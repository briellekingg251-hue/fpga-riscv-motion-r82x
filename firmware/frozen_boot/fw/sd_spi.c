#include "soc.h"
#include "storage.h"
#define SDREG(o) MMIO32(0x10004200u+(o))
static int high_capacity, io_error, initialized;
static uint16_t crc16(uint16_t crc,uint8_t value) {
    crc^=(uint16_t)value<<8;
    for(unsigned k=0;k<8;k++)crc=(uint16_t)((crc<<1)^((crc&0x8000u)?0x1021u:0));
    return crc;
}
static uint8_t transfer(uint8_t b) {
    uint32_t t=MTIME_LO;
    SDREG(0x10)=b;
    while(SDREG(4)&1u)if((uint32_t)(MTIME_LO-t)>CPU_CLOCK_HZ/100u){io_error=1;return 0xff;}
    return (uint8_t)SDREG(0x10);
}
static void release(void) { SDREG(8)=1; transfer(0xff); }
static int ready(uint32_t timeout) {
    uint32_t t=MTIME_LO;
    do { if(transfer(0xff)==0xff)return io_error?-1:0; } while((uint32_t)(MTIME_LO-t)<timeout && !io_error);
    return -1;
}
static int command(unsigned cmd,uint32_t arg,uint8_t crc) {
    release(); SDREG(8)=0;
    if(ready(CPU_CLOCK_HZ/2u))return -1;
    transfer((uint8_t)(0x40u|cmd));
    for(int i=24;i>=0;i-=8)transfer((uint8_t)(arg>>i));
    transfer(crc);
    for(unsigned i=0;i<10;i++){uint8_t r=transfer(0xff);if(!(r&0x80))return io_error?-1:r;}
    return -1;
}
int sd_init(void) {
    uint32_t t,ocr=0; int v2=0,r;
    io_error=0; high_capacity=0; initialized=0;
    if(SDREG(0)!=0x53445331u)return -1;
    SDREG(0x0c)=203; SDREG(8)=1;
    t=MTIME_LO;while((uint32_t)(MTIME_LO-t)<CPU_CLOCK_HZ/100u);
    for(unsigned i=0;i<10;i++)transfer(0xff);
    if(command(0,0,0x95)!=1)goto fail;
    r=command(8,0x1aa,0x87);
    if(r==1){for(unsigned i=0;i<4;i++)ocr=(ocr<<8)|transfer(0xff);if(ocr!=0x1aa)goto fail;v2=1;}
    else if(r!=5)goto fail;
    t=MTIME_LO;
    do {
        r=command(55,0,1); if(r<0 || r>1)goto fail;
        r=command(41,v2?0x40000000u:0,1); if(r==0)break;
        if(r!=1 || (uint32_t)(MTIME_LO-t)>CPU_CLOCK_HZ*2u)goto fail;
    }while(!io_error);
    if(io_error || command(58,0,1)!=0)goto fail;
    ocr=0;for(unsigned i=0;i<4;i++)ocr=(ocr<<8)|transfer(0xff);
    if(!(ocr&0x80000000u) || !(ocr&0x00300000u))goto fail;
    high_capacity=v2 && (ocr&0x40000000u);
    if(!high_capacity && command(16,512,1)!=0)goto fail;
    release(); SDREG(0x0c)=27; /* 3 MHz, conservative for jumper wiring. */
    initialized=!io_error;
    return initialized?0:-1;
fail:release();return -1;
}
int sd_capacity(uint32_t *blocks) {
    uint8_t csd[16],token;uint16_t crc=0,received;uint32_t t;
    if(!initialized || command(9,0,1)!=0)goto fail;
    t=MTIME_LO;
    do{token=transfer(0xff);if(token!=0xff)break;}while((uint32_t)(MTIME_LO-t)<CPU_CLOCK_HZ/2u && !io_error);
    if(token!=0xfe)goto fail;
    for(unsigned i=0;i<16;i++){csd[i]=transfer(0xff);crc=crc16(crc,csd[i]);}
    received=(uint16_t)transfer(0xff)<<8;received|=transfer(0xff);release();
    if(io_error || crc!=received)return -1;
    if((csd[0]>>6)==1) {
        uint32_t c=((uint32_t)(csd[7]&63)<<16)|(uint32_t)csd[8]<<8|csd[9];
        if(c==0x3fffffu)return -1; /* 2 TiB needs a 64-bit sector count. */
        *blocks=(c+1u)*1024u;return 0;
    }
    if((csd[0]>>6)==0) {
        unsigned shift=(csd[5]&15u)+(((csd[9]&3u)<<1)|(csd[10]>>7))+2u;
        uint32_t c=((uint32_t)(csd[6]&3u)<<10)|((uint32_t)csd[7]<<2)|(csd[8]>>6);
        if(shift<9 || shift>28 || (c+1u)>(0xffffffffu>>(shift-9)))return -1;
        *blocks=(c+1u)<<(shift-9);return 0;
    }
    return -1;
fail:release();return -1;
}
int sd_read_block(uint32_t lba,uint8_t *p) {
    uint32_t t;uint8_t token;uint16_t crc=0,received;
    if(!initialized || io_error || (!high_capacity && lba>0x7fffffu))return -1;
    if(command(17,high_capacity?lba:lba*512u,1)!=0)goto fail;
    t=MTIME_LO;
    do { token=transfer(0xff);if(token!=0xff)break; }while((uint32_t)(MTIME_LO-t)<CPU_CLOCK_HZ/2u && !io_error);
    if(token!=0xfe)goto fail;
    for(unsigned i=0;i<512;i++){p[i]=transfer(0xff);crc=crc16(crc,p[i]);}
    received=(uint16_t)transfer(0xff)<<8;received|=transfer(0xff);
    release();return io_error || received!=crc?-1:0;
fail:release();return -1;
}
int sd_write_block(uint32_t lba,const uint8_t *p) {
    uint16_t crc=0;uint8_t response=0xff;
    if(!initialized || io_error || (!high_capacity && lba>0x7fffffu))return -1;
    if(command(24,high_capacity?lba:lba*512u,1)!=0)goto fail;
    transfer(0xff);transfer(0xfe);
    for(unsigned i=0;i<512;i++){transfer(p[i]);crc=crc16(crc,p[i]);}
    transfer((uint8_t)(crc>>8));transfer((uint8_t)crc);
    for(unsigned i=0;i<8 && response==0xff;i++)response=transfer(0xff);
    if((response&31)!=5 || ready(CPU_CLOCK_HZ))goto fail;
    release();return io_error?-1:0;
fail:release();return -1;
}
