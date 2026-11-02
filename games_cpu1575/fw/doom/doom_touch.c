/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <string.h>
#include "doomkeys.h"
#include "doom_port.h"
/* Coordinates match the 512x300 GPU framebuffer (1024x600 panel / 2).
 * Arrows move; SL/SR are retained as strafe aliases. A separate contact that
 * starts outside all buttons owns horizontal look until lifted, by track ID.
 * FIRE remains a held key, so release always stops firing. */
static const doom_button_t game_buttons[] = {
    {62,170,48,40,"^",KEY_UPARROW}, {14,216,48,40,"<",KEY_STRAFE_L},
    {110,216,48,40,">",KEY_STRAFE_R}, {62,258,48,38,"v",KEY_DOWNARROW},
    {166,258,54,38,"SL",KEY_STRAFE_L}, {226,258,54,38,"SR",KEY_STRAFE_R},
    {166,210,76,38,"RUN",KEY_RSHIFT}, {420,202,78,62,"FIRE",KEY_FIRE},
    {340,202,74,44,"USE",KEY_USE}, {340,252,74,42,"GUN",0},
    {420,270,78,24,"OK",KEY_ENTER}, {450,6,56,30,"MENU",KEY_ESCAPE},
    {386,6,56,30,"MAP",KEY_TAB}, {314,6,64,30,"PAUSE",KEY_PAUSE}
};
/* Menu arrows are real arrow keys, not the gameplay strafe aliases. YES/NO
 * are distinct from ENTER: Doom's confirmation dialogs require y/n. */
static const doom_button_t menu_buttons[] = {
    {62,170,48,40,"^",KEY_UPARROW}, {14,216,48,40,"<",KEY_LEFTARROW},
    {110,216,48,40,">",KEY_RIGHTARROW}, {62,258,48,38,"v",KEY_DOWNARROW},
    {340,202,74,44,"YES",'y'}, {420,202,78,44,"NO",'n'},
    {340,252,74,42,"BACK",KEY_BACKSPACE}, {420,252,78,42,"OK",KEY_ENTER},
    {450,6,56,30,"CLOSE",KEY_ESCAPE}
};
static const doom_button_t map_buttons[] = {
    {62,170,48,40,"^",KEY_UPARROW}, {14,216,48,40,"<",KEY_LEFTARROW},
    {110,216,48,40,">",KEY_RIGHTARROW}, {62,258,48,38,"v",KEY_DOWNARROW},
    {166,210,62,38,"ZOOM-",KEY_MINUS}, {234,210,62,38,"ZOOM+",KEY_EQUALS},
    {166,258,62,38,"FOLLOW",'f'}, {234,258,62,38,"GRID",'g'},
    {340,202,74,44,"MARK",'m'}, {420,202,78,44,"CLEAR",'c'},
    {340,252,74,42,"FIT",'0'}, {420,252,78,42,"BACK",KEY_TAB},
    {450,6,56,30,"MENU",KEY_ESCAPE}
};
#define BUTTON_COUNT(a) (sizeof (a) / sizeof (a)[0])
const doom_button_t *doom_buttons = game_buttons;
unsigned doom_button_count = BUTTON_COUNT(game_buttons);
static uint8_t desired[256], reported[256];
static unsigned input_context;
static int wait_lift;
static uint32_t repeat_at[256];
static uint8_t repeat_pending[256];
static unsigned weapon = 2;
static int weapon_contact;
enum { CONTACT_BUTTON, CONTACT_LOOK, CONTACT_BLOCKED };
typedef struct { uint8_t id, role; int x, y; } contact_t;
static contact_t contacts[5];
static unsigned contact_count;
static int pending_look, look_owner = -1;
static uint32_t last_ms;
/* Physical panel pixels: reject jitter and discontinuities, then scale to
 * Doom mouse units. At default sensitivity a 200 px drag turns about 105 deg.
 * Accumulation is bounded so angleturn's signed 16-bit field cannot wrap. */
#define SWIPE_DEADZONE 4
#define SWIPE_MAX_STEP 256
#define SWIPE_GAIN 12
#define SWIPE_MAX_PENDING 1024
static int button_at(int x, int y)
{
    for (unsigned i = 0; i < doom_button_count; ++i) {
        const doom_button_t *b = doom_buttons + i;
        if (x >= b->x && x < b->x+b->w && y >= b->y && y < b->y+b->h)
            return (int)i;
    }
    return -1;
}
static void reset_contacts(void)
{
    contact_count = 0; look_owner = -1; pending_look = 0;
}
void doom_input_context(unsigned context)
{
    if (context > DOOM_INPUT_MAP || context == input_context) return;
    /* Do not carry a held MENU/OK button into the newly displayed screen.
     * Preserve reported[] so the engine still receives every old release. */
    wait_lift = contact_count != 0;
    memset(desired, 0, sizeof desired);
    memset(repeat_pending, 0, sizeof repeat_pending);
    reset_contacts(); input_context = context;
    doom_buttons = context == DOOM_INPUT_MENU ? menu_buttons :
                   context == DOOM_INPUT_MAP ? map_buttons : game_buttons;
    doom_button_count = context == DOOM_INPUT_MENU ? BUTTON_COUNT(menu_buttons) :
                        context == DOOM_INPUT_MAP ? BUTTON_COUNT(map_buttons) : BUTTON_COUNT(game_buttons);
    weapon_contact = 0;
}
unsigned doom_input_current_context(void) { return input_context; }
void doom_input_reset(void)
{
    memset(desired, 0, sizeof desired); memset(reported, 0, sizeof reported);
    memset(repeat_pending, 0, sizeof repeat_pending);
    memset(repeat_at, 0, sizeof repeat_at);
    input_context = DOOM_INPUT_GAME; wait_lift = 0;
    doom_buttons = game_buttons; doom_button_count = BUTTON_COUNT(game_buttons);
    weapon = 2; weapon_contact = 0;
    last_ms = 0; reset_contacts();
}
void doom_input_sample(uint32_t ms, int valid, unsigned count, const uint32_t *xy,
                       const uint8_t *ids)
{
    uint8_t next[256] = {0};
    contact_t fresh[5];
    int gun = 0;
    if ((uint32_t)(ms-last_ms) > 200u) reset_contacts();
    last_ms = ms;
    if (!valid || count > 5 || (count && !xy)) count = 0;
    for (unsigned p = 0; p < count; ++p) {
        if ((xy[p] & 65535u) >= 1024 || (xy[p] >> 16) >= 600) {
            count = 0; break;
        }
        if (ids) for (unsigned j = 0; j < p; ++j)
            if (ids[j] == ids[p]) { count = 0; break; }
    }
    if (wait_lift) {
        if (!count) wait_lift = 0;
        count = 0;
    }
    /* Old coordinate-only multi-touch hardware cannot identify a look owner.
     * Keep its button compatibility; single-contact look remains supported. */
    if (!count || (!ids && count > 1)) reset_contacts();
    int owner_present = 0;
    for (unsigned p = 0; p < count; ++p)
        if ((int)(ids ? ids[p] : 0) == look_owner) owner_present = 1;
    if (!owner_present) { look_owner = -1; pending_look = 0; }
    for (unsigned p = 0; p < count; ++p) {
        unsigned rx = xy[p] & 65535u, ry = xy[p] >> 16;
        int x = (int)(rx / 2), y = (int)(ry / 2);
        int b = button_at(x, y);
        contact_t c = {ids ? ids[p] : 0, CONTACT_BLOCKED, (int)rx, (int)ry};
        int previous = -1;
        if (ids || count == 1) {
            for (unsigned j = 0; j < contact_count; ++j)
                if (contacts[j].id == c.id) { previous = (int)j; break; }
            if (previous >= 0) c = contacts[previous];
            else if (b >= 0) c.role = CONTACT_BUTTON;
            else if (input_context == DOOM_INPUT_GAME && look_owner < 0) {
                c.role = CONTACT_LOOK; look_owner = c.id;
            }
        } else c.role = CONTACT_BUTTON;
        if (c.role == CONTACT_BUTTON && b >= 0) {
            if (doom_buttons[b].key) next[doom_buttons[b].key] = 1; else gun = 1;
        } else if (c.role == CONTACT_LOOK && previous >= 0) {
            int dx = (int)rx-c.x, dy = (int)ry-c.y;
            int ax = dx < 0 ? -dx : dx, ay = dy < 0 ? -dy : dy;
            if (ax > SWIPE_MAX_STEP || ay > SWIPE_MAX_STEP) {
                pending_look = 0; c.x = (int)rx; c.y = (int)ry;
            } else if (ax >= SWIPE_DEADZONE && ax >= ay) {
                pending_look += dx * SWIPE_GAIN;
                if (pending_look > SWIPE_MAX_PENDING) pending_look = SWIPE_MAX_PENDING;
                if (pending_look < -SWIPE_MAX_PENDING) pending_look = -SWIPE_MAX_PENDING;
                c.x = (int)rx; c.y = (int)ry;
            } else if (ay >= SWIPE_DEADZONE && ay > ax) {
                c.x = (int)rx; c.y = (int)ry;
            }
        }
        fresh[p] = c;
    }
    memcpy(contacts, fresh, count * sizeof fresh[0]); contact_count = count;
    if (gun && !weapon_contact) weapon = weapon == 7 ? 1 : weapon+1;
    if (gun) next['0'+weapon] = 1;
    weapon_contact = gun;
    for (unsigned k = 0; k < 256; ++k) {
        int arrow = k == KEY_UPARROW || k == KEY_DOWNARROW ||
                    k == KEY_LEFTARROW || k == KEY_RIGHTARROW;
        if (input_context != DOOM_INPUT_MENU || !arrow || !next[k]) repeat_pending[k] = 0;
        else if (!desired[k]) { repeat_at[k] = ms + 350u; repeat_pending[k] = 0; }
        else if ((int32_t)(ms - repeat_at[k]) >= 0) {
            repeat_pending[k] = 1; repeat_at[k] = ms + 110u;
        }
    }
    memcpy(desired, next, sizeof desired);
}
int doom_input_mouse_delta(void)
{
    int dx = pending_look; pending_look = 0; return dx;
}
/* Convergent state delivery has no bounded event queue that could lose a
 * release. Always release old keys before pressing newly selected keys. */
int doom_input_event(int *pressed, unsigned char *key)
{
    for (unsigned pass = 0; pass < 2; ++pass)
        for (unsigned k = 0; k < 256; ++k)
            if (desired[k] != reported[k] && desired[k] == pass) {
                reported[k] = desired[k]; *pressed = desired[k]; *key = (unsigned char)k;
                return 1;
            }
    for (unsigned k = 0; k < 256; ++k)
        if (repeat_pending[k] && desired[k] && reported[k]) {
            repeat_pending[k] = 0; *pressed = 1; *key = (unsigned char)k;
            return 1;
        }
    return 0;
}
int doom_input_held(unsigned char key) { return desired[key]; }
