/* FAT32 reader. Never allocates clusters or changes FAT/directory metadata. */
#include "storage.h"
static uint8_t sector[512];
static uint8_t fat_buffer[512];
static uint32_t cached_fat_lba=0xffffffffu;
static struct {uint32_t first,cluster,hop;} walk_cache[4];
static unsigned cache_victim;
static uint32_t base, end, fat, data_base, root, clusters, fat_sectors;
static unsigned spc;
static uint16_t u16(const uint8_t *p) { return p[0] | (uint16_t)p[1]<<8; }
static uint32_t u32(const uint8_t *p) { return u16(p) | (uint32_t)u16(p+2)<<16; }
static int valid(uint32_t c) { return c >= 2 && c < clusters+2; }
static int next(uint32_t c, uint32_t *n) {
    uint32_t lba=fat+c/128;
    if (!valid(c))return -1;
    if(cached_fat_lba!=lba){if(sd_read_block(lba,fat_buffer))return -1;cached_fat_lba=lba;}
    *n = u32(fat_buffer+(c%128)*4) & 0x0fffffffu;
    return 0;
}
int fat_mount(void) {
    uint32_t total, reserved, nf, ext, fs;
    base=end=spc=0;
    cached_fat_lba=0xffffffffu;cache_victim=0;
    for(unsigned i=0;i<4;i++)walk_cache[i].first=0;
    if (sd_read_block(0,sector) || u16(sector+510)!=0xaa55) return -1;
    if (u16(sector+11)!=512) {
        /* MBR: select the first FAT32 partition, not necessarily entry zero. */
        unsigned i; uint32_t partition_size=0;
        for (i=0;i<4;i++) {
            const uint8_t *e=sector+446+i*16;
            if ((e[4]==0x0b || e[4]==0x0c) && u32(e+8) && u32(e+12)) {
                base=u32(e+8); partition_size=u32(e+12); break;
            }
        }
        if (i==4 || base>0xffffffffu-partition_size) return -1;
        end=base+partition_size;
        if (sd_read_block(base,sector)) return -1;
    }
    total=u32(sector+32); reserved=u16(sector+14); nf=sector[16]; fs=u32(sector+36);
    spc=sector[13]; ext=u16(sector+40); root=u32(sector+44);
    if (u16(sector+510)!=0xaa55 || u16(sector+11)!=512 || !spc || spc>128 ||
        (spc&(spc-1)) || !reserved || (nf!=1 && nf!=2) || !fs ||
        u16(sector+17) || u16(sector+22) || u16(sector+19) || u16(sector+42) ||
        fs>0xffffffffu/nf || !total || base>0xffffffffu-total ||
        (end && base+total>end)) return -1;
    if (reserved>=total || nf*fs>=total-reserved) return -1;
    clusters=(total-reserved-nf*fs)/spc;
    if (clusters<65525 || clusters>0x0fffffedu || fs < (clusters+2+127)/128) return -1;
    if ((ext&0x80) && (ext&15)>=nf) return -1;
    fat=base+reserved+((ext&0x80)?(ext&15)*fs:0);
    fat_sectors=fs; data_base=base+reserved+nf*fs; end=base+total;
    return valid(root)?0:-1;
}
uint32_t fat_root(void) { return root; }
uint32_t fat_volume_start(void) { return base; }
uint32_t fat_volume_end(void) { return end; }
int fat_sector(const sd_file_t *file, uint32_t index, uint32_t *lba) {
    uint32_t c=file->cluster, hops;
    if (!spc || file->size>0xfffffe00u || !valid(c)) return -1;
    hops=index/spc;
    if (index>=((file->size+511u)/512u) || hops>=clusters || c/128>=fat_sectors) return -1;
    unsigned slot=4;uint32_t target=hops;
    for(unsigned i=0;i<4;i++)if(walk_cache[i].first==c){slot=i;break;}
    if(slot<4 && walk_cache[slot].hop<=hops && valid(walk_cache[slot].cluster)){
        c=walk_cache[slot].cluster;hops-=walk_cache[slot].hop;
    }
    while (hops--) { if (next(c,&c) || !valid(c)) return -1; }
    if(slot==4)slot=cache_victim++%4;
    walk_cache[slot].first=file->cluster;walk_cache[slot].cluster=c;walk_cache[slot].hop=target;
    *lba=data_base+(c-2)*spc+index%spc;
    return *lba<end?0:-1;
}
int fat_read(const sd_file_t *file, uint32_t off, uint8_t *dst, uint32_t len) {
    if (off>file->size || len>file->size-off) return -1;
    while (len) {
        uint32_t lba,n=512-(off%512);
        if (n>len) n=len;
        if (fat_sector(file,off/512,&lba) || sd_read_block(lba,sector)) return -1;
        for (uint32_t i=0;i<n;i++) dst[i]=sector[off%512+i];
        dst+=n; off+=n; len-=n;
    }
    return 0;
}
/* Directory index counts physical entries. LFN/deleted/labels are skipped. */
int fat_dir_entry(uint32_t dir, unsigned index, char name[12], sd_file_t *out) {
    uint32_t c=dir, hops, lba; const uint8_t *e;
    if (!spc || !valid(c)) return -1;
    hops=index/(spc*16u);
    if(hops>=clusters)return -1;
    while (hops--) { if(next(c,&c)) return -1; if(c>=0x0ffffff8u) return 1; if(!valid(c))return -1; }
    lba=data_base+(c-2)*spc+(index/16)%spc;
    if (lba>=end || sd_read_block(lba,sector)) return -1;
    e=sector+(index%16)*32;
    if (!e[0]) return 1;
    if (e[0]==0xe5 || e[11]==0x0f || (e[11]&8)) return 2;
    for (unsigned i=0;i<11;i++)name[i]=(char)e[i];
    name[11]=0;
    out->cluster=((uint32_t)u16(e+20)<<16)|u16(e+26);
    out->size=u32(e+28); out->attr=e[11];
    return 0;
}
int fat_find(uint32_t dir, const char name[11], sd_file_t *out) {
    char n[12];
    for(unsigned i=0;i<4096;i++) {
        int r=fat_dir_entry(dir,i,n,out); unsigned k;
        if(r<0 || r==1)return -1;
        if(r==2)continue;
        for(k=0;k<11 && n[k]==name[k];k++){}
        if(k==11)return 0;
    }
    return -1;
}
uint32_t storage_crc(uint32_t crc,const uint8_t *p,unsigned n) {
    while(n--) { crc^=*p++; for(unsigned k=0;k<8;k++)crc=(crc>>1)^((0u-(crc&1u))&0xedb88320u); }
    return crc;
}
