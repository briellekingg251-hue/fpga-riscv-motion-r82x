/* UART sector install (fn_uart_link at 0x10004E00), polled in PC INSTALL mode
 * next to the UDP RPC.  PC -> board frames (524 bytes):
 *   'P' 'L' op seq lba[4] payload[512] crc32[4]   (crc over op..payload)
 * board -> PC replies (25 bytes):
 *   'L' 'P' op|0x80 seq lba[4] status info[12] crc32[4]  (crc over op..info)
 * op 0 INFO  info = capacity, 0x53445031, ABI
 * op 1 WRITE writes the payload, reads it back and compares;
 *            info[0] = CRC32 of the read-back sector
 * op 2 BAUD  payload[0..3] = new divider (CPU clocks per bit), applied after
 *            the reply has been sent at the old rate.
 * op 3 CRC   payload[0..3] = count (1..256): info[0] = CRC32 of sectors
 *            lba..lba+count-1, so the PC can skip unchanged sectors.
 * status 0 = ok, 1 = rejected / SD error, 2 = frame CRC error. */
#include "soc.h"
#include "storage.h"
#define UL(o) MMIO32(0x10004e00u+(o))
static uint8_t frame[522];
static uint8_t readback[512];
static unsigned frame_pos;
static int frame_sync;

static uint32_t le32(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put_le32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static void send_byte(uint8_t b){while(UL(4)&2u){}UL(0x0c)=b;}

/* Menu mode: receive only; the transmitter takes the UART pin with the first
 * reply, so normal loader messages keep working until the PC talks to us. */
void uartlink_listen(void) {
    if(UL(0x14)&1u)return;  /* a PC session is active: keep its baud rate */
    UL(0x14)=2u;
    UL(0x10)=CPU_CLOCK_HZ/115200u;
    frame_pos=0;frame_sync=0;
}
/* Give the UART pin back to the CPU before starting a game. */
void uartlink_release(void) {
    while(UL(4)&2u){}
    UL(0x14)=0u;
}
void uartlink_start(void) {
    UL(0x14)=2u;            /* clear overflow */
    UL(0x10)=CPU_CLOCK_HZ/115200u;
    UL(0x14)=1u;            /* this transmitter now drives the board UART pin */
    frame_pos=0;frame_sync=0;
}

static void reply(uint8_t op,uint8_t seq,uint32_t lba,uint8_t status,const uint32_t info[3]) {
    uint8_t r[25];
    UL(0x14)=1u;            /* replies always leave through this transmitter */
    r[0]='L';r[1]='P';r[2]=(uint8_t)(op|0x80u);r[3]=seq;put_le32(r+4,lba);r[8]=status;
    for(unsigned i=0;i<3;i++)put_le32(r+9+4*i,info[i]);
    put_le32(r+21,~storage_crc(0xffffffffu,r+2,19));
    for(unsigned i=0;i<25;i++)send_byte(r[i]);
}

static void handle(uint32_t capacity) {
    uint8_t op=frame[0],seq=frame[1];
    uint32_t lba=le32(frame+2),info[3]={0,0,0};
    uint8_t status=1;
    if(le32(frame+518)!=~storage_crc(0xffffffffu,frame,518)){reply(op,seq,lba,2,info);return;}
    if(op==0){info[0]=capacity;info[1]=0x53445031u;info[2]=GAME_ABI;status=capacity?0:1;}
    else if(op==1 && capacity && lba<capacity) {
        const uint8_t *data=frame+6;
        status=0;
        if(sd_write_block(lba,data) || sd_read_block(lba,readback))status=1;
        for(unsigned i=0;!status && i<512;i++)if(readback[i]!=data[i])status=1;
        info[0]=~storage_crc(0xffffffffu,readback,512);
    } else if(op==3 && capacity) {
        uint32_t count=le32(frame+6),crc=0xffffffffu;
        if(count>=1 && count<=256 && lba<capacity && count<=capacity-lba) {
            status=0;
            for(uint32_t i=0;i<count;i++){
                if(sd_read_block(lba+i,readback)){status=1;break;}
                crc=storage_crc(crc,readback,512);
            }
            info[0]=~crc;
        }
    } else if(op==2) {
        uint32_t divider=le32(frame+6);
        if(divider>=16 && divider<=65535){
            reply(op,seq,lba,0,info);
            while(UL(4)&2u){}
            for(volatile unsigned i=0;i<2000;i++){}   /* let the stop bit finish */
            UL(0x10)=divider;
            return;
        }
    }
    reply(op,seq,lba,status,info);
}

/* Consume received bytes; returns after at most one handled frame. */
void uartlink_poll(uint32_t capacity) {
    for(unsigned budget=0;budget<600;budget++) {
        uint32_t v=UL(8);
        if(!(v&0x100u))return;
        uint8_t b=(uint8_t)v;
        if(frame_sync<2) {
            if(frame_sync==0)frame_sync=b=='P';
            else frame_sync=b=='L'?2:(b=='P');
            frame_pos=0;
            continue;
        }
        frame[frame_pos++]=b;
        if(frame_pos==sizeof frame){frame_sync=0;frame_pos=0;handle(capacity);return;}
    }
}
/* A PC session (first reply sent) owns the UART pin and its baud rate. */
int uartlink_active(void) { return (UL(0x14)&1u)!=0; }
