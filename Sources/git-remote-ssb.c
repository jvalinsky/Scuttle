#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <pwd.h>
#include <sys/wait.h>

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

void handle_list(int app_fd, const char *repo_id) {
    char cmd[MAX_LINE];
    snprintf(cmd, sizeof(cmd), "LIST %s\n", repo_id);
    write(app_fd, cmd, strlen(cmd));
    
    char line[MAX_LINE];
    FILE *fp = fdopen(dup(app_fd), "r");
    while (fgets(line, sizeof(line), fp)) {
        if (strcmp(line, "END\n") == 0) break;
        char ref[MAX_LINE], sha[MAX_LINE];
        if (sscanf(line, "%s %s", ref, sha) == 2) {
            printf("%s %s\n", sha, ref);
        }
    }
    printf("\n");
    fflush(stdout);
    fclose(fp);
}

void handle_fetch(int app_fd, const char *repo_id, const char *sha) {
    char cmd[MAX_LINE];
    snprintf(cmd, sizeof(cmd), "FETCH_SHA %s %s\n", repo_id, sha);
    write(app_fd, cmd, strlen(cmd));
    
    char line[MAX_LINE];
    FILE *fp = fdopen(dup(app_fd), "r");
    if (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "SEND_PACK ", 10) == 0) {
            size_t size = atol(line + 10);
            
            int pipe_fds[2];
            pipe(pipe_fds);
            
            if (fork() == 0) {
                close(pipe_fds[1]);
                dup2(pipe_fds[0], 0);
                execlp("git", "git", "index-pack", "--stdin", NULL);
                exit(1);
            }
            
            close(pipe_fds[0]);
            
            unsigned char buf[4096];
            size_t total = 0;
            while (total < size) {
                size_t to_read = (size - total > sizeof(buf)) ? sizeof(buf) : size - total;
                ssize_t n = read(app_fd, buf, to_read);
                if (n <= 0) break;
                write(pipe_fds[1], buf, n);
                total += n;
            }
            close(pipe_fds[1]);
            wait(NULL);
        }
    }
    fclose(fp);
}

void handle_push(int app_fd, const char *repo_id, const char *ref, const char *sha) {
    char tmp_pack[] = "/tmp/ssb_push_XXXXXX.pack";
    int pack_fd = mkstemps(tmp_pack, 5);
    if (pack_fd == -1) return;
    
    int pipe_fds[2];
    pipe(pipe_fds);
    
    pid_t pid = fork();
    if (pid == 0) {
        close(pipe_fds[0]);
        dup2(pipe_fds[1], 1);
        printf("%s\n", sha);
        execlp("git", "git", "pack-objects", "--stdout", "--thin", "--revs", NULL);
        exit(1);
    }
    
    close(pipe_fds[1]);
    
    size_t pack_size = 0;
    unsigned char buf[4096];
    ssize_t n;
    while ((n = read(pipe_fds[0], buf, sizeof(buf))) > 0) {
        write(pack_fd, buf, n);
        pack_size += n;
    }
    close(pipe_fds[0]);
    wait(NULL);
    close(pack_fd);
    
    char tmp_idx[256];
    snprintf(tmp_idx, sizeof(tmp_idx), "%.*s.idx", (int)(strlen(tmp_pack) - 5), tmp_pack);
    
    pid_t idx_pid = fork();
    if (idx_pid == 0) {
        execlp("git", "git", "index-pack", "-o", tmp_idx, tmp_pack, NULL);
        exit(1);
    }
    wait(NULL);
    
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
    write(app_fd, push_cmd, strlen(push_cmd));
    
    write(app_fd, pack_data, pack_size);
    write(app_fd, idx_data, idx_size);
    
    free(pack_data);
    free(idx_data);
    unlink(tmp_pack);
    unlink(tmp_idx);
    
    char resp[MAX_LINE];
    n = read(app_fd, resp, sizeof(resp) - 1);
    if (n > 0) {
        resp[n] = 0;
        if (strcmp(resp, "OK\n") == 0) {
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
