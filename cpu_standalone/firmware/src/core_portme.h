/* P1 bare-metal CoreMark port.  Only the permitted core_portme file is
 * changed; benchmark sources stay in third_party/coremark at the fixed
 * upstream commit recorded in third_party/coremark.commit. */
#ifndef P1_CORE_PORTME_H
#define P1_CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>

#include "soc_config.h"

/* RV32I has no floating-point extension.  Keeping this macro at zero also
 * makes core_main use integer seconds and avoids pulling in float helpers. */
#ifndef HAS_FLOAT
#define HAS_FLOAT 1   /* soft-float, used only for the report lines */
#endif
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 0
#define HAS_PRINTF 0

#define COMPILER_VERSION "riscv-none-elf-gcc " __VERSION__ " (RV32I_Zmmul_Zbc/ILP32 target)"
#ifndef COMPILER_FLAGS   /* the build script passes the exact flags */
#define COMPILER_FLAGS "-march=rv32i_zmmul_zbc -mabi=ilp32 -mno-relax -msmall-data-limit=0 -O3 -ffreestanding -fno-builtin -fno-stack-protector -ffunction-sections -fdata-sections -Wall -Wextra -mtune=sifive-7-series -funroll-loops"
#endif
#define MEM_LOCATION "RAM"

typedef int16_t ee_s16;
typedef uint16_t ee_u16;
typedef int32_t ee_s32;
typedef double ee_f32;
typedef uint8_t ee_u8;
typedef uint32_t ee_u32;
typedef uintptr_t ee_ptr_int;
typedef size_t ee_size_t;

#define align_mem(x) (void *)(4u + (((ee_ptr_int)(x) - 1u) & ~3u))

/* The peripheral timer is 64-bit even though the core is RV32I. */
#define CORETIMETYPE uint64_t
typedef uint64_t CORE_TICKS;

#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif
#ifndef MEM_METHOD
#define MEM_METHOD MEM_STATIC
#endif

#define MULTITHREAD 1
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) && !defined(VALIDATION_RUN)
#if (TOTAL_DATA_SIZE == 1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE == 2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

int ee_printf(const char *fmt, ...);

#endif
