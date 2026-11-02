#include "soc.h"
#include "storage.h"
#include "control_boot.h"
#ifndef VARIANT_GAME_ID
#error VARIANT_GAME_ID required
#endif
static uint8_t block[512];
#ifndef VARIANT_BOOT_INFO
#define VARIANT_BOOT_INFO ((volatile boot_info_t *)(uintptr_t)BOOT_INFO_ADDR)
#endif
#ifndef VARIANT_CONTROL_BOOT
#define VARIANT_CONTROL_BOOT ((const volatile control_boot_t *)(uintptr_t)CONTROL_BOOT_ADDR)
#endif
#ifndef VARIANT_GAME_RAM
#define VARIANT_GAME_RAM ((volatile uint8_t *)(uintptr_t)0x80000000u)
#endif
void uartlink_start(void);
void uartlink_poll(uint32_t capacity);
static uint32_t word(const uint8_t *p) {
    return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;
}
static void maintenance(void) {
    uint32_t capacity=0;
    if(sd_capacity(&capacity))capacity=0;
    uart_puts("UART_SD_MAINT_V1 READY / READ BACKUP SUPPORTED\n");
    uartlink_start();
    for(;;)uartlink_poll(capacity);
}
static void fail(const char *s) {
    uart_puts(s);uart_puts("\n");
    storage_jump(LOADER_ENTRY_ADDR);
}
int main(void) {
    control_boot_t c;
    volatile boot_info_t *info=VARIANT_BOOT_INFO;
    if(info->magic!=BOOT_INFO_MAGIC || info->game_id!=VARIANT_GAME_ID ||
       !control_boot_read(VARIANT_CONTROL_BOOT,VARIANT_GAME_ID,&c))fail("VARIANT HANDOFF INVALID");
    if(sd_init() || fat_mount())fail("VARIANT SD MOUNT FAILED");
    sd_file_t games,dir,m,p;
    if(fat_find(fat_root(),"GAMES      ",&games) || !(games.attr&0x10) ||
       fat_find(games.cluster,VARIANT_GAME_ID==CONTROL_GAME_FRUIT?
                "FRUIT      ":"SUBWAY     ",&dir) || !(dir.attr&0x10))fail("VARIANT DIRECTORY MISSING");
    sd_file_t base;
    if(fat_find(dir.cluster,"MANIFESTBIN",&base) || base.size!=32 ||
       fat_read(&base,0,block,32) || word(block)!=0x53444731u ||
       word(block+28)!=~storage_crc(0xffffffffu,block,28))fail("VARIANT BASE MANIFEST INVALID");
    uint32_t sprite_crc=word(block+16),palette_crc=word(block+20);
    const char *manifest=c.mode==CONTROL_POSE?"POSE    MAN":"TOUCH   MAN";
    const char *program=c.mode==CONTROL_POSE?"POSE    BIN":"TOUCH   BIN";
    if(fat_find(dir.cluster,manifest,&m))maintenance();
    if(m.size!=32 || (m.attr&0x10) || fat_read(&m,0,block,32))fail("VARIANT MANIFEST READ FAILED");
    uint32_t size=word(block+8),crc_expected=word(block+12);
    uint32_t abi=VARIANT_GAME_ID==CONTROL_GAME_FRUIT?1u:2u;
    if(word(block)!=0x53444731u || word(block+4)!=abi || word(block+24)!=VARIANT_GAME_ID ||
       word(block+16)!=sprite_crc || word(block+20)!=palette_crc ||
       word(block+28)!=~storage_crc(0xffffffffu,block,28) ||
       !size || size>GAME_RAM_LIMIT-8192u)fail("VARIANT MANIFEST INVALID");
    if(fat_find(dir.cluster,program,&p) || (p.attr&0x10) || p.size!=size)fail("VARIANT PROGRAM MISSING");
    uint32_t crc=0xffffffffu;
    for(uint32_t off=0;off<size;off+=512) {
        unsigned n=size-off>512?512:(unsigned)(size-off);
        if(fat_read(&p,off,block,n))fail("VARIANT PROGRAM READ FAILED");
        crc=storage_crc(crc,block,n);
        volatile uint8_t *ram=VARIANT_GAME_RAM+off;
        for(unsigned i=0;i<n;i++)ram[i]=block[i];
    }
    if(~crc!=crc_expected)fail("VARIANT PROGRAM CRC FAILED");
    /* The dispatcher runs in DDR, so replacing RAM cannot overwrite its code,
     * BSS or stack. The original SAVE LBAs and mode/epoch handoff are retained. */
    crc=0xffffffffu;
    for(uint32_t off=0;off<size;off+=512) {
        unsigned n=size-off>512?512:(unsigned)(size-off);
        const volatile uint8_t *ram=VARIANT_GAME_RAM+off;
        for(unsigned i=0;i<n;i++)block[i]=ram[i];
        crc=storage_crc(crc,block,n);
    }
    if(~crc!=crc_expected)fail("VARIANT RAM CRC FAILED");
    uart_puts(c.mode==CONTROL_POSE?"VARIANT SELECTED POSE\n":"VARIANT SELECTED TOUCH\n");
    storage_jump(0x80000000u);
}
