#ifndef FN_STORAGE_H
#define FN_STORAGE_H
#include <stdint.h>
#include "control_boot.h"
#define GAME_RAM_LIMIT 0x17c00u
#define BOOT_INFO_ADDR 0x80017c00u
#define BOOT_INFO_MAGIC 0x53444249u
#define GAME_ABI 1u
/* Loader ABI 3: DDR3-resident programs (cached window 0x80020000..0x83ffffff). */
#define DDR_GAME_MIN 0x80020000u
#define DDR_GAME_MAX 0x83000000u
#define DDR_STATUS MMIO32(0x10004f00u) /* bit0: DDR3 calibrated */
typedef struct { uint32_t cluster, size; uint8_t attr; } sd_file_t;
typedef struct {
    uint32_t magic, abi, game_id, save_lba[2], volume_start, volume_end;
} boot_info_t;
typedef char boot_info_size_check[(sizeof(boot_info_t)==28)?1:-1];
#define LOADER_ENTRY_ADDR 0x80018000u
int sd_init(void);
int sd_read_block(uint32_t lba, uint8_t *data);
int sd_write_block(uint32_t lba, const uint8_t *data);
int sd_capacity(uint32_t *blocks);
void cardlink_run(void);
int fat_mount(void);
uint32_t fat_root(void);
int fat_find(uint32_t dir, const char name[11], sd_file_t *out);
int fat_dir_entry(uint32_t dir, unsigned index, char name[12], sd_file_t *out);
int fat_read(const sd_file_t *file, uint32_t offset, uint8_t *dst, uint32_t len);
int fat_sector(const sd_file_t *file, uint32_t index, uint32_t *lba);
uint32_t fat_volume_start(void);
uint32_t fat_volume_end(void);
uint32_t storage_crc(uint32_t crc, const uint8_t *data, unsigned size);
uint32_t game_record_load(void);
int game_record_save(uint32_t score);
void storage_jump(uint32_t address) __attribute__((noreturn));
#endif
