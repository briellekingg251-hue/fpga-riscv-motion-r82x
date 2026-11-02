#ifndef P1_UART_H
#define P1_UART_H

#include <stdint.h>

uint32_t p1_uart_busy(void);
void p1_uart_putc(char value);
void p1_uart_puts(const char *text);
void p1_uart_flush(void);

#endif
