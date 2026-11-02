/* Single-block UDP RPC, active only in the bootloader's install screen. */
#include "soc.h"
#include "storage.h"
#define NETREG(o) MMIO32(0x10004300u+(o))
#define RXWORD(i) MMIO32(0x10004400u+(i)*4u)
#define TXWORD(i) MMIO32(0x10004800u+(i)*4u)
static uint32_t request[135],response[135];
static uint8_t verify_block[512];
/* Ops 3/4 carry one half sector each as nibble-duplicated bytes (n | n<<4).
 * The current RGMII receive timing loses packets whose two nibbles differ, so
 * this encoding keeps installation reliable until the link timing is tuned.
 * Op 3 stages bytes 0..255, op 4 stages 256..511 of the same LBA and then
 * writes, reads back and returns the sector like op 2. */
static uint8_t staged_block[512];
static uint32_t staged_lba=0xffffffffu;
static int decode_half(const uint8_t *src,uint8_t *dst) {
    for(unsigned i=0;i<256;i++){
        uint8_t a=src[2*i],b=src[2*i+1];
        if((a>>4)!=(a&15u) || (b>>4)!=(b&15u))return -1;
        dst[i]=(uint8_t)((a&15u)|((b&15u)<<4));
    }
    return 0;
}
static int link_same(uint32_t epoch) {
    return (NETREG(4)&4u) && NETREG(12)==epoch;
}
static void cardlink_handle(uint32_t capacity) {
        for(unsigned i=0;i<135;i++)response[i]=0;
        response[0]=request[0];response[1]=request[1]|0x80000000u;
        response[2]=request[2];response[3]=request[3];response[4]=request[4];
        uint32_t crc=storage_crc(0xffffffffu,(const uint8_t *)request,24);
        crc=storage_crc(crc,(const uint8_t *)(request+7),512);
        int ok=request[0]==0x31424453u && request[5]==0 && request[6]==~crc;
        int err=1;
        if(ok && request[1]==0) {
            response[7]=capacity;response[8]=0x53445031u;response[9]=GAME_ABI;err=capacity?0:1;
        } else if(ok && capacity && request[4]<capacity) {
            if(request[1]==1)err=sd_read_block(request[4],(uint8_t *)(response+7));
            else if(request[1]==2 || request[1]==4) {
                const uint8_t *data=(const uint8_t *)(request+7);
                if(request[1]==4) {
                    err=staged_lba!=request[4] || decode_half(data,staged_block+256);
                    data=staged_block;
                    staged_lba=0xffffffffu;
                } else err=0;
                if(!err)err=sd_write_block(request[4],data);
                if(!err)err=sd_read_block(request[4],verify_block);
                if(!err)for(unsigned i=0;i<512;i++)if(verify_block[i]!=data[i]){err=1;break;}
                if(!err)for(unsigned i=0;i<512;i++)((uint8_t *)(response+7))[i]=verify_block[i];
            } else if(request[1]==3) {
                err=decode_half((const uint8_t *)(request+7),staged_block);
                staged_lba=err?0xffffffffu:request[4];
            }
        }
        response[5]=err?1u:0u;
        crc=storage_crc(0xffffffffu,(const uint8_t *)response,24);
        crc=storage_crc(crc,(const uint8_t *)(response+7),512);response[6]=~crc;
}
void uartlink_start(void);
void uartlink_poll(uint32_t capacity);
void cardlink_run(void) {
    uint32_t capacity=0;
    if(sd_capacity(&capacity))uart_puts("SD CAPACITY ERROR\n");
    uart_puts("PC INSTALL MODE UDP 8081 + UART\n");
    uartlink_start();
    for(;;) {
        uartlink_poll(capacity);
        uint32_t epoch=NETREG(12);
        if((NETREG(4)&5u)!=5u)continue;
        for(unsigned i=0;i<135;i++)request[i]=RXWORD(i);
        if(!link_same(epoch))continue;
        cardlink_handle(capacity);
        if(!link_same(epoch))continue;
        for(unsigned i=0;i<135;i++)TXWORD(i)=response[i];
        if(!link_same(epoch))continue;
        NETREG(8)=1;
        while(link_same(epoch) && (NETREG(4)&2u)){}
    }
}
