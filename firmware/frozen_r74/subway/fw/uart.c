#include "soc.h"

void uart_putc(char c)
{
    while (UART_STATUS & 1u) {
    }
    UART_DATA = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s)
{
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

void uart_putu(uint32_t v)
{
    char buf[11];
    int n = 0;
    do {
        uint32_t q = v / 10u;
        buf[n++] = (char)('0' + (v - q * 10u));
        v = q;
    } while (v && n < 10);
    while (n) uart_putc(buf[--n]);
}
