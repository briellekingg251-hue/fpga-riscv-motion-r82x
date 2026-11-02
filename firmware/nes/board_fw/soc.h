/* SoC memory map of the s80 CPU + Fruit Ninja display engine. */
#ifndef FN_SOC_H
#define FN_SOC_H

#include <stdint.h>

#ifndef MMIO32
#define MMIO32(a) (*(volatile uint32_t *)(uintptr_t)(a))
#endif

#ifndef CPU_CLOCK_HZ
#define CPU_CLOCK_HZ   162000000u   /* CPU PLL 27 MHz x 35 / 6 */
#endif

#define UART_BASE      0x10000000u
#define UART_DATA      MMIO32(UART_BASE + 0x0u)
#define UART_STATUS    MMIO32(UART_BASE + 0x4u)   /* bit0 busy */

#define GPIO_BASE      0x10001000u
#define GPIO_OUT       MMIO32(GPIO_BASE + 0x0u)   /* bit0 LED0, bit1 LED1 */

#define TIMER_BASE     0x10002000u
#define MTIME_LO       MMIO32(TIMER_BASE + 0x0u)  /* +1 per CPU clock */
#define MTIME_HI       MMIO32(TIMER_BASE + 0x4u)

#define GPU_BASE       0x10004000u

void uart_putc(char c);
void uart_puts(const char *s);
void uart_putu(uint32_t v);

#endif
