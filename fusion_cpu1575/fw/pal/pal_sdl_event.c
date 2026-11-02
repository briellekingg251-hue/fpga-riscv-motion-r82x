/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "pal_sdl_backend.h"
#include "pal_touch.h"
#include "../touch.h"
#include <sdl-event.h>
#include <sdl-timer.h>

enum { KEY_COUNT = SDLK_PAGEDOWN + 1 };
typedef struct { uint32_t pal; uint8_t sdl; } key_map_t;
static const key_map_t key_map[] = {
    {PAL_MENU, SDLK_ESCAPE}, {PAL_CONFIRM, SDLK_RETURN},
    {PAL_DOWN, SDLK_DOWN}, {PAL_LEFT, SDLK_LEFT},
    {PAL_UP, SDLK_UP}, {PAL_RIGHT, SDLK_RIGHT},
    {PAL_PAGEUP, SDLK_PAGEUP}, {PAL_PAGEDOWN, SDLK_PAGEDOWN},
    {PAL_AUTO, SDLK_A}, {PAL_STATUS, SDLK_S}
};
#define MAP_COUNT (sizeof(key_map) / sizeof(key_map[0]))
#define HELD_KEYS (PAL_UP | PAL_DOWN | PAL_LEFT | PAL_RIGHT | PAL_PAGEUP | PAL_PAGEDOWN)

static SDL_Event queue[PAL_SDL_EVENT_CAPACITY];
static unsigned queued;
static SDL_Event deferred[PAL_SDL_DEFERRED_CAPACITY];
static unsigned deferred_count;
static uint8_t keyboard[KEY_COUNT];
static pal_touch_state_t touch_state;
static uint32_t pending_pressed, last_sequence, last_fresh_ms, overflow_count;
static int have_sequence;
static int action_armed = 1;
static const char *last_error = "";

static int error(const char *message)
{
    last_error = message;
    return -1;
}

const char *pal_sdl_events_error(void) { return last_error; }
uint32_t pal_sdl_events_overflows(void) { return overflow_count; }

void pal_sdl_events_reset(void)
{
    queued = deferred_count = 0;
    touch_state.held = touch_state.deadline = 0;
    pending_pressed = last_sequence = last_fresh_ms = overflow_count = 0;
    have_sequence = 0;
    action_armed = 1;
    last_error = "";
    for (unsigned i = 0; i < KEY_COUNT; ++i) keyboard[i] = 0;
}

static int valid_event(const SDL_Event *event)
{
    return event && event->type <= SDL_USEREVENT &&
        (event->type == SDL_USEREVENT ||
         (event->key.keysym.sym > SDLK_NONE && event->key.keysym.sym < KEY_COUNT));
}

static void remove_event(unsigned index)
{
    --queued;
    for (unsigned i = index; i < queued; ++i) queue[i] = queue[i + 1];
}

static void flush_deferred(void)
{
    unsigned count = deferred_count;
    if (count > PAL_SDL_EVENT_CAPACITY - queued) count = PAL_SDL_EVENT_CAPACITY - queued;
    for (unsigned i = 0; i < count; ++i) queue[queued++] = deferred[i];
    deferred_count -= count;
    for (unsigned i = 0; i < deferred_count; ++i) deferred[i] = deferred[i + count];
}

static void append_key(unsigned type, unsigned sym)
{
    SDL_Event event = {0};
    event.key.type = (uint8_t)type;
    event.key.keysym.sym = (uint8_t)sym;
    if (deferred_count || queued == PAL_SDL_EVENT_CAPACITY)
        deferred[deferred_count++] = event;
    else queue[queued++] = event;
}

int pal_sdl_events_pump(void)
{
    if (pal_video_service) pal_video_service();
    touch_sample_t sample = touch_read();
    uint32_t now = SDL_GetTicks();
    int fresh = !have_sequence || sample.sequence != last_sequence;
    if (fresh) {
        have_sequence = 1;
        last_sequence = sample.sequence;
        last_fresh_ms = now;
    }
    int x = 0, y = 0;
    /* fn_gt911 state: count at 7:4; contact ID occupies 15:8. */
    unsigned count = (sample.status >> 4) & 15u;
    int healthy = (sample.status & (TOUCH_READY | TOUCH_FAULT)) == TOUCH_READY;
    int stale = (uint32_t)(now - last_fresh_ms) >= PAL_SDL_TOUCH_STALE_MS;
    int down = healthy && (sample.status & TOUCH_DOWN) && count >= 1u && count <= 5u &&
        !stale && touch_map(sample.xy, &x, &y);
    int armed = action_armed;
    /* Synthetic stale/fault releases must not turn recovery of the same
     * held finger into another OK/BACK. Only an explicit healthy fresh lift
     * re-arms actions; movement may resume as soon as valid data returns. */
    if (fresh && healthy && !(sample.status & TOUCH_DOWN) && count == 0) armed = 1;
    /* Invalid samples release movement immediately, but do not cancel a
     * previously accepted action click awaiting PAL's state snapshot. */
    if (!healthy || stale || ((sample.status & TOUCH_DOWN) && !down)) pending_pressed &= ~HELD_KEYS;
    pal_touch_state_t next = touch_state;
    pal_touch_events_t events = pal_touch_update(&next, now, healthy, down, x, y);
    uint32_t action = events.held & ~HELD_KEYS;
    if (action && !armed && !(touch_state.held & action)) {
        next.held &= ~action;
        events.held &= ~action;
        events.pressed &= ~action;
    } else if (events.pressed & ~HELD_KEYS) armed = 0;
    flush_deferred();
    unsigned needed = 0;
    for (unsigned i = 0; i < MAP_COUNT; ++i) {
        if (events.released & key_map[i].pal) ++needed;
        if (events.pressed & key_map[i].pal) ++needed;
    }
    if (needed > PAL_SDL_EVENT_CAPACITY - queued + PAL_SDL_DEFERRED_CAPACITY - deferred_count) {
        ++overflow_count;
        return error("PAL touch deferred queue full; new transition rejected");
    }
    /* Release the previous direction before pressing the new one. */
    for (unsigned i = 0; i < MAP_COUNT; ++i)
        if (events.released & key_map[i].pal) append_key(SDL_KEYUP, key_map[i].sdl);
    for (unsigned i = 0; i < MAP_COUNT; ++i)
        if (events.pressed & key_map[i].pal) append_key(SDL_KEYDOWN, key_map[i].sdl);
    touch_state = next;
    action_armed = armed;
    pending_pressed |= events.pressed;
    if (deferred_count) {
        if (needed) ++overflow_count;
        return error("PAL SDL event queue full; touch snapshots deferred");
    }
    return 0;
}

int SDL_PushEvent(SDL_Event *event)
{
    if (!valid_event(event)) return error("Invalid PAL SDL event");
    flush_deferred();
    if (queued == PAL_SDL_EVENT_CAPACITY) {
        ++overflow_count;
        return error("PAL SDL event queue full");
    }
    queue[queued++] = *event;
    /* Pushed keyboard events do not change the physical keyboard state. */
    return 0; /* SDL 1.2 / Navy contract */
}

int SDL_PollEvent(SDL_Event *event)
{
    int result = pal_sdl_events_pump();
    if (!queued) return result < 0 ? -1 : 0;
    /* Drain existing events even after a pump overflow so the deferred
     * transition can fit on a subsequent pump. Poll(NULL) only checks. */
    if (event) {
        *event = queue[0];
        remove_event(0);
    }
    return 1;
}

int SDL_WaitEvent(SDL_Event *event)
{
    if (!event) return error("SDL_WaitEvent requires an output event");
    for (;;) {
        int result = SDL_PollEvent(event);
        if (result) return result;
        SDL_Delay(1);
    }
}

int SDL_PeepEvents(SDL_Event *events, int numevents, int action, uint32_t mask)
{
    if (numevents < 0 || (numevents && !events) ||
        (action != SDL_ADDEVENT && action != SDL_PEEKEVENT && action != SDL_GETEVENT))
        return error("Invalid SDL_PeepEvents arguments");
    if (action == SDL_ADDEVENT) {
        flush_deferred();
        if ((unsigned)numevents > PAL_SDL_EVENT_CAPACITY - queued) {
            ++overflow_count;
            return error("PAL SDL event queue full");
        }
        for (int i = 0; i < numevents; ++i)
            if (!valid_event(&events[i])) return error("Invalid PAL SDL event");
        for (int i = 0; i < numevents; ++i) queue[queued++] = events[i];
        return numevents;
    }
    int found = 0;
    for (unsigned i = 0; i < queued && found < numevents; ) {
        if (mask & SDL_EVENTMASK(queue[i].type)) {
            events[found++] = queue[i];
            if (action == SDL_GETEVENT) { remove_event(i); continue; }
        }
        ++i;
    }
    return found;
}

uint8_t *SDL_GetKeyState(int *numkeys)
{
    /* PAL-Navy polls state after draining events and repeats every held key.
     * Keep movement/page keys held, but expose action buttons for one state
     * snapshot per physical press, preventing unintended repeated OK/BACK.
     * pending_pressed also preserves a tap released before the next snapshot. */
    (void)pal_sdl_events_pump();
    uint32_t visible = (touch_state.held & HELD_KEYS) | pending_pressed;
    for (unsigned i = 0; i < KEY_COUNT; ++i) keyboard[i] = 0;
    for (unsigned i = 0; i < MAP_COUNT; ++i)
        if (visible & key_map[i].pal) keyboard[key_map[i].sdl] = 1;
    pending_pressed = 0;
    if (numkeys) *numkeys = KEY_COUNT;
    return keyboard;
}
