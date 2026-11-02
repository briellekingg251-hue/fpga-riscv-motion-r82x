#include "soc.h"
#include "storage.h"
#ifdef STORAGE_HOST_TEST
extern boot_info_t test_boot_info;
#define INFO (&test_boot_info)
#else
#define INFO ((const volatile boot_info_t *)BOOT_INFO_ADDR)
#endif
static uint8_t block[512], verify[512];
static uint32_t sequence, best_score;
static int active=-1;
static uint32_t get32(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static int usable(void) {
    return INFO->magic==BOOT_INFO_MAGIC && INFO->abi==GAME_ABI &&
        INFO->save_lba[0]!=INFO->save_lba[1] && INFO->volume_start<INFO->volume_end &&
        INFO->save_lba[0]>INFO->volume_start && INFO->save_lba[1]>INFO->volume_start &&
        INFO->save_lba[0]<INFO->volume_end && INFO->save_lba[1]<INFO->volume_end;
}
static int record_valid(const uint8_t *p){
    return get32(p)==0x53415631u && get32(p+4)==GAME_ABI &&
        get32(p+8)==INFO->game_id &&
        get32(p+508)==~storage_crc(0xffffffffu,p,508);
}
uint32_t game_record_load(void) {
    active=-1; sequence=best_score=0;
    if(!usable() || sd_init())return 0;
    for(int i=0;i<2;i++)if(!sd_read_block(INFO->save_lba[i],block) && record_valid(block)) {
        uint32_t seq=get32(block+12);
        if(active<0 || (int32_t)(seq-sequence)>0){active=i;sequence=seq;best_score=get32(block+16);}
    }
    return best_score;
}
int game_record_save(uint32_t score) {
    int target=active==0?1:0;
    if(!usable())return -1;
    if(score<=best_score && active>=0)return 0;
    for(unsigned i=0;i<512;i++)block[i]=0;
    put32(block,0x53415631u);put32(block+4,GAME_ABI);put32(block+8,INFO->game_id);
    put32(block+12,sequence+1);put32(block+16,score);
    put32(block+508,~storage_crc(0xffffffffu,block,508));
    if(sd_write_block(INFO->save_lba[target],block) || sd_read_block(INFO->save_lba[target],verify))return -1;
    for(unsigned i=0;i<512;i++)if(block[i]!=verify[i])return -1;
    active=target;sequence++;best_score=score;return 0;
}
