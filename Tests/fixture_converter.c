// SPDX-License-Identifier: MIT
// Synthetic converter for testing the wrapper; never installed.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 6 && argc != 7) return 2;
    if (!strcmp(argv[5], "fail")) return 7;
    FILE *input = argc == 7 ? fopen(argv[6], "rb") : stdin;
    if (!input) return 3;
    unsigned char bytes[4096];
    size_t size;
    while ((size = fread(bytes, 1, sizeof(bytes), input)) > 0) {
        if (fwrite(bytes, 1, size, stdout) != size) return 4;
    }
    return ferror(input) ? 5 : 0;
}
