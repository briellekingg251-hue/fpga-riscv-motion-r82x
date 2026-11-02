/* P1 CoreMark timer and target lifecycle port. */
#include "coremark.h"
#include "core_portme.h"

#include "p1_exit.h"
#include "p1_timer.h"
#include "p1_uart.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#elif PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#elif PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif

volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

static CORE_TICKS start_time_val;
static CORE_TICKS stop_time_val;

void start_time(void)
{
    p1_uart_puts("TIMING_BEGIN\n");
    p1_uart_flush();
    start_time_val = p1_timer_read();
}

void stop_time(void)
{
    stop_time_val = p1_timer_read();
    p1_uart_puts("TIMING_END\n");
}

CORE_TICKS get_time(void)
{
    return stop_time_val - start_time_val;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
#if HAS_FLOAT
    return (secs_ret)ticks / (secs_ret)CLOCK_HZ;
#else
    return (secs_ret)(ticks / (CORE_TICKS)CLOCK_HZ);
#endif
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    p->portable_id = 1;
}

/* Hardware performance counters (SoC MMIO, 64-bit lo/hi words, see o2_soc). */
#define PERF_BASE 0x10003000u
static ee_u32 perf_rd32(ee_u32 off) { return *(volatile ee_u32 *)(PERF_BASE + off); }
static unsigned long long perf_rd64(ee_u32 idx)
{
    ee_u32 lo = perf_rd32(8u * idx), hi = perf_rd32(8u * idx + 4u);
    return ((unsigned long long)hi << 32) | lo;
}
static void put_u64(const char *label, unsigned long long v)
{
    char buf[24];
    int n = 0;
    do { buf[n++] = (char)('0' + (int)(v % 10u)); v /= 10u; } while (v != 0u);
    p1_uart_puts(label);
    while (n > 0) { char c[2] = { buf[--n], 0 }; p1_uart_puts(c); }
    p1_uart_puts("\n");
}

void portable_fini(core_portable *p)
{
    p->portable_id = 0;
    *(volatile ee_u32 *)PERF_BASE = 0u;          /* freeze the counters */
    unsigned long long cyc = perf_rd64(1), ins = perf_rd64(2), icm = perf_rd64(3);
    unsigned long long lda = perf_rd64(4), ldm = perf_rd64(5), fes = perf_rd64(6), bes = perf_rd64(7);
    ee_printf("\n");
    put_u64("Total cycles: ", cyc);
    put_u64("Total instructions: ", ins);
    put_u64("I-Cache Miss: ", icm);
    put_u64("D-Cache Load Miss: ", ldm);
    put_u64("D-Cache Load Access: ", lda);
    put_u64("Stalled frontend cycles: ", fes);
    put_u64("Stalled backend cycles: ", bes);
#if HAS_FLOAT
    double c = (double)cyc;
    ee_printf("IPC: %.3f\n", (double)ins / c);
    ee_printf("I-Cache miss rate: %.3f%%\n", 100.0 * (double)icm / (double)(ins ? ins : 1u));
    ee_printf("D-Cache load miss rate: %.3f%%\n", 100.0 * (double)ldm / (double)(lda ? lda : 1u));
    ee_printf("Stalled frontend rate: %.3f%%\n", 100.0 * (double)fes / c);
    ee_printf("Stalled backend rate: %.3f%%\n", 100.0 * (double)bes / c);
#endif
    p1_uart_flush();
    p1_exit(P1_EXIT_PASS);
}

/* These symbols satisfy the official interface.  P1 uses MEM_STATIC, so a
 * call indicates a port/build configuration error rather than heap support. */
void *portable_malloc(ee_size_t size)
{
    (void)size;
    return (void *)0;
}

void portable_free(void *p)
{
    (void)p;
}
