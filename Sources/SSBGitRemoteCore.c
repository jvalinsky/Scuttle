#include "SSBGitRemoteCore.h"

#include <errno.h>
#include <limits.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static int ssb_git_remote_connect_to_path(const char *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd == -1) {
        return -1;
    }

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

void ssb_git_remote_resolve_socket_path_for_values(char *path,
                                                   size_t path_size,
                                                   const char *xdg_state_home,
                                                   const char *xdg_data_home,
                                                   const char *home) {
    if (!path || path_size == 0) {
        return;
    }

    if (xdg_state_home && xdg_state_home[0] != '\0') {
        snprintf(path, path_size, "%s/scuttle/scuttle_helper.sock", xdg_state_home);
        return;
    }

    if (xdg_data_home && xdg_data_home[0] != '\0') {
        snprintf(path, path_size, "%s/scuttle/scuttle_helper.sock", xdg_data_home);
        return;
    }

    if (!home || home[0] == '\0') {
        struct passwd *entry = getpwuid(getuid());
        if (entry && entry->pw_dir) {
            home = entry->pw_dir;
        } else {
            home = "";
        }
    }
    snprintf(path, path_size, "%s/.local/state/scuttle/scuttle_helper.sock", home);
}

void ssb_git_remote_resolve_socket_path(char *path, size_t path_size) {
    ssb_git_remote_resolve_socket_path_for_values(path,
                                                  path_size,
                                                  getenv("XDG_STATE_HOME"),
                                                  getenv("XDG_DATA_HOME"),
                                                  getenv("HOME"));
}

int ssb_git_remote_connect_to_app(void) {
    char path[256];
    ssb_git_remote_resolve_socket_path(path, sizeof(path));
    return ssb_git_remote_connect_to_path(path);
}

int ssb_git_remote_write_all(int fd, const void *buf, size_t len) {
    const unsigned char *cursor = (const unsigned char *)buf;
    size_t written = 0;

    while (written < len) {
        ssize_t n = write(fd, cursor + written, len - written);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        if (n == 0) {
            return -1;
        }
        written += (size_t)n;
    }

    return 0;
}

int ssb_git_remote_read_full(int fd, void *buf, size_t len) {
    unsigned char *cursor = (unsigned char *)buf;
    size_t read_total = 0;

    while (read_total < len) {
        ssize_t n = read(fd, cursor + read_total, len - read_total);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        if (n == 0) {
            return -1;
        }
        read_total += (size_t)n;
    }

    return 0;
}

ssize_t ssb_git_remote_read_line_fd(int fd, char *buf, size_t size) {
    size_t used = 0;

    if (size == 0) {
        return -1;
    }

    while (used + 1 < size) {
        char ch = '\0';
        ssize_t n = read(fd, &ch, 1);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
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

int ssb_git_remote_parse_fetch_request(const char *line,
                                       char *sha,
                                       size_t sha_size,
                                       char *name,
                                       size_t name_size) {
    if (!line || !sha || !name || sha_size == 0 || name_size == 0) {
        return 0;
    }
    return sscanf(line, "fetch %1023s %1023s", sha, name) == 2;
}

int ssb_git_remote_parse_push_request(const char *line,
                                      char *src,
                                      size_t src_size,
                                      char *dst,
                                      size_t dst_size) {
    if (!line || !src || !dst || src_size == 0 || dst_size == 0) {
        return 0;
    }
    return sscanf(line, "push %1023[^:]:%1023s", src, dst) == 2;
}

int ssb_git_remote_extract_repo_id(const char *url, char *repo_id, size_t repo_id_size) {
    const char *prefix = "ssb://";
    size_t prefix_len = strlen(prefix);

    if (!url || !repo_id || repo_id_size == 0) {
        return 0;
    }
    if (strncmp(url, prefix, prefix_len) != 0) {
        return 0;
    }

    snprintf(repo_id, repo_id_size, "%s", url + prefix_len);
    return repo_id[0] != '\0';
}

static void ssb_git_remote_close_if_valid(int fd) {
    if (fd >= 0) {
        close(fd);
    }
}

void ssb_git_remote_handle_list(int app_fd, const char *repo_id) {
    char cmd[SSB_GIT_REMOTE_MAX_LINE];
    snprintf(cmd, sizeof(cmd), "LIST %s\n", repo_id);
    if (ssb_git_remote_write_all(app_fd, cmd, strlen(cmd)) != 0) {
        return;
    }

    char line[SSB_GIT_REMOTE_MAX_LINE];
    while (ssb_git_remote_read_line_fd(app_fd, line, sizeof(line)) > 0) {
        if (strcmp(line, "END\n") == 0 || strcmp(line, "END") == 0) {
            break;
        }
        char ref[SSB_GIT_REMOTE_MAX_LINE];
        char sha[SSB_GIT_REMOTE_MAX_LINE];
        if (sscanf(line, "%1023s %1023s", ref, sha) == 2) {
            printf("%s %s\n", sha, ref);
        }
    }
    printf("\n");
    fflush(stdout);
}

void ssb_git_remote_handle_fetch(int app_fd, const char *repo_id, const char *sha) {
    char cmd[SSB_GIT_REMOTE_MAX_LINE];
    snprintf(cmd, sizeof(cmd), "FETCH_SHA %s %s\n", repo_id, sha);
    if (ssb_git_remote_write_all(app_fd, cmd, strlen(cmd)) != 0) {
        return;
    }

    char line[SSB_GIT_REMOTE_MAX_LINE];
    if (ssb_git_remote_read_line_fd(app_fd, line, sizeof(line)) <= 0) {
        return;
    }

    if (strncmp(line, "SEND_PACK ", 10) == 0) {
        char *endptr = NULL;
        errno = 0;
        unsigned long long size = strtoull(line + 10, &endptr, 10);
        if (errno != 0 || endptr == line + 10) {
            return;
        }

        int pipe_fds[2];
        if (pipe(pipe_fds) != 0) {
            return;
        }

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
            if (ssb_git_remote_read_full(app_fd, buf, chunk) != 0) {
                break;
            }
            if (ssb_git_remote_write_all(pipe_fds[1], buf, chunk) != 0) {
                break;
            }
            total += chunk;
        }
        close(pipe_fds[1]);
        waitpid(pid, NULL, 0);
    }
}

void ssb_git_remote_handle_push(int app_fd, const char *repo_id, const char *ref, const char *sha) {
    char tmp_pack[] = "/tmp/ssb_push_XXXXXX.pack";
    int pack_fd = mkstemps(tmp_pack, 5);
    if (pack_fd == -1) {
        return;
    }

    int rev_pipe[2] = { -1, -1 };
    int pack_pipe[2] = { -1, -1 };
    if (pipe(rev_pipe) != 0 || pipe(pack_pipe) != 0) {
        ssb_git_remote_close_if_valid(rev_pipe[0]);
        ssb_git_remote_close_if_valid(rev_pipe[1]);
        ssb_git_remote_close_if_valid(pack_pipe[0]);
        ssb_git_remote_close_if_valid(pack_pipe[1]);
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
        if (ssb_git_remote_write_all(pack_fd, buf, (size_t)n) != 0) {
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
    size_t idx_size = (size_t)ftell(idx_fp);
    fseek(idx_fp, 0, SEEK_SET);
    unsigned char *idx_data = malloc(idx_size);
    if (!idx_data) {
        fclose(idx_fp);
        unlink(tmp_pack);
        unlink(tmp_idx);
        return;
    }
    fread(idx_data, 1, idx_size, idx_fp);
    fclose(idx_fp);

    FILE *pack_fp = fopen(tmp_pack, "rb");
    if (!pack_fp) {
        free(idx_data);
        unlink(tmp_pack);
        unlink(tmp_idx);
        return;
    }
    unsigned char *pack_data = malloc(pack_size);
    if (!pack_data) {
        fclose(pack_fp);
        free(idx_data);
        unlink(tmp_pack);
        unlink(tmp_idx);
        return;
    }
    fread(pack_data, 1, pack_size, pack_fp);
    fclose(pack_fp);

    char push_cmd[SSB_GIT_REMOTE_MAX_LINE];
    snprintf(push_cmd, sizeof(push_cmd), "PUSH %s %s %s %zu %zu\n", repo_id, ref, sha, pack_size, idx_size);
    if (ssb_git_remote_write_all(app_fd, push_cmd, strlen(push_cmd)) != 0 ||
        ssb_git_remote_write_all(app_fd, pack_data, pack_size) != 0 ||
        ssb_git_remote_write_all(app_fd, idx_data, idx_size) != 0) {
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

    char resp[SSB_GIT_REMOTE_MAX_LINE];
    if (ssb_git_remote_read_line_fd(app_fd, resp, sizeof(resp)) > 0) {
        if (strcmp(resp, "OK\n") == 0 || strcmp(resp, "OK") == 0) {
            printf("ok %s\n", ref);
        } else {
            printf("error %s %s", ref, resp);
        }
    }
}

int ssb_git_remote_run(int argc, char **argv) {
    if (argc < 3) {
        return 1;
    }

    char repo_id[SSB_GIT_REMOTE_MAX_LINE];
    if (!ssb_git_remote_extract_repo_id(argv[2], repo_id, sizeof(repo_id))) {
        fprintf(stderr, "Error: expected remote URL in form ssb://<repo-id>\n");
        return 1;
    }

    int app_fd = ssb_git_remote_connect_to_app();
    if (app_fd == -1) {
        fprintf(stderr, "Error: Scuttle app is not running.\n");
        return 1;
    }

    char line[SSB_GIT_REMOTE_MAX_LINE];
    while (fgets(line, sizeof(line), stdin)) {
        if (strcmp(line, "capabilities\n") == 0) {
            printf("list\n");
            printf("fetch\n");
            printf("push\n");
            printf("\n");
        } else if (strncmp(line, "list", 4) == 0) {
            ssb_git_remote_handle_list(app_fd, repo_id);
        } else if (strncmp(line, "fetch ", 6) == 0) {
            char sha[SSB_GIT_REMOTE_MAX_LINE];
            char name[SSB_GIT_REMOTE_MAX_LINE];
            if (ssb_git_remote_parse_fetch_request(line, sha, sizeof(sha), name, sizeof(name))) {
                ssb_git_remote_handle_fetch(app_fd, repo_id, sha);
            }
            printf("\n");
        } else if (strncmp(line, "push ", 5) == 0) {
            char src[SSB_GIT_REMOTE_MAX_LINE];
            char dst[SSB_GIT_REMOTE_MAX_LINE];
            if (ssb_git_remote_parse_push_request(line, src, sizeof(src), dst, sizeof(dst))) {
                char sha_cmd[SSB_GIT_REMOTE_MAX_LINE];
                snprintf(sha_cmd, sizeof(sha_cmd), "git rev-parse %s", src);
                FILE *process = popen(sha_cmd, "r");
                if (process) {
                    char sha[SSB_GIT_REMOTE_MAX_LINE];
                    if (fgets(sha, sizeof(sha), process)) {
                        size_t len = strlen(sha);
                        if (len > 0 && sha[len - 1] == '\n') {
                            sha[len - 1] = '\0';
                        }
                        ssb_git_remote_handle_push(app_fd, repo_id, dst, sha);
                    }
                    pclose(process);
                }
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
