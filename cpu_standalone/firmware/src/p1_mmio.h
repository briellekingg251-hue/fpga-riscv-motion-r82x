#ifndef P1_MMIO_H
#define P1_MMIO_H

#include <stdint.h>
#include "soc_config.h"

#define P1_MMIO32(address) (*(volatile uint32_t *)(uintptr_t)(address))
#define P1_MMIO8(address)  (*(volatile uint8_t *)(uintptr_t)(address))

#define P1_UART_DATA      P1_MMIO32(UART_BASE + 0u)
#define P1_UART_STATUS    P1_MMIO32(UART_BASE + 4u)
#define P1_UART_BAUD      P1_MMIO32(UART_BASE + 8u)
#define P1_GPIO_DATA      P1_MMIO32(GPIO_BASE + 0u)
#define P1_TIMER_LOW      P1_MMIO32(TIMER_BASE + 0u)
#define P1_TIMER_HIGH     P1_MMIO32(TIMER_BASE + 4u)
#define P1_EXIT_CODE      P1_MMIO32(EXIT_BASE)

#endif
