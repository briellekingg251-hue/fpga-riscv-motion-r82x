/* Manual Fruit Ninja for the s80 RISC-V CPU + FPGA display engine.
 * START / PAUSE / RESUME / RESTART / RETRY are explicit touch buttons.
 * The optional automatic demonstration requires -DFN_DEMO_MODE=1.
 * Game coordinates are framebuffer pixels (512 x 300).
 */
#include <stdint.h>
#include "soc.h"
#include "gpu.h"
#include "assets.h"
#include "touch.h"
#include "game_control.h"
#include "pose_ui.h"
#include "pose_blade_visual.h"
static game_control_t game_control;
/* POSE mode only: live skeleton/cursor UI, wait-for-player and auto pause. */
static pose_ui_t pose_ui;
static int pose_waiting, pose_lost_pause;
#ifndef FN_SD_ENABLED
#define FN_SD_ENABLED 1
#endif
#if FN_SD_ENABLED
static int returning_to_menu;
#endif
#if FN_SD_ENABLED
#include "storage.h"
#endif

#ifndef FN_START_STATE
#define FN_START_STATE ST_TITLE
#endif
#ifndef FN_FAST_FORWARD
#define FN_FAST_FORWARD 0
#endif
#ifndef FN_DEMO_MODE
#define FN_DEMO_MODE 0
#endif

/* ------------------------------------------------------------ tuning */
#define GRAVITY        30          /* Q8 px / frame^2 */
#define LAUNCH_Y       (330 << 8)
#define KILL_Y         (345 << 8)
#define HALF_SPEED     190         /* Q8 px / frame separation */
#define SWIPE_LEN      120
#define SWIPE_FRAMES   7
#define MAX_OBJ        24
#define MAX_SPLASH     10
#define MAX_POP        6
#define TRAIL_N        10
#define TITLE_FRAMES   240
#define OVER_FRAMES    210
#define MAX_MISSES     3

enum { ST_TITLE, ST_PLAY, ST_OVER, ST_PAUSE };
enum { OBJ_NONE, OBJ_FRUIT, OBJ_HALF, OBJ_BOMB };

typedef struct {
    uint8_t kind, type, flip, sliced_by;
    int x, y, vx, vy;              /* Q8 framebuffer pixels */
    int ang, spin;                 /* Q8 angle units (256 units = 1 turn) */
} obj_t;

typedef struct { int x, y, age; uint8_t img, ang, flip, used; } splash_t;
typedef struct { int x, y, age; uint8_t used; char text[20]; } popup_t;
typedef struct { int x, y; } pt_t;
typedef struct { int x, y, w, h; const char *label; } button_t;

/* Drawing and hit testing share these exact rectangles (right/bottom excluded).
 * Multiply by two to obtain raw panel pixels for hardware/system tests.
 */
static const button_t BTN_START   = {176, 242, 160, 40, "START"};
static const button_t BTN_PAUSE   = {208,   4,  96, 40, "PAUSE"};
static const button_t BTN_RESUME  = {164, 132, 184, 44, "RESUME"};
static const button_t BTN_RESTART = {164, 194, 184, 44, "RESTART"};
static const button_t BTN_RETRY   = {176, 218, 160, 46, "RETRY"};
#if FN_SD_ENABLED
static const button_t BTN_MENU    = {400, 4, 104, 36, "MENU"};
#endif

typedef struct {
    uint8_t whole, half, splash, radius;
} fruit_info_t;

static const fruit_info_t FRUITS[5] = {
    {SPR_WATERMELON, SPR_WATERMELON_HALF, SPR_SPLASH_RED,    28},
    {SPR_ORANGE,     SPR_ORANGE_HALF,     SPR_SPLASH_ORANGE, 24},
    {SPR_APPLE,      SPR_APPLE_HALF,      SPR_SPLASH_YELLOW, 24},
    {SPR_LEMON,      SPR_LEMON_HALF,      SPR_SPLASH_YELLOW, 24},
    {SPR_KIWI,       SPR_KIWI_HALF,       SPR_SPLASH_GREEN,  23},
};

/* ------------------------------------------------------------ state */
static obj_t    objs[MAX_OBJ];
static splash_t splashes[MAX_SPLASH];
static popup_t  popups[MAX_POP];
static pt_t     trail[TRAIL_N];
static int      trail_n;
static pt_t pose_trail[2][TRAIL_N];
static int pose_trail_n[2];
static uint32_t pose_trail_ms[2][TRAIL_N];
static pose_blade_visual_t pose_visual[2];

static int state, state_timer, frame_no;
static int score, best, misses, wave_timer, flash;

static struct {
    int active, t, cooldown, angle, combo;
    int sx, sy, ex, ey, px, py;      /* start / end / previous tip, framebuffer px */
} blade;

static struct {
    touch_sample_t sample;
    int x, y, down, pressed, new_stroke, fresh;
    int manual_frames, stale_frames, seen_sample, log_frames, press_armed;
    int block_until_release;
    uint32_t logged_status, logged_errors;
    unsigned track_id;
} touch = { .press_armed = 1 };

static uint32_t rng_state = 0x2545F491u;
static uint32_t rnd(void)
{
    uint32_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return rng_state = x;
}
static int rnd_range(int lo, int hi) { return lo + (int)(rnd() % (uint32_t)(hi - lo + 1)); }
static int iabs(int v) { return v < 0 ? -v : v; }

/* ------------------------------------------------------------ helpers */
static void touch_poll(void)
{
    touch_sample_t s = touch_read();
    unsigned count = (s.status >> 4) & 15u;
    unsigned id = (s.status >> 8) & 255u;
    int x = touch.x, y = touch.y;
    int was_down = touch.down;
    touch.fresh = !touch.seen_sample || s.sequence != touch.sample.sequence;
    if (touch.fresh) touch.stale_frames = 0;
    else if (touch.stale_frames < FN_TOUCH_STALE_FRAMES) touch.stale_frames++;
    int healthy = (s.status & (TOUCH_READY | TOUCH_FAULT)) == TOUCH_READY;
    int down = healthy && (s.status & TOUCH_DOWN) && count >= 1 && count <= 5 &&
               touch.stale_frames < FN_TOUCH_STALE_FRAMES && touch_map(s.xy, &x, &y);
    /* A lost/stale packet stops the blade but must not turn one held finger
     * into repeated Start/Retry presses when communication returns.
     */
    if (healthy && touch.fresh && !(s.status & TOUCH_DOWN) && count == 0) {
        touch.press_armed = 1;
        touch.block_until_release = 0;
    }
    touch.pressed = down && touch.fresh && !was_down && touch.press_armed &&
                    !touch.block_until_release;
    touch.new_stroke = down && (!was_down || id != touch.track_id);
    if (down) {
        touch.press_armed = 0;
        touch.manual_frames = FN_TOUCH_RELEASE_FRAMES;
    } else if (touch.manual_frames > 0) touch.manual_frames--;
    touch.down = down;
    touch.x = x;
    touch.y = y;
    touch.track_id = id;
    touch.sample = s;
    touch.seen_sample = 1;
#if FN_TOUCH_LOG
    /* At most two lines/sec, including the raw coordinates used for checking
     * panel orientation. Status contains ready/fault/down, count and track ID.
     */
    if (++touch.log_frames >= 30 &&
        (down || s.status != touch.logged_status || s.errors != touch.logged_errors)) {
        uart_puts("touch status "); uart_putu(s.status);
        uart_puts(" x "); uart_putu(s.xy & 0xFFFFu);
        uart_puts(" y "); uart_putu(s.xy >> 16);
        uart_puts(" seq "); uart_putu(s.sequence);
        uart_puts(" err "); uart_putu(s.errors);
        uart_puts("\n");
        touch.log_frames = 0;
        touch.logged_status = s.status;
        touch.logged_errors = s.errors;
    }
#endif
}

static void fmt_uint(char *dst, const char *prefix, int v)
{
    char tmp[12];
    int n = 0;
    while (*prefix) *dst++ = *prefix++;
    if (v < 0) v = 0;
    do {
        tmp[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v && n < 11);
    while (n) *dst++ = tmp[--n];
    *dst = 0;
}

static obj_t *obj_alloc(void)
{
    for (int i = 0; i < MAX_OBJ; ++i)
        if (objs[i].kind == OBJ_NONE) return &objs[i];
    return 0;
}

static void popup(int x, int y, const char *text)
{
    for (int i = 0; i < MAX_POP; ++i) {
        if (!popups[i].used) {
            popup_t *p = &popups[i];
            p->used = 1;
            p->x = x;
            p->y = y;
            p->age = 0;
            int k = 0;
            while (text[k] && k < 19) { p->text[k] = text[k]; ++k; }
            p->text[k] = 0;
            return;
        }
    }
}

static void add_splash(int x, int y, uint8_t img)
{
    int oldest = 0;
    for (int i = 0; i < MAX_SPLASH; ++i) {
        if (!splashes[i].used) { oldest = i; break; }
        if (splashes[i].age > splashes[oldest].age) oldest = i;
    }
    splash_t *s = &splashes[oldest];
    s->used = 1;
    s->x = x;
    s->y = y;
    s->age = 0;
    s->img = img;
    s->ang = (uint8_t)rnd();
    s->flip = (uint8_t)(rnd() & 1);
}

/* ------------------------------------------------------------ spawning */
static void launch(int kind, int type)
{
    obj_t *o = obj_alloc();
    if (!o) return;
    int x = rnd_range(90, 422);
    o->kind = (uint8_t)kind;
    o->type = (uint8_t)type;
    o->flip = (uint8_t)(rnd() & 1);
    o->sliced_by = 0;
    o->x = x << 8;
    o->y = LAUNCH_Y;
    o->vx = ((256 - x) * 256) / 170 + rnd_range(-60, 60);
    o->vy = -rnd_range(1680, 2080);
    o->ang = rnd_range(0, 255) << 8;
    o->spin = rnd_range(120, 560) * ((rnd() & 1) ? 1 : -1);
}

static void spawn_wave(void)
{
    int n = 1 + (int)(rnd() % 4);
    if (score > 20 && (rnd() & 3) == 0) n++;
    for (int i = 0; i < n; ++i) launch(OBJ_FRUIT, (int)(rnd() % 5));
    if (score > 5 && (rnd() % 100) < 22) launch(OBJ_BOMB, 0);
}

/* ------------------------------------------------------------ slicing */
static void slice(obj_t *o)
{
    const fruit_info_t *f = &FRUITS[o->type];
    int th = blade.angle - 64;                 /* half's cut line follows the blade */
    int c = icos(th), s = isin(th);
    for (int side = 0; side < 2; ++side) {
        obj_t *h = obj_alloc();
        if (!h) break;
        int sgn = side ? 1 : -1;
        h->kind = OBJ_HALF;
        h->type = o->type;
        h->flip = (uint8_t)side;
        h->x = o->x;
        h->y = o->y;
        h->vx = o->vx + sgn * ((c * HALF_SPEED) >> 14);
        h->vy = o->vy + sgn * ((s * HALF_SPEED) >> 14) - 60;
        h->ang = (th & 255) << 8;
        h->spin = sgn * rnd_range(100, 260);
    }
    add_splash(o->x >> 8, o->y >> 8, f->splash);
    o->kind = OBJ_NONE;
    score++;
    blade.combo++;
}

static int hit(const obj_t *o, int x, int y)
{
    int r = (o->kind == OBJ_BOMB) ? 22 : FRUITS[o->type].radius;
    int dx = (o->x >> 8) - x, dy = (o->y >> 8) - y;
    return dx * dx + dy * dy <= r * r;
}

/* blade segment (x0,y0)->(x1,y1): slice everything it crosses */
static void blade_cut(int x0, int y0, int x1, int y1)
{
    int dx = x1 - x0, dy = y1 - y0;
    int n = (iabs(dx) > iabs(dy) ? iabs(dx) : iabs(dy)) / 4 + 1;
    for (int k = 0; k <= n; ++k) {
        int x = x0 + dx * k / n, y = y0 + dy * k / n;
        for (int i = 0; i < MAX_OBJ; ++i) {
            obj_t *o = &objs[i];
            if ((o->kind == OBJ_FRUIT || o->kind == OBJ_BOMB) && hit(o, x, y)) {
                if (o->kind == OBJ_BOMB) {
                    o->kind = OBJ_NONE;
                    flash = 12;
                    add_splash(x, y, SPR_SPARKLE);
                    if (state == ST_PLAY) { state = ST_OVER; state_timer = 0; }
                    return;
                } else {
                    slice(o);
                }
            }
        }
    }
}

#if FN_DEMO_MODE
/* would a swipe through (px,py) at `angle` touch a bomb during the swipe? */
static int swipe_hits_bomb(int px, int py, int angle, int t_hit)
{
    int hx = (icos(angle) * (SWIPE_LEN / 2)) >> 14, hy = (isin(angle) * (SWIPE_LEN / 2)) >> 14;
    for (int i = 0; i < MAX_OBJ; ++i) {
        const obj_t *o = &objs[i];
        if (o->kind != OBJ_BOMB) continue;
        for (int k = 0; k <= SWIPE_FRAMES; ++k) {
            int dt = k - t_hit;
            int t = t_hit + dt;
            int bx = (o->x + o->vx * t) >> 8;
            int by = (o->y + o->vy * t + GRAVITY * t * t / 2) >> 8;
            int sx = px - hx + (2 * hx * k) / SWIPE_FRAMES;
            int sy = py - hy + (2 * hy * k) / SWIPE_FRAMES;
            int ddx = bx - sx, ddy = by - sy;
            if (ddx * ddx + ddy * ddy < 36 * 36) return 1;
        }
    }
    return 0;
}

static void blade_plan(void)
{
    const obj_t *best_o = 0;
    int best_score = 1 << 30;
    for (int i = 0; i < MAX_OBJ; ++i) {
        const obj_t *o = &objs[i];
        if (o->kind != OBJ_FRUIT) continue;
        int y = o->y >> 8;
        if (y > 250 || y < 20) continue;
        int sc = iabs(o->vy) + ((o->vy > 0) ? 400 : 0);   /* prefer fruit near the apex */
        if (sc < best_score) { best_score = sc; best_o = o; }
    }
    if (!best_o) return;
    if ((rnd() % 100) < 4) { blade.cooldown = 30; return; }  /* the AI hesitates sometimes */
    int t_hit = SWIPE_FRAMES / 2;
    int px = (best_o->x + best_o->vx * t_hit) >> 8;
    int py = (best_o->y + best_o->vy * t_hit + GRAVITY * t_hit * t_hit / 2) >> 8;
    for (int tries = 0; tries < 6; ++tries) {
        int a = (int)(rnd() & 255);
        if (swipe_hits_bomb(px, py, a, t_hit)) continue;
        int hx = (icos(a) * (SWIPE_LEN / 2)) >> 14, hy = (isin(a) * (SWIPE_LEN / 2)) >> 14;
        blade.active = 1;
        blade.t = 0;
        blade.angle = a;
        blade.combo = 0;
        blade.sx = px - hx;
        blade.sy = py - hy;
        blade.ex = px + hx;
        blade.ey = py + hy;
        blade.px = blade.sx;
        blade.py = blade.sy;
        trail_n = 0;
        trail[trail_n].x = blade.sx;
        trail[trail_n].y = blade.sy;
        trail_n++;
        return;
    }
    blade.cooldown = 6;
}

static void blade_update(void)
{
    if (blade.active) {
        blade.t++;
        int x = blade.sx + (blade.ex - blade.sx) * blade.t / SWIPE_FRAMES;
        int y = blade.sy + (blade.ey - blade.sy) * blade.t / SWIPE_FRAMES;
        blade_cut(blade.px, blade.py, x, y);
        blade.px = x;
        blade.py = y;
        if (trail_n == TRAIL_N) {
            for (int i = 1; i < TRAIL_N; ++i) trail[i - 1] = trail[i];
            trail_n--;
        }
        trail[trail_n].x = x;
        trail[trail_n].y = y;
        trail_n++;
        if (blade.t >= SWIPE_FRAMES) {
            blade.active = 0;
            blade.cooldown = rnd_range(3, 12);
            if (blade.combo >= 3) {
                char txt[20];
                fmt_uint(txt, "Combo x", blade.combo);
                popup(x - 40, y - 20, txt);
                score += blade.combo;
            }
        }
    } else {
        if (trail_n > 0) {                      /* trail shrinks after the swipe */
            int drop = trail_n > 3 ? 3 : trail_n;
            for (int i = drop; i < trail_n; ++i) trail[i - drop] = trail[i];
            trail_n -= drop;
        }
        if (blade.cooldown > 0) blade.cooldown--;
        else if (state != ST_TITLE) blade_plan();
    }
}
#endif

static void trail_decay(void)
{
    int drop = trail_n > 3 ? 3 : trail_n;
    for (int i = drop; i < trail_n; ++i) trail[i - drop] = trail[i];
    trail_n -= drop;
}

static void trail_add(int x, int y)
{
    if (trail_n == TRAIL_N) {
        for (int i = 1; i < TRAIL_N; ++i) trail[i - 1] = trail[i];
        trail_n--;
    }
    trail[trail_n].x = x;
    trail[trail_n].y = y;
    trail_n++;
}

static void touch_finish_combo(void)
{
    if (state == ST_PLAY && blade.combo >= 3) {
        char txt[20];
        fmt_uint(txt, "Combo x", blade.combo);
        popup(blade.px - 40, blade.py - 20, txt);
        score += blade.combo;
    }
    blade.combo = 0;
}

/* Eight-octant approximation in the existing 0..255 angle units.  This only
 * controls the direction in which halves separate; the hit segment is exact.
 */
static int touch_angle(int dx, int dy)
{
    int ax = iabs(dx), ay = iabs(dy);
    if (!ax && !ay) return blade.angle;
    int a = ax >= ay ? ay * 32 / ax : 64 - ax * 32 / ay;
    if (dx < 0) a = 128 - a;
    if (dy < 0) a = -a;
    return a & 255;
}

static void touch_blade_update(void)
{
    if (blade.active) blade.combo = 0;
    blade.active = 0;             /* immediately cancel any AI swipe */
    blade.cooldown = 0;
    if (!touch.down || touch.block_until_release || state != ST_PLAY) {
        touch_finish_combo();
        trail_decay();
        return;
    }
    if (touch.new_stroke) {
        /* Never connect a finger to the AI tip, an old contact, or another ID. */
        touch_finish_combo();
        trail_n = 0;
        blade.px = touch.x;
        blade.py = touch.y;
        blade.angle = 0;
        trail_add(touch.x, touch.y);
        blade_cut(touch.x, touch.y, touch.x, touch.y);
    } else if (touch.fresh && (touch.x != blade.px || touch.y != blade.py)) {
        blade.angle = touch_angle(touch.x - blade.px, touch.y - blade.py);
        if (!trail_n) trail_add(blade.px, blade.py);
        blade_cut(blade.px, blade.py, touch.x, touch.y);
        trail_add(touch.x, touch.y);
        blade.px = touch.x;
        blade.py = touch.y;
    } else {
        trail_decay();
    }
}

/* Backend-smoothed real sample segments are the only POSE hit geometry.
 * Each hand has a separate visual trail. Missing/first points never connect. */
static void pose_blade_update(void)
{
    blade.active=0;blade.cooldown=0;
    const control_frame_t *f=&game_control.frame;
    uint32_t now=game_control.ms;
    for(unsigned h=0;h<2;h++) {
        const control_blade_t *p=&f->hand[h];
        if(state!=ST_PLAY || !f->pose_valid || !p->point_valid) {
            pose_trail_n[h]=0;pose_visual[h].active=0;continue;
        }
        if(game_control.fresh && p->segment_valid) {
            blade.angle=touch_angle(p->x-p->x0,p->y-p->y0);
            blade.px=p->x;blade.py=p->y;
            blade_cut(p->x0,p->y0,p->x,p->y);
            if(state!=ST_PLAY) {pose_trail_n[0]=pose_trail_n[1]=0;
                pose_visual[0].active=pose_visual[1].active=0;return;}
        }
        if(game_control.fresh) {
            if(!p->segment_valid)pose_trail_n[h]=0;
            pose_blade_visual_sample(&pose_visual[h],p->x,p->y,f->capture_ms,now,p->segment_valid!=0);
        }
        pose_blade_visual_advance(&pose_visual[h],now);
        while(pose_trail_n[h] && now-pose_trail_ms[h][0]>160u) {
            for(int i=1;i<pose_trail_n[h];i++) {
                pose_trail[h][i-1]=pose_trail[h][i];pose_trail_ms[h][i-1]=pose_trail_ms[h][i];
            }
            --pose_trail_n[h];
        }
        int x=pose_visual[h].xq/256,y=pose_visual[h].yq/256,n=pose_trail_n[h];
        if(!n || pose_trail[h][n-1].x!=x || pose_trail[h][n-1].y!=y) {
            if(n==TRAIL_N) {
                for(int i=1;i<n;i++) {pose_trail[h][i-1]=pose_trail[h][i];pose_trail_ms[h][i-1]=pose_trail_ms[h][i];}
                --n;
            }
            pose_trail[h][n]=(pt_t){x,y};pose_trail_ms[h][n]=now;pose_trail_n[h]=n+1;
        }
    }
    /* Combo never accumulates across separate pose samples/hands/loss. */
    blade.combo=0;
}

/* ------------------------------------------------------------ update */
static void reset_game(void)
{
    for (int i = 0; i < MAX_OBJ; ++i) objs[i].kind = OBJ_NONE;
    for (int i = 0; i < MAX_SPLASH; ++i) splashes[i].used = 0;
    for (int i = 0; i < MAX_POP; ++i) popups[i].used = 0;
    score = 0;
    misses = 0;
    wave_timer = 40;
    trail_n = 0;
    pose_trail_n[0]=pose_trail_n[1]=0;
    pose_visual[0].active=pose_visual[1].active=0;
    blade.active = 0;
    blade.cooldown = 30;
    blade.combo = 0;
    flash = 0;
    if (touch.down) touch.new_stroke = 1;
}

static int button_hit(const button_t *b)
{
    return touch.x >= b->x && touch.x < b->x + b->w &&
           touch.y >= b->y && touch.y < b->y + b->h;
}

static void consume_ui_touch(const char *action)
{
    touch.block_until_release = 1;
    touch.press_armed = 0;
    touch.pressed = 0;
    touch.new_stroke = 0;
    if(game_control.mode==CONTROL_POSE)game_control_flush(&game_control);
    trail_n = 0;
    pose_trail_n[0]=pose_trail_n[1]=0;
    pose_visual[0].active=pose_visual[1].active=0;
    blade.active = 0;
    blade.combo = 0;
#if FN_TOUCH_LOG
    uart_puts("ui "); uart_puts(action); uart_puts("\n");
#else
    (void)action;
#endif
}

static void start_game(const char *action)
{
    if (score > best) best = score;
    reset_game();
    pose_waiting = game_control.mode == CONTROL_POSE;
    pose_lost_pause = 0;
    state = ST_PLAY;
    state_timer = 0;
    consume_ui_touch(action);
}

/* A player standing away from the screen holds a hand over a button. */
static void pose_ui_press(void)
{
    const button_t *b[3];
    unsigned n = 0;
    if (state == ST_TITLE) b[n++] = &BTN_START;
    else if (state == ST_PAUSE) { b[n++] = &BTN_RESUME; b[n++] = &BTN_RESTART; }
    else if (state == ST_OVER) b[n++] = &BTN_RETRY;
#if FN_SD_ENABLED
    if (state != ST_PLAY) b[n++] = &BTN_MENU;
#endif
    pose_ui_rect_t r[3];
    for (unsigned k = 0; k < n; ++k) r[k] = (pose_ui_rect_t){b[k]->x, b[k]->y, b[k]->w, b[k]->h};
    int i = pose_ui_dwell(&pose_ui, r, n);
    if (i >= 0) {
        touch.x = b[i]->x + b[i]->w / 2;
        touch.y = b[i]->y + b[i]->h / 2;
        touch.pressed = 1;
    }
}

static int handle_ui_touch(void)
{
    if (game_control.mode == CONTROL_POSE && !touch.pressed) pose_ui_press();
    if (!touch.pressed) return 0;
#if FN_SD_ENABLED
    if (state != ST_PLAY && button_hit(&BTN_MENU)) {
        if (score > best) best = score;
        if (game_record_save((uint32_t)best)) uart_puts("SD SAVE FAILED\n");
        while (!(GPU_REG_STATUS & 4u)) {}
        game_control_flush(&game_control);
        returning_to_menu=1;
        return 1;
    }
#endif
    if (state == ST_TITLE && button_hit(&BTN_START)) {
        start_game("START");
    } else if (state == ST_PLAY && button_hit(&BTN_PAUSE)) {
        state = ST_PAUSE;
        consume_ui_touch("PAUSE");
    } else if (state == ST_PAUSE && button_hit(&BTN_RESUME)) {
        state = ST_PLAY;
        pose_waiting = game_control.mode == CONTROL_POSE;
        pose_lost_pause = 0;
        consume_ui_touch("RESUME");
    } else if (state == ST_PAUSE && button_hit(&BTN_RESTART)) {
        start_game("RESTART");
    } else if (state == ST_OVER && button_hit(&BTN_RETRY)) {
        start_game("RETRY");
    } else return 0;
    return 1;
}

static void update(void)
{
    frame_no++;
    /* UI clicks are consumed before any simulation or collision work. Even
     * Resume leaves this frame frozen and requires a real lift before slicing.
     */
    if (handle_ui_touch()) return;
    if (state == ST_PAUSE) return;
    if (state == ST_TITLE) {
#if FN_DEMO_MODE
        if (++state_timer >= TITLE_FRAMES) {
            state = ST_PLAY; state_timer = 0; reset_game();
        }
#endif
        return;
    }
    if (flash > 0) flash--;
    if (state == ST_OVER) {
#if FN_DEMO_MODE
        if (++state_timer >= OVER_FRAMES) {
            if (score > best) best = score;
            state = ST_TITLE; state_timer = 0; reset_game();
        }
#endif
        return;
    }
    if (game_control.mode == CONTROL_POSE) {
        /* No fruit is launched until the camera has the player; losing the
         * player mid-round pauses instead of silently costing lives. */
        if (pose_waiting) {
            if (!pose_ui.body) return;
            pose_waiting = 0;
        }
        if (pose_ui_lost_for(&pose_ui, POSE_UI_LOST_MS)) {
            state = ST_PAUSE;
            pose_lost_pause = 1;
            consume_ui_touch("AUTO PAUSE");
            return;
        }
    }
    state_timer++;
    if (--wave_timer <= 0) {
        spawn_wave();
        wave_timer = rnd_range(70, 120) - (score > 30 ? 20 : 0);
    }

    for (int i = 0; i < MAX_OBJ; ++i) {
        obj_t *o = &objs[i];
        if (o->kind == OBJ_NONE) continue;
        o->x += o->vx;
        o->y += o->vy;
        o->vy += GRAVITY;
        o->ang += o->spin;
        if (o->y > KILL_Y && o->vy > 0) {
            if (o->kind == OBJ_FRUIT && state == ST_PLAY) {
                if (++misses >= MAX_MISSES) { state = ST_OVER; state_timer = 0; }
            }
            o->kind = OBJ_NONE;
        }
    }
    for (int i = 0; i < MAX_SPLASH; ++i)
        if (splashes[i].used && ++splashes[i].age > 110) splashes[i].used = 0;
    for (int i = 0; i < MAX_POP; ++i)
        if (popups[i].used && ++popups[i].age > 60) popups[i].used = 0;

    if(game_control.mode==CONTROL_POSE)pose_blade_update();
    else {
#if FN_DEMO_MODE
    if (touch.manual_frames > 0 || touch.down || touch.block_until_release)
        touch_blade_update();
    else if (state == ST_PLAY) blade_update();
#else
    touch_blade_update();
#endif
    }
}

/* ------------------------------------------------------------ drawing */
static void draw_button(const button_t *b)
{
    gpu_rect(b->x, b->y, b->w, b->h, COL_GOLD);
    gpu_rect(b->x + 2, b->y + 2, b->w - 4, b->h - 4, COL_INK);
    int scale = 2;
    gpu_text_shadow(b->x + (b->w - gpu_text_width(b->label, scale)) / 2,
                    b->y + (b->h - 32) / 2, b->label, COL_CREAM, COL_SHADOW, scale);
}

static void draw_trail_points(const pt_t *points,int point_count)
{
    if (point_count < 2) return;
    for (int pass = 0; pass < 2; ++pass) {
        for (int i = 1; i < point_count; ++i) {
            int x0 = points[i - 1].x, y0 = points[i - 1].y;
            int dx = points[i].x - x0, dy = points[i].y - y0;
            int n = (iabs(dx) > iabs(dy) ? iabs(dx) : iabs(dy)) / 3 + 1;
            for (int k = 0; k < n; ++k) {
                int t = (i - 1) * n + k, total = (point_count - 1) * n;
                int r = 1 + (t * 4) / total;              /* thin tail -> thick head */
                int x = x0 + dx * k / n, y = y0 + dy * k / n;
                if (pass == 0) gpu_circle(x, y, r + 2, COL_BLADE_RAMP + 2 + (t * 4) / total);
                else           gpu_circle(x, y, r > 1 ? r - 1 : 0, COL_BLADE_CORE);
            }
        }
    }
}

static void draw_trail(void)
{
    if(game_control.mode==CONTROL_POSE) {
        for(unsigned h=0;h<2;h++) {
            const control_blade_t *p=&game_control.frame.hand[h];
            if(state==ST_PLAY && game_control.frame.pose_valid && p->point_valid) {
                gpu_circle(pose_visual[h].xq/256,pose_visual[h].yq/256,6,COL_BLADE_RAMP+6);
                gpu_circle(pose_visual[h].xq/256,pose_visual[h].yq/256,3,COL_BLADE_CORE);
                draw_trail_points(pose_trail[h],pose_trail_n[h]);
            }
        }
        return;
    }
    if (touch.down && !touch.block_until_release && state == ST_PLAY) {
        gpu_circle(touch.x, touch.y, 6, COL_BLADE_RAMP + 6);
        gpu_circle(touch.x, touch.y, 3, COL_BLADE_CORE);
    }
    draw_trail_points(trail,trail_n);
}

static void draw_hud(void)
{
    char txt[20];
    gpu_sprite(SPR_WATERMELON, 22, 20, 100, 230, 0);
    fmt_uint(txt, "", score);
    gpu_text_shadow(42, 4, txt, COL_GOLD, COL_SHADOW, 2);
    fmt_uint(txt, "BEST ", best > score ? best : score);
    gpu_text_shadow(44, 38, txt, COL_CREAM, COL_SHADOW, 1);
    for (int i = 0; i < MAX_MISSES; ++i) {
        int sc = (i < misses) ? 150 : 110 + 10 * i;
        gpu_sprite(i < misses ? SPR_X_RED : SPR_X_GRAY, 420 + 30 * i, 22, sc, 0, 0);
    }
    gpu_text_shadow(6, 282, "s80 RISC-V 157.5MHz + FPGA GPU", COL_CREAM, COL_SHADOW, 1);
    if (state == ST_PLAY) draw_button(&BTN_PAUSE);
}

static void draw_objects(void)
{
    for (int i = 0; i < MAX_SPLASH; ++i) {
        const splash_t *s = &splashes[i];
        if (!s->used) continue;
        int sc = s->age < 6 ? 120 + s->age * 36 : (s->age < 80 ? 336 : 336 - (s->age - 80) * 11);
        if (sc > 20) gpu_sprite(s->img, s->x, s->y, sc, s->ang, s->flip);
    }
    for (int i = 0; i < MAX_OBJ; ++i) {
        const obj_t *o = &objs[i];
        if (o->kind == OBJ_NONE) continue;
        int x = o->x >> 8, y = o->y >> 8, a = (o->ang >> 8) & 255;
        if (o->kind == OBJ_BOMB)       gpu_sprite(SPR_BOMB, x, y, 256, (o->ang >> 10) & 255, 0);
        else if (o->kind == OBJ_FRUIT) gpu_sprite(FRUITS[o->type].whole, x, y, 256, a, o->flip);
        else                           gpu_sprite(FRUITS[o->type].half, x, y, 256, a, o->flip);
    }
    for (int i = 0; i < MAX_POP; ++i) {
        const popup_t *p = &popups[i];
        if (p->used) gpu_text_shadow(p->x, p->y - p->age / 2, p->text, COL_LIGHT_YELLOW, COL_DARK_RED, 2);
    }
}

static void draw_center(const char *s, int y, unsigned color, unsigned shadow, int scale)
{
    gpu_text_shadow((FB_W - gpu_text_width(s, scale)) / 2, y, s, color, shadow, scale);
}

static void draw_title(void)
{
    gpu_bg(5);
    static const uint8_t spin_imgs[5] = {SPR_WATERMELON, SPR_ORANGE, SPR_APPLE, SPR_LEMON, SPR_KIWI};
    for (int i = 0; i < 5; ++i) {
        int a = frame_no * 2 + i * 51;
        int x = 256 + ((icos(a) * 190) >> 14);
        int y = 190 + ((isin(a) * 60) >> 14);
        gpu_sprite(spin_imgs[i], x, y, 230 + ((isin(frame_no * 3 + i * 40) * 30) >> 14), frame_no + i * 40, 0);
    }
    draw_center("FRUIT", 22, COL_RED, COL_INK, 4);
    draw_center("NINJA", 84, COL_GOLD, COL_INK, 4);
    if (game_control.mode == CONTROL_POSE) {
        draw_center("SLICE WITH YOUR HANDS - AVOID BOMBS", 150, COL_WHITE, COL_INK, 1);
        draw_center("HOLD A HAND ON START", 222, COL_GOLD, COL_INK, 1);
    } else {
        draw_center("SWIPE FRUIT - AVOID BOMBS", 150, COL_WHITE, COL_INK, 1);
    }
    draw_button(&BTN_START);
    char txt[20];
    fmt_uint(txt, "BEST ", best);
    gpu_text_shadow(8, 8, txt, COL_CREAM, COL_SHADOW, 1);
}

static void draw_pose_ui(void)
{
    if (state == ST_PLAY && pose_waiting)
        pose_ui_draw_prompt(&pose_ui, 104, "STEP INTO VIEW", "STAND 2M BACK, ARMS VISIBLE");
    if (state == ST_PAUSE && pose_lost_pause)
        draw_center("PLAYER LOST", 240, COL_RED, COL_INK, 1);
#if !FN_DUAL_POSE_PIP
    pose_ui_draw_panel(&pose_ui, 418, 232);
#endif
    if (state != ST_PLAY) pose_ui_draw_cursors(&pose_ui);
}

static void draw(void)
{
    if (state == ST_TITLE) {
        draw_title();
#if FN_SD_ENABLED
        draw_button(&BTN_MENU);
#endif
        if (game_control.mode == CONTROL_POSE) draw_pose_ui();
        return;
    }
    gpu_bg(0);
    draw_objects();
    draw_trail();
    draw_hud();
    if (state == ST_PAUSE) {
        gpu_rect(140, 60, 232, 196, COL_INK);
        draw_center("PAUSED", 74, COL_GOLD, COL_SHADOW, 3);
        draw_button(&BTN_RESUME);
        draw_button(&BTN_RESTART);
    } else if (state == ST_OVER) {
        draw_center("GAME OVER", 100, COL_RED, COL_INK, 4);
        char txt[20];
        fmt_uint(txt, "SCORE ", score);
        draw_center(txt, 170, COL_GOLD, COL_INK, 2);
        draw_button(&BTN_RETRY);
    }
    if (flash > 8) gpu_rect(0, 0, FB_W, FB_H, COL_WHITE);
#if FN_SD_ENABLED
    if (state != ST_PLAY) draw_button(&BTN_MENU);
#endif
    if (game_control.mode == CONTROL_POSE) draw_pose_ui();
}

/* ------------------------------------------------------------ main */
int main(void)
{
    uint32_t sent = gpu_swaps();
    int first_frame = 1;
    uint32_t t_mark = MTIME_LO;
    int f_mark = 0;

    GPIO_OUT = 1;
#if FN_SD_ENABLED
    best = (int)game_record_load();
    uint32_t stored_best = (uint32_t)best;
    int previous_state = ST_TITLE;
#endif
    game_control_init(&game_control,GAME_CONTROL_BOOT_PTR,CONTROL_GAME_FRUIT,MTIME_LO);
    pose_ui_reset(&pose_ui, game_control.ms);
    state = FN_START_STATE;
    reset_game();
    for (int i = 0; i < FN_FAST_FORWARD; ++i) update();
    if (GPU_REG_ID != GPU_ID_VALUE) GPIO_OUT = 2;

    for (;;) {
        /* one frame in flight: draw frame N+1 once frame N is on screen, so
         * the GPU renders it during that frame and input latency is 1 frame */
        while ((uint16_t)(sent - gpu_swaps()) != 0u) {
            game_control_service(&game_control);
        }
#if FN_SD_ENABLED
        if(returning_to_menu) {
            if(game_control_stop(&game_control))storage_jump(0x80018000u);
            continue;
        }
#endif
        game_control_service(&game_control);
        touch_poll();
        if(game_control.mode==CONTROL_POSE) {
            game_control_poll(&game_control,game_control_now(&game_control,MTIME_LO));
            pose_ui_update(&pose_ui,game_control.ms);
        }
        update();
#if FN_SD_ENABLED
        if(returning_to_menu) {
            if(game_control_stop(&game_control))storage_jump(0x80018000u);
            continue;
        }
        if (state == ST_OVER && previous_state != ST_OVER) {
            if (score > best) best = score;
            if ((uint32_t)best > stored_best) {
                int save_result = game_record_save((uint32_t)best);
                uart_puts(save_result ? "SD SAVE FAILED\n" : "SD SAVE OK\n");
                if (!save_result) stored_best = (uint32_t)best;
            }
        }
        previous_state = state;
#endif
        draw();
        gpu_swap();
        sent++;
        if (first_frame) {
            first_frame = 0;
            uart_puts("\nFruit Ninja FPGA: s80 RISC-V @157.5MHz, GPU 1024x600\n");
#if FN_DEMO_MODE
            uart_puts("mode DEMO (AI enabled)\n");
#else
            uart_puts("mode MANUAL (START / PAUSE / RESUME / RESTART)\n");
#endif
        }
        GPIO_OUT = (uint32_t)((frame_no >> 5) & 1) | (state == ST_PLAY ? 2u : 0u);
        if (frame_no - f_mark >= 300) {
            uint32_t now = MTIME_LO;
            uint32_t kcycles = (now - t_mark) / 1000u;
            uint32_t fps10 = kcycles ? (uint32_t)(frame_no - f_mark) * (CPU_CLOCK_HZ / 100u) / kcycles : 0;
            uart_puts("frame ");
            uart_putu((uint32_t)frame_no);
            uart_puts(" fps x10 ");
            uart_putu(fps10);
            uart_puts(" score ");
            uart_putu((uint32_t)score);
            uart_puts(" best ");
            uart_putu((uint32_t)best);
            uart_puts(" state ");
            uart_putu((uint32_t)state);
            uart_puts("\n");
            t_mark = now;
            f_mark = frame_no;
        }
    }
    return 0;
}
