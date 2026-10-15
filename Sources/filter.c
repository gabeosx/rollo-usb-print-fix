// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rollo USB Pacing contributors

#include <cups/sidechannel.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;
#ifndef ROLLO_VENDOR_CONVERTER
#define ROLLO_VENDOR_CONVERTER "/Library/Printers/Rollo/rastertorollo"
#endif
static volatile sig_atomic_t cancelled;
static void cancel_print(int signum) { (void)signum; cancelled = 1; }

static void stop_child(pid_t child) {
    kill(child, SIGTERM);
    for (int i = 0; i < 40; i++) {
        int status;
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child || (result < 0 && errno == ECHILD)) return;
        struct timespec pause = {0, 50000000};
        nanosleep(&pause, NULL);
    }
    kill(child, SIGKILL);
    while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
}

int main(int argc, char **argv) {
    if (argc != 6 && argc != 7) {
        fputs("ERROR: Usage: rastertorollo-paced job-id user title copies options [file]\n", stderr);
        return 1;
    }
    struct sigaction action = {0};
    action.sa_handler = cancel_print;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    signal(SIGPIPE, SIG_IGN);

    /* A read-only side-channel query ensures the backend has opened the
       device before the first paced bytes, as in the successful diagnostic. */
    struct stat side;
    if (fstat(CUPS_SC_FD, &side) == 0 && S_ISSOCK(side.st_mode)) {
        char bidi = 0;
        int length = 1;
        cups_sc_status_t status = cupsSideChannelDoRequest(
            CUPS_SC_CMD_GET_BIDI, &bidi, &length, 15.0);
        if (status != CUPS_SC_STATUS_OK) {
            fprintf(stderr, "ERROR: Rollo pacing backend readiness failed (status %d); no print data sent.\n", status);
            return 1;
        }
        fputs("DEBUG: Rollo pacing backend readiness confirmed.\n", stderr);
    }
    if (cancelled) return 1;

    int raw_pipe[2];
    if (pipe(raw_pipe) < 0) { perror("ERROR: Rollo pacing pipe"); return 1; }
    /* CUPS reserves descriptors 3 and 4 for back/side channels. */
    int reader = fcntl(raw_pipe[0], F_DUPFD_CLOEXEC, 5);
    int writer = fcntl(raw_pipe[1], F_DUPFD_CLOEXEC, 5);
    close(raw_pipe[0]); close(raw_pipe[1]);
    if (reader < 0 || writer < 0) {
        if (reader >= 0) close(reader);
        if (writer >= 0) close(writer);
        perror("ERROR: Rollo pacing descriptors"); return 1;
    }

    posix_spawn_file_actions_t files;
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&files);
    posix_spawn_file_actions_adddup2(&files, writer, STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&files, reader);
    posix_spawn_file_actions_addclose(&files, writer);
    posix_spawnattr_init(&attributes);
    sigset_t defaults;
    sigemptyset(&defaults); sigaddset(&defaults, SIGPIPE);
    posix_spawnattr_setsigdefault(&attributes, &defaults);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSIGDEF);
    pid_t child;
    int error = posix_spawn(&child, ROLLO_VENDOR_CONVERTER,
                           &files, &attributes, argv, environ);
    posix_spawn_file_actions_destroy(&files);
    posix_spawnattr_destroy(&attributes);
    close(writer);
    if (error) {
        close(reader); errno = error;
        perror("ERROR: Original Rollo converter could not start"); return 1;
    }

    /* The converter retains the original input and options. This process
       forwards its stdout unchanged, with bounded writes and pacing. */
    close(STDIN_FILENO);
    unsigned char buffer[512];
    size_t total = 0;
    int failed = 0;
    while (!cancelled) {
        ssize_t count = read(reader, buffer, sizeof(buffer));
        if (count < 0) {
            if (errno == EINTR) continue;
            perror("ERROR: Rollo pacing input"); failed = 1; break;
        }
        if (count == 0) break;
        ssize_t offset = 0;
        while (offset < count && !cancelled) {
            ssize_t written = write(STDOUT_FILENO, buffer + offset, (size_t)(count - offset));
            if (written < 0) {
                if (errno == EINTR) continue;
                perror("ERROR: Rollo pacing output"); failed = 1; break;
            }
            if (written == 0) { failed = 1; break; }
            offset += written; total += (size_t)written;
        }
        if (failed || cancelled) break;
        struct timespec pause = {0, 20000000};
        while (nanosleep(&pause, &pause) < 0 && errno == EINTR && !cancelled) {}
    }
    close(reader);
    if (failed || cancelled) {
        stop_child(child);
        fputs("ERROR: Rollo pacing stopped; job is not confirmed printed.\n", stderr);
        return 1;
    }
    int status;
    while (waitpid(child, &status, 0) < 0) {
        if (errno == EINTR) {
            if (cancelled) { stop_child(child); return 1; }
            continue;
        }
        perror("ERROR: Rollo converter status"); return 1;
    }
    fprintf(stderr, "DEBUG: Rollo pacing forwarded %zu unchanged bytes in <=512-byte writes with 20 ms spacing.\n", total);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
