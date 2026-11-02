#include "p1_mmio.h"
#include "p1_uart.h"

uint32_t p1_uart_busy(void)
{
    return P1_UART_STATUS & 1u;
}

void p1_uart_putc(char value)
{
    while (p1_uart_busy() != 0u) {
    }
    P1_UART_DATA = (uint32_t)(uint8_t)value;
}

void p1_uart_puts(const char *text)
{
    while (*text != '\0') {
        p1_uart_putc(*text++);
    }
}

void p1_uart_flush(void)
{
    while (p1_uart_busy() != 0u) {
    }
}
