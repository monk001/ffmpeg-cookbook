/* Copyright 2018 lzy0168@gmail.com */

#include <assert.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char** argv) {
  if (argc != 2) {
    printf("usage:\n");
    printf("  %s fname\n", argv[0]);
    return -1;
  } else if (access(argv[1], F_OK) == -1) {
    printf("file %s doesn't exists!\n", argv[0]);
    return -2;
  } else {
    FILE* f = fopen(argv[1], "r");
    printf("char a[] = {\n");
    unsigned long n = 0;
    while (!feof(f)) {
      unsigned char c;
      if(fread(&c, 1, 1, f) == 0)
        break;
      printf("0x%.2X,", (int)c);
      ++n;
      if(n % 10 == 0)
        printf("\n");
    }
    fclose(f);
    printf("};\n");
    return 0;
  }
}
