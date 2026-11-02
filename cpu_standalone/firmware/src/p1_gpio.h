#ifndef P1_GPIO_H
#define P1_GPIO_H

#include <stdint.h>

void p1_gpio_write(uint32_t value);
uint32_t p1_gpio_read(void);
void p1_gpio_write_byte(unsigned lane, uint8_t value);

#endif
