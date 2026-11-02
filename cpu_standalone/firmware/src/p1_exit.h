#ifndef P1_EXIT_H
#define P1_EXIT_H

#include <stdint.h>

#define P1_EXIT_FAIL 0u
#define P1_EXIT_PASS 1u

void p1_exit(uint32_t code);

#endif
