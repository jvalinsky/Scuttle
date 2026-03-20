#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <pwd.h>
#include <sys/wait.h>
#include <errno.h>
#include <limits.h>

#define MAX_LINE 1024

static void resolve_socket_path(char *path, size_t path_size) {
    const char *xdg_state = getenv("XDG_STATE_HOME");
    if (xdg_state && xdg_state[0] != '\0') {
        snprintf(path, path_size, "%s/scuttle/scuttle_helper.sock", xdg_state);
        return;
    }

    const char *xdg_data = getenv("XDG_DATA_HOME");
    if (xdg_data && xdg_data[0] != '\0') {
        snprintf(path, path_size, "%s/scuttle/scuttle_helper.sock", xdg_data);
        return;
    }

    const char *home = getenv("HOME");
    if (!home) home = getpwuid(getuid())->pw_dir;
    snprintf(path, path_size, "%s/.local/state/scuttle/scuttle_helper.sock", home);
}

int connect_to_app(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd == -1) return -1;

    char path[256];
    resolve_socket_path(path, sizeof(path));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        close(fd);
        return -1;
    }
    return fd;
}

static int write_all(int fd, const void *buf, size_t len) {
    const unsigned char *cursor = (const unsigned char *)buf;
    size_t written = 0;

    while (written < len) {
        ssize_t n = write(fd, cursor + written, len - written);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (n == 0) {
            return -1;
        }
        written += (size_t)n;
    }

    return 0;
}

static int read_full(int fd, void *buf, size_t len) {
    unsigned char *cursor = (unsigned char *)buf;
    size_t read_total = 0;

    while (read_total < len) {
        ssize_t n = read(fd, cursor + read_total, len - read_total);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (n == 0) {
            return -1;
        }
        read_total += (size_t)n;
    }

    return 0;
}

static ssize_t read_line_fd(int fd, char *buf, size_t size) {
    size_t used = 0;

    if (size == 0) return -1;

    while (used + 1 < size) {
        char ch = '\0';
        ssize_t n = read(fd, &ch, 1);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (n == 0) {
            break;
        }

        buf[used++] = ch;
        if (ch == '\n') {
            break;
        }
    }

    buf[used] = '\0';
    return (ssize_t)used;
}

static void close_if_valid(int fd) {
    if (fd >= 0) {
        close(fd);
    }
}

void handle_list(int app_fd, const char *repo_id) {
    char cmd[MAX_LINE];
    snprintf(cmd, sizeof(cmd), "LIST %s\n", repo_id);
    if (write_all(app_fd, cmd, strlen(cmd)) != 0) return;
    
    char line[MAX_LINE];
    while (read_line_fd(app_fd, line, sizeof(line)) > 0) {
        if (strcmp(line, "END\n") == 0 || strcmp(line, "END") == 0) break;
        char ref[MAX_LINE], sha[MAX_LINE];
        if (sscanf(line, "%s %s", ref, sha) == 2) {
            printf("%s %s\n", sha, ref);
        }
    }
    printf("\n");
    fflush(stdout);
}

void handle_fetch(int app_fd, const char *repo_id, const char *sha) {
    char cmd[MAX_LINE];
    snprintf(cmd, sizeof(cmd), "FETCH_SHA %s %s\n", repo_id, sha);
    if (write_all(app_fd, cmd, strlen(cmd)) != 0) return;
    
    char line[MAX_LINE];
    if (read_line_fd(app_fd, line, sizeof(line)) <= 0) return;

    if (strncmp(line, "SEND_PACK ", 10) == 0) {
        char *endptr = NULL;
        errno = 0;
        unsigned long long size = strtoull(line + 10, &endptr, 10);
        if (errno != 0 || endptr == line + 10) {
            return;
        }

        int pipe_fds[2];
        if (pipe(pipe_fds) != 0) return;

        pid_t pid = fork();
        if (pid == 0) {
            close(pipe_fds[1]);
            dup2(pipe_fds[0], STDIN_FILENO);
            close(pipe_fds[0]);
            execlp("git", "git", "index-pack", "--stdin", NULL);
            _exit(1);
        }
        if (pid < 0) {
            close(pipe_fds[0]);
            close(pipe_fds[1]);
            return;
        }

        close(pipe_fds[0]);

        unsigned char buf[4096];
        size_t total = 0;
        while (total < size) {
            size_t remaining = (size_t)(size - total);
            size_t chunk = (remaining > sizeof(buf)) ? sizeof(buf) : remaining;
            if (read_full(app_fd, buf, chunk) != 0) break;
            if (write_all(pipe_fds[1], buf, chunk) != 0) break;
            total += chunk;
        }
        close(pipe_fds[1]);
        waitpid(pid, NULL, 0);
    }
}

void handle_push(int app_fd, const char *repo_id, const char *ref, const char *sha) {
    char tmp_pack[] = "/tmp/ssb_push_XXXXXX.pack";
    int pack_fd = mkstemps(tmp_pack, 5);
    if (pack_fd == -1) return;
    
    int rev_pipe[2] = { -1, -1 };
    int pack_pipe[2] = { -1, -1 };
    if (pipe(rev_pipe) != 0 || pipe(pack_pipe) != 0) {
        close_if_valid(rev_pipe[0]);
        close_if_valid(rev_pipe[1]);
        close_if_valid(pack_pipe[0]);
        close_if_valid(pack_pipe[1]);
        close(pack_fd);
        unlink(tmp_pack);
        return;
    }
    
    pid_t pid = fork();
    if (pid == 0) {
        close(rev_pipe[1]);
        close(pack_pipe[0]);
        dup2(rev_pipe[0], STDIN_FILENO);
        dup2(pack_pipe[1], STDOUT_FILENO);
        close(rev_pipe[0]);
        close(pack_pipe[1]);
        execlp("git", "git", "pack-objects", "--stdout", "--revs", NULL);
        _exit(1);
    }
    if (pid < 0) {
        close(rev_pipe[0]);
        close(rev_pipe[1]);
        close(pack_pipe[0]);
        close(pack_pipe[1]);
        close(pack_fd);
        unlink(tmp_pack);
        return;
    }
    
    close(rev_pipe[0]);
    close(pack_pipe[1]);
    dprintf(rev_pipe[1], "%s\n", sha);
    close(rev_pipe[1]);
    
    size_t pack_size = 0;
    unsigned char buf[4096];
    ssize_t n;
    while ((n = read(pack_pipe[0], buf, sizeof(buf))) > 0) {
        if (write_all(pack_fd, buf, (size_t)n) != 0) {
            n = -1;
            break;
        }
        pack_size += (size_t)n;
    }
    close(pack_pipe[0]);
    waitpid(pid, NULL, 0);
    close(pack_fd);
    
    if (n < 0 || pack_size == 0) {
        unlink(tmp_pack);
        return;
    }

    char tmp_idx[PATH_MAX];
    snprintf(tmp_idx, sizeof(tmp_idx), "%.*s.idx", (int)(strlen(tmp_pack) - 5), tmp_pack);
    
    pid_t idx_pid = fork();
    if (idx_pid == 0) {
        execlp("git", "git", "index-pack", "-o", tmp_idx, tmp_pack, NULL);
        _exit(1);
    }
    if (idx_pid < 0) {
        unlink(tmp_pack);
        return;
    }
    waitpid(idx_pid, NULL, 0);
    
    FILE *idx_fp = fopen(tmp_idx, "rb");
    if (!idx_fp) {
        unlink(tmp_pack);
        return;
    }
    fseek(idx_fp, 0, SEEK_END);
    size_t idx_size = ftell(idx_fp);
    fseek(idx_fp, 0, SEEK_SET);
    unsigned char *idx_data = malloc(idx_size);
    fread(idx_data, 1, idx_size, idx_fp);
    fclose(idx_fp);
    
    FILE *pack_fp = fopen(tmp_pack, "rb");
    unsigned char *pack_data = malloc(pack_size);
    fread(pack_data, 1, pack_size, pack_fp);
    fclose(pack_fp);
    
    char push_cmd[MAX_LINE];
    snprintf(push_cmd, sizeof(push_cmd), "PUSH %s %s %s %zu %zu\n", repo_id, ref, sha, pack_size, idx_size);
    if (write_all(app_fd, push_cmd, strlen(push_cmd)) != 0 ||
        write_all(app_fd, pack_data, pack_size) != 0 ||
        write_all(app_fd, idx_data, idx_size) != 0) {
        free(pack_data);
        free(idx_data);
        unlink(tmp_pack);
        unlink(tmp_idx);
        return;
    }
    
    free(pack_data);
    free(idx_data);
    unlink(tmp_pack);
    unlink(tmp_idx);
    
    char resp[MAX_LINE];
    if (read_line_fd(app_fd, resp, sizeof(resp)) > 0) {
        if (strcmp(resp, "OK\n") == 0 || strcmp(resp, "OK") == 0) {
            printf("ok %s\n", ref);
        } else {
            printf("error %s %s", ref, resp);
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    const char *url = argv[2];
    const char *repo_id = url + 6;
    
    int app_fd = connect_to_app();
    if (app_fd == -1) {
        fprintf(stderr, "Error: Scuttle app is not running.\n");
        return 1;
    }
    
    char line[MAX_LINE];
    while (fgets(line, sizeof(line), stdin)) {
        if (strcmp(line, "capabilities\n") == 0) {
            printf("list\n");
            printf("fetch\n");
            printf("push\n");
            printf("\n");
        } else if (strncmp(line, "list", 4) == 0) {
            handle_list(app_fd, repo_id);
        } else if (strncmp(line, "fetch ", 6) == 0) {
            char sha[MAX_LINE], name[MAX_LINE];
            sscanf(line + 6, "%s %s", sha, name);
            handle_fetch(app_fd, repo_id, sha);
            printf("\n");
        } else if (strncmp(line, "push ", 5) == 0) {
            char src[MAX_LINE], dst[MAX_LINE];
            if (sscanf(line + 5, "%[^:]:%s", src, dst) == 2) {
                char sha_cmd[MAX_LINE];
                snprintf(sha_cmd, sizeof(sha_cmd), "git rev-parse %s", src);
                FILE *p = popen(sha_cmd, "r");
                char sha[MAX_LINE];
                if (fgets(sha, sizeof(sha), p)) {
                    sha[strlen(sha)-1] = 0;
                    handle_push(app_fd, repo_id, dst, sha);
                }
                pclose(p);
            }
            printf("\n");
        } else if (strcmp(line, "\n") == 0) {
            // Batch end
        }
        fflush(stdout);
    }
    
    close(app_fd);
    return 0;
}
