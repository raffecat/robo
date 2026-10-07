#include <stdio.h>
#include <stdlib.h>

size_t read_binary_file(const char *filename, char* buffer, size_t buf_size) {
    FILE *file = fopen(filename, "rb");

    if (!file) {
        perror("fopen");
        return 0;
    }

    // Seek to end to get file size
    if (fseek(file, 0, SEEK_END) != 0) {
        perror("fseek");
        fclose(file);
        return 0;
    }

    long size = ftell(file);
    if (size < 0) {
        perror("ftell");
        fclose(file);
        return 0;
    }
    if ((size_t)size > buf_size) {
        fprintf(stderr, "%s too big", filename);
        fclose(file);
        return 0;
    }
    rewind(file); // Go back to start

    // Read into buffer
    size_t read = fread(buffer, 1, (size_t)size, file);
    if (read != (size_t)size) {
        perror("fread");
        free(buffer);
        fclose(file);
        return 0;
    }

    fclose(file);
    return (size_t)size;
}
