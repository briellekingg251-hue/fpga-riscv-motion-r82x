/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "pal_sd.h"
static uint8_t block[512],verify[512];
static uint32_t get32(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(i*8));}
int pal_file_open(pal_file_t *f,uint32_t directory,const char *name){
 char short_name[11];unsigned base=0,ext=0;int dot=0;
 for(unsigned i=0;i<11;i++)short_name[i]=' ';
 for(unsigned i=0;name[i];i++){
  unsigned c=(unsigned char)name[i];if(c>='a' && c<='z')c-=32;
  if(c=='.'){if(dot || !base)return -1;dot=1;continue;}
  if(!((c>='A' && c<='Z') || (c>='0' && c<='9') || c=='_' || c=='-'))return -1;
  if(dot){if(ext==3)return -1;short_name[8+ext++]=(char)c;}
  else{if(base==8)return -1;short_name[base++]=(char)c;}
 }
 if(!base || (dot && !ext) || fat_find(directory,short_name,&f->file) || (f->file.attr&0x10))return -1;
 f->position=0;return 0;
}
int pal_file_seek(pal_file_t *f,int32_t offset,int origin){
 int64_t base=origin==0?0:origin==1?(int64_t)f->position:origin==2?(int64_t)f->file.size:-1;
 int64_t pos=base+offset;if(base<0 || pos<0 || pos>f->file.size)return -1;
 f->position=(uint32_t)pos;return 0;
}
int pal_file_read(pal_file_t *f,uint8_t *p,uint32_t n){
 if(f->position>f->file.size)return -1;
 if(n>f->file.size-f->position)n=f->file.size-f->position;
 if(n>0x7fffffffu || fat_read(&f->file,f->position,p,n))return -1;
 f->position+=n;return (int)n;
}
static int valid_header(const sd_file_t *f,uint32_t id,uint32_t slot,uint32_t *seq,uint32_t *len,uint32_t *crc){
 if(f->size<1024 || (f->attr&0x11) || fat_read(f,0,block,512))return -1;
 if(get32(block)!=0x534c4150u || get32(block+4)!=1 || get32(block+8)!=id || get32(block+12)!=slot ||
    get32(block+508)!=~storage_crc(0xffffffffu,block,508))return -1;
 *seq=get32(block+16);*len=get32(block+20);*crc=get32(block+24);
 return !*len || *len>f->size-512u?-1:0;
}
static int payload_check(const sd_file_t *f,uint32_t n,uint32_t expected){
 uint32_t crc=0xffffffffu;
 for(uint32_t off=0;off<n;){unsigned take=n-off>512?512:(unsigned)(n-off);
  if(fat_read(f,off+512,block,take))return -1;
  crc=storage_crc(crc,block,take);off+=take;
 }
 return ~crc==expected?0:-1;
}
static int select_save(const sd_file_t pair[2],uint32_t id,uint32_t slot,uint32_t *seq,uint32_t *n){
 int active=-1;*seq=0;*n=0;
 for(unsigned i=0;i<2;i++){uint32_t s,l,c;
  if(!valid_header(pair+i,id,slot,&s,&l,&c) && !payload_check(pair+i,l,c) &&
     (active<0 || (int32_t)(s-*seq)>0)){active=(int)i;*seq=s;*n=l;}
 }return active;
}
int pal_save_load(const sd_file_t pair[2],uint32_t id,uint32_t slot,uint8_t *data,uint32_t capacity,uint32_t *length){
 uint32_t seq,n;int active=select_save(pair,id,slot,&seq,&n);
 if(active<0 || n>capacity)return -1;
 if(fat_read(pair+active,512,data,n))return -1;
 *length=n;return 0;
}
static int write_verified(const sd_file_t *f,uint32_t sector){
 uint32_t lba;if(fat_sector(f,sector,&lba) || sd_write_block(lba,block) || sd_read_block(lba,verify))return -1;
 for(unsigned i=0;i<512;i++)if(block[i]!=verify[i])return -1;
 return 0;
}
int pal_save_commit(const sd_file_t pair[2],uint32_t id,uint32_t slot,const uint8_t *data,uint32_t n){
 uint32_t seq,old_len;int active=select_save(pair,id,slot,&seq,&old_len),target=active==0?1:0;
 uint32_t a,b;
 // Header and payload are different files; reject aliases before any write.
 if(!n || pair[0].cluster==pair[1].cluster || pair[target].size<1024 || (pair[target].attr&0x11) ||
    n>pair[target].size-512u || fat_sector(pair,0,&a) || fat_sector(pair+1,0,&b) || a==b)return -1;
 // Invalidate target before replacing its old payload. Previous active file stays valid.
 for(unsigned i=0;i<512;i++)block[i]=0;
 if(write_verified(pair+target,0))return -1;
 uint32_t crc=0xffffffffu;
 for(uint32_t off=0;off<n;off+=512){unsigned take=n-off>512?512:(unsigned)(n-off);
  for(unsigned i=0;i<512;i++)block[i]=i<take?data[off+i]:0;
  crc=storage_crc(crc,block,take);if(write_verified(pair+target,1+off/512))return -1;
 }
 for(unsigned i=0;i<512;i++)block[i]=0;
 put32(block,0x534c4150u);put32(block+4,1);put32(block+8,id);put32(block+12,slot);
 put32(block+16,seq+1u);put32(block+20,n);put32(block+24,~crc);
 put32(block+508,~storage_crc(0xffffffffu,block,508));
 return write_verified(pair+target,0);
}
