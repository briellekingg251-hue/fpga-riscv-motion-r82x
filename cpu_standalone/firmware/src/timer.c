#include "p1_mmio.h"
#include "p1_timer.h"

uint64_t p1_timer_read(void)
{
    uint32_t high_a;
    uint32_t low;
    uint32_t high_b;

    do {
        high_a = P1_TIMER_HIGH;
        low = P1_TIMER_LOW;
        high_b = P1_TIMER_HIGH;
    } while (high_a != high_b);

    return ((uint64_t)high_a << 32) | (uint64_t)low;
}
