#include "p1_mmio.h"
#include "p1_exit.h"

void p1_exit(uint32_t code)
{
    P1_EXIT_CODE = code;
}
