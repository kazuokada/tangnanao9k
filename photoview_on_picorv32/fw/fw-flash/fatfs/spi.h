#include <stdint.h>
typedef struct {
    volatile uint32_t control0;
    volatile uint32_t control1;
    volatile uint32_t txdata;
    volatile uint32_t rxdata;
    volatile uint32_t status;
    volatile uint32_t CSout;
    volatile uint32_t dummy0;	// 0x18
    volatile uint32_t dummy1;	// 0x1c
    volatile uint32_t debug;	// 0x20
} PICOSPI;

#define SPI_SD  ((PICOSPI*)0x84000000)

