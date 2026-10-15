// SPDX-License-Identifier: MIT
// Simulates only the documented CUPS side-channel handshake. Never installed.
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 4) return 90;
    int pair[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair)) return 91;
    pid_t child = fork();
    if (child < 0) return 92;
    if (!child) {
        close(pair[0]);
        if (pair[1] != 4) { if (dup2(pair[1], 4) < 0) _exit(93); close(pair[1]); }
        execl(argv[1], argv[1], "1", "test-user", "synthetic", "1", "test", argv[2], NULL);
        _exit(94);
    }
    close(pair[1]);
    unsigned char request[4];
    size_t have = 0;
    while (have < sizeof(request)) {
        ssize_t count = read(pair[0], request + have, sizeof(request) - have);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return 95;
        have += (size_t)count;
    }
    if (request[0] != 3 || request[2] != 0 || request[3] != 0) return 96;
    unsigned char response[5] = {3, (unsigned char)atoi(argv[3]), 0, 1, 1};
    if (write(pair[0], response, sizeof(response)) != sizeof(response)) return 97;
    close(pair[0]);
    int status;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    return WIFEXITED(status) ? WEXITSTATUS(status) : 98;
}
