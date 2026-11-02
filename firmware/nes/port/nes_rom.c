/* SPDX-License-Identifier: GPL-2.0-or-later */
/* iNES image validation.  Pure: no I/O, usable on the host. */
#include <stddef.h>
#include "nes_port.h"

#define HEADER_BYTES  16u
#define TRAINER_BYTES 512u
#define PRG_UNIT      0x4000u
#define CHR_UNIT      0x2000u

static int is_nes2(const uint8_t *h) { return (h[7] & 0x0cu) == 0x08u; }

/* Headers written by old tools carry text such as "DiskDude!" in bytes 7..15;
 * their byte 7 is then garbage and must not contribute mapper bits. */
static int archaic(const uint8_t *h)
{
    return !is_nes2(h) && (h[12] | h[13] | h[14] | h[15]) != 0;
}

int nes_rom_header_mapper(const uint8_t header[16], unsigned *mapper)
{
    if (header[0] != 'N' || header[1] != 'E' || header[2] != 'S' || header[3] != 0x1a)
        return NES_ROM_BAD_MAGIC;
    /* NES 2.0 is accepted only when it adds nothing beyond iNES 1.0:
     * mapper < 256 and no PRG/CHR size MSBs. */
    if (is_nes2(header) && ((header[8] & 0x0fu) || header[9]))
        return NES_ROM_NES2_UNSUPPORTED;
    *mapper = (unsigned)(header[6] >> 4) | (archaic(header) ? 0u : (header[7] & 0xf0u));
    return NES_ROM_OK;
}

int nes_rom_parse(const uint8_t *image, uint32_t size, nes_rom_t *out)
{
    unsigned mapper;
    int status;
    if (size < HEADER_BYTES) return NES_ROM_TRUNCATED;
    if (size > NES_ROM_MAX) return NES_ROM_TOO_BIG;
    status = nes_rom_header_mapper(image, &mapper);
    if (status != NES_ROM_OK) return status;
    if (image[4] == 0) return NES_ROM_NO_PRG;
    uint32_t trainer = (image[6] & 4u) ? TRAINER_BYTES : 0u;
    uint32_t prg = (uint32_t)image[4] * PRG_UNIT, chr = (uint32_t)image[5] * CHR_UNIT;
    /* All terms are bounded (<= 255 * 16 KiB), so the sum cannot overflow. */
    if (HEADER_BYTES + trainer + prg + chr > size) return NES_ROM_TRUNCATED;
    if (!nes_mapper_supported(mapper)) return NES_ROM_MAPPER_UNSUPPORTED;
    for (unsigned i = 0; i < HEADER_BYTES; ++i) out->header[i] = i < 8u ? image[i] : 0u;
    /* InfoNES derives the mapper from bytes 6/7: hand it the sanitised value. */
    out->header[7] = (uint8_t)(mapper & 0xf0u);
    out->trainer = trainer ? image + HEADER_BYTES : NULL;
    out->prg = image + HEADER_BYTES + trainer;
    out->chr = chr ? out->prg + prg : NULL;
    out->prg_bytes = prg;
    out->chr_bytes = chr;
    out->mapper = mapper;
    return NES_ROM_OK;
}

const char *nes_rom_error(int code)
{
    switch (code) {
    case NES_ROM_OK: return "OK";
    case NES_ROM_BAD_MAGIC: return "NOT AN INES FILE";
    case NES_ROM_NO_PRG: return "NO PRG ROM";
    case NES_ROM_TRUNCATED: return "FILE TRUNCATED";
    case NES_ROM_TOO_BIG: return "FILE LARGER THAN 1 MIB";
    case NES_ROM_NES2_UNSUPPORTED: return "NES 2.0 FEATURES UNSUPPORTED";
    case NES_ROM_MAPPER_UNSUPPORTED: return "MAPPER UNSUPPORTED";
    default: return "UNKNOWN ERROR";
    }
}
