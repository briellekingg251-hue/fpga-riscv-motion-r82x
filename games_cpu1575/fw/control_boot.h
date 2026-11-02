/* Separate 64-byte mode extension. boot_info ABI1/2/3 remains unchanged. */
#ifndef FN_CONTROL_BOOT_H
#define FN_CONTROL_BOOT_H
#include "control.h"
#define CONTROL_BOOT_ADDR 0x80017c40u
#define CONTROL_BOOT_END 0x80017c80u
#define CONTROL_BOOT_MAGIC 0x434d4f44u
#define CONTROL_BOOT_VERSION 1u
#define CONTROL_BOOT_SIZE 64u
typedef struct {
    uint32_t magic,version,size,mode,capabilities,session_epoch,game_id;
    uint32_t reserved[8];
    uint32_t checksum;
} control_boot_t;
typedef char control_boot_size_check[(sizeof(control_boot_t)==64)?1:-1];
/* XOR tag detects malformed extensions, not cryptographic authentication.
 * Invalidate magic before writing; commit magic last. Single CPU; mode never
 * changes during gameplay. Reader snapshots fields and rechecks magic. */
#define CONTROL_BOOT_CHECK_TAG 0x6d6f6465u
static inline uint32_t control_boot_checksum(const control_boot_t *b) {
    return CONTROL_BOOT_CHECK_TAG ^ b->magic ^ b->version ^ b->size ^ b->mode ^
           b->capabilities ^ b->session_epoch ^ b->game_id;
}
static inline int control_boot_valid(const control_boot_t *b,uint32_t id) {
    if(b->magic!=CONTROL_BOOT_MAGIC || b->version!=CONTROL_BOOT_VERSION ||
       b->size!=CONTROL_BOOT_SIZE || !b->session_epoch || b->game_id!=id ||
       !control_game_allowed(b->mode,id) || b->capabilities!=control_game_caps(id) ||
       b->checksum!=control_boot_checksum(b))return 0;
    for(unsigned i=0;i<8;i++)if(b->reserved[i])return 0;
    return 1;
}
static inline int control_boot_read(const volatile control_boot_t *p,uint32_t id,control_boot_t *out) {
    control_boot_t b;
    b.magic=p->magic;b.version=p->version;b.size=p->size;b.mode=p->mode;
    b.capabilities=p->capabilities;b.session_epoch=p->session_epoch;b.game_id=p->game_id;
    for(unsigned i=0;i<8;i++)b.reserved[i]=p->reserved[i];
    b.checksum=p->checksum;
    *out=b;
    return p->magic==b.magic && control_boot_valid(&b,id);
}
static inline control_mode_t control_boot_mode(const volatile control_boot_t *p,uint32_t id) {
    control_boot_t b;
    return control_boot_read(p,id,&b)?(control_mode_t)b.mode:CONTROL_TOUCH;
}
#endif
