#ifndef SSB_GIT_REMOTE_CORE_H
#define SSB_GIT_REMOTE_CORE_H

#include <stddef.h>
#include <stdio.h>
#include <sys/types.h>

#define SSB_GIT_REMOTE_MAX_LINE 1024

void ssb_git_remote_resolve_socket_path_for_values(char *path,
                                                   size_t path_size,
                                                   const char *xdg_state_home,
                                                   const char *xdg_data_home,
                                                   const char *home);
void ssb_git_remote_resolve_socket_path(char *path, size_t path_size);
int ssb_git_remote_connect_to_app(void);

int ssb_git_remote_write_all(int fd, const void *buf, size_t len);
int ssb_git_remote_read_full(int fd, void *buf, size_t len);
ssize_t ssb_git_remote_read_line_fd(int fd, char *buf, size_t size);

int ssb_git_remote_parse_fetch_request(const char *line,
                                       char *sha,
                                       size_t sha_size,
                                       char *name,
                                       size_t name_size);
int ssb_git_remote_parse_push_request(const char *line,
                                      char *src,
                                      size_t src_size,
                                      char *dst,
                                      size_t dst_size);
int ssb_git_remote_extract_repo_id(const char *url, char *repo_id, size_t repo_id_size);

void ssb_git_remote_handle_list(int app_fd, const char *repo_id);
void ssb_git_remote_handle_fetch(int app_fd, const char *repo_id, const char *sha);
void ssb_git_remote_handle_push(int app_fd, const char *repo_id, const char *ref, const char *sha);

int ssb_git_remote_run(int argc, char **argv);

#endif
