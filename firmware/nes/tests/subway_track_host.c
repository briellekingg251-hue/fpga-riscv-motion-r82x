/* Subway crouch through the whole firmware chain on the host:
 * MMIO fixture -> decoder -> pose service -> confirm_track -> pose_input ->
 * game_control -> sw_update_pose, at the board's 15.6 fps (64 ms samples).
 *
 * Unlike the R61 test, the body is realistic: a crouch shortens the torso by
 * 40 % (shoulders 250 -> 400, hips 450 -> 520) within one or two samples, and
 * the detector box lags the pose by one frame, as on the board.  Checks: the
 * crouch is published within 3 samples, held for 2 s without any track break,
 * survives occasional leaning samples, releases on standing up; a sudden jump
 * of the body (another person) still breaks the track.
 *
 * Built against a copy of a Subway fw tree (tests/ next to fw/), with the
 * fusion fixture files production_pose_host.c and game_pose_fixture.h. */
#define PRODUCTION_POSE_FIXTURE_ONLY 1
#include "production_pose_host.c"

enum { FRAME_MS = 64, HOLD_SAMPLES = 31 };
/* lean: horizontal shoulder shift against the hips (side-lane perspective). */
/* hide: bit j set = joint j not detected (e.g. a hip hidden by the knees). */
typedef struct { int sy, hy, ky, tilt, lean, hide; } body_t;
static const body_t STAND = {250, 450, 545, 0};
static const body_t HALF = {330, 490, 548, 0};
static const body_t CROUCH = {400, 520, 552, 0};
static body_t previous;
static int previous_u = 640;

static int at(int u) { return 1279 - u; }
static void clear_objects(void) { for (int i = 0; i < SW_MAX_OBJ; i++) sw_objs[i].kind = K_NONE; }
static void ticks(int n) {
    app_input_t in = {0};
    for (int i = 0; i < n; i++) { clear_objects(); sw_update_pose(&in, &game.frame, 0); assert(sw_state == SW_PLAY); }
}

/* Same encoding as the fixture's tensor_scaled(), for an arbitrary body. */
static void tensor_pose(uint32_t bank, int cx, body_t b) {
    const int step = 2;
    assert(!pose_held || bank != (regs[0x014 / 4] >> 31));
    bank_origin[bank] = cx - 300; bank_step[bank] = step;
    int8_t heat[216][12], off[216][24];
    memset(heat, -120, sizeof heat); memset(off, 0, sizeof off);
    const int dx[12] = {-60, 60, -80, 80, -100, 100, -40, 40, -40, 40, -40, 40};
    const int ys[12] = {b.sy - b.tilt / 2, b.sy + b.tilt / 2, (b.sy + b.hy) / 2, (b.sy + b.hy) / 2,
                        b.hy - 20, b.hy - 20, b.hy, b.hy, b.ky, b.ky, 570, 570};
    for (uint32_t j = 0; j < 12u; j++) {
        int x = cx + dx[j] + (j <= 5 ? b.lean : 0), y = ys[j];
        int first = 15 * step / 2, grid = 16 * step;
        int c = (x - bank_origin[bank] - first) / grid, r = (y - first) / grid;
        if (c > 11) c = 11;
        if (c < 0) c = 0;
        if (r > 17) r = 17;
        if (r < 0) r = 0;
        uint32_t pixel = (uint32_t)(r * 12 + c);
        if (!(b.hide >> j & 1)) heat[pixel][j] = -6;
        off[pixel][j] = (int8_t)((y - (first + grid * r)) * 2 / step);
        off[pixel][j + 12u] = (int8_t)((x - (bank_origin[bank] + first + grid * c)) * 2 / step);
    }
    uint8_t bytes[7776];
    memcpy(bytes, heat, sizeof heat); memcpy(bytes + sizeof heat, off, sizeof off);
    for (uint32_t w = 0; w < 1944u; w++) {
        uint32_t k = w * 4u;
        regs[(0x4000u + bank * 0x2000u) / 4u + w] =
            bytes[k] | ((uint32_t)bytes[k + 1] << 8) | ((uint32_t)bytes[k + 2] << 16) | ((uint32_t)bytes[k + 3] << 24);
    }
}

/* One camera sample; the detector box follows the PREVIOUS body (one-frame lag). */
static void sample(int u, body_t b) {
    app_input_t in = {0};
    ++frame_count; frame_capture += FRAME_MS;
    uint32_t bank = frame_count & 1u;
    int lag = 2 * ((previous.sy + previous.hy) / 2 - 350);
    /* The box lags one frame both vertically and horizontally. */
    detector(frame_count, frame_capture, at(previous_u), lag);
    tensor_pose(bank, at(u), b);
    install(bank, frame_count, frame_capture); regs[0x094 / 4] = frame_capture + 7u;
    uint32_t pub = service.stats.published; pump(pub + 1u);
    game_control_poll(&game, regs[0x094 / 4]);
    clear_objects(); sw_update_pose(&in, &game.frame, 1); ticks(3);
    previous = b; previous_u = u;
}

static void begin_run(uint32_t session) {
    start_mode(session, CONTROL_GAME_SUBWAY);
    frame_count = 0; frame_capture = 68; move_events = 0; previous = STAND; previous_u = 640;
    sw_set_control(CONTROL_POSE, session); sw_new_run(); clear_objects();
    sw_lane = 1; sw_px = sw_lane_x(1);
    for (int i = 0; i < 8; i++) sample(640, STAND);
    assert(trajectory.confirmed && game.frame.actions.target_lane == 2 && !game.frame.actions.duck_held);
}

static int crouch_in(body_t first) {
    int n = 0;
    sample(640, first);
    while (!game.frame.actions.duck_held) { sample(640, CROUCH); assert(++n <= 3); }
    return n + 1;
}

static void hold(int samples, int lean_every) {
    for (int i = 0; i < samples; i++) {
        body_t b = CROUCH;
        if (lean_every && i % lean_every == lean_every - 1) b.tilt = 70;
        sample(640, b);
        assert(game.frame.actions.duck_held && sw_duck);
        assert(trajectory.confirmed && game.frame.actions.target_lane == 2);
    }
}

static int stand_up(void) {
    int n = 0;
    while (game.frame.actions.duck_held) { sample(640, STAND); assert(++n <= 3); }
    assert(!sw_duck && trajectory.confirmed);
    return n;
}

int main(void) {
    begin_run(101);
    uint32_t breaks = trajectory.rejections, epoch0 = trajectory.track_epoch;
    int fast = crouch_in(CROUCH);
    hold(HOLD_SAMPLES, 0);
    int up = stand_up();
    assert(trajectory.rejections == breaks && trajectory.track_epoch == epoch0);
    printf("SUBWAY_TRACK_FAST_CROUCH_PASS crouch after %d samples, held 2 s, release after %d, no track break\n", fast, up);

    int two = crouch_in(HALF);
    hold(HOLD_SAMPLES, 4);
    stand_up();
    assert(trajectory.rejections == breaks && trajectory.track_epoch == epoch0);
    printf("SUBWAY_TRACK_LEANING_CROUCH_PASS two-step crouch after %d samples, 1-in-4 leaning samples held\n", two);

    /* Side lane (left third): a crouch with a forward lean that the camera sees
     * as the shoulders shifted 0.7 torso towards the image centre. */
    for (int u = 640; u > 300; u -= 40) sample(u, STAND);
    for (int i = 0; i < 6; i++) sample(300, STAND);
    assert(game.frame.actions.target_lane == 1 && trajectory.confirmed);
    uint32_t side_breaks = trajectory.rejections;
    body_t lean = CROUCH; lean.lean = 84;   /* at(300) = 979: centre is to the left */
    int side = 0;
    do { sample(300, lean); assert(++side <= 3); } while (!game.frame.actions.duck_held);
    for (int i = 0; i < HOLD_SAMPLES; i++) {
        sample(300, lean);
        assert(game.frame.actions.duck_held && sw_duck && trajectory.confirmed);
        assert(game.frame.actions.target_lane == 1);
    }
    while (game.frame.actions.duck_held) { sample(300, STAND); assert(++side <= 40); }
    assert(trajectory.rejections == side_breaks);
    printf("SUBWAY_TRACK_SIDE_LANE_PASS leaning crouch in the left lane held 2 s, no track break\n");
    for (int u = 300; u < 640; u += 40) sample(u, STAND);
    for (int i = 0; i < 6; i++) sample(640, STAND);
    breaks = trajectory.rejections; epoch0 = trajectory.track_epoch;

    /* Crouch with hips hidden by the knees: the right hip on alternate
     * samples, and once both hips for two samples in a row. */
    {
        body_t c = CROUCH;
        crouch_in(CROUCH);
        for (int i = 0; i < HOLD_SAMPLES; i++) {
            c.hide = i % 2 ? 1 << 7 : 0;
            if (i == 10 || i == 11) c.hide = (1 << 6) | (1 << 7);
            sample(640, c);
            assert(game.frame.actions.duck_held && sw_duck && trajectory.confirmed);
        }
        stand_up();
        assert(trajectory.rejections == breaks && trajectory.track_epoch == epoch0);
        printf("SUBWAY_TRACK_HIDDEN_HIPS_PASS crouch held with one or both hips hidden, no track break\n");
    }

    /* Fast side step: 85 px per 64 ms sample (1.3 m/s on screen), box lagging. */
    {
        for (int i = 0; i < 4; i++) sample(640, STAND);
        int u = 640, after = -1;
        while (game.frame.actions.target_lane != 1) {
            u = u > 300 ? u - 85 : 300;
            sample(u, STAND);
            if (after >= 0 || u < 396) ++after;
            assert(after <= 2);
        }
        assert(trajectory.rejections == breaks && trajectory.track_epoch == epoch0);
        printf("SUBWAY_TRACK_SIDE_STEP_PASS lane published %d sample(s) after crossing, no track break\n", after);
        for (int v = u; v < 640; v += 85) sample(v, STAND);
        for (int i = 0; i < 6; i++) sample(640, STAND);
        breaks = trajectory.rejections; epoch0 = trajectory.track_epoch;
    }

    /* A different person: the body appears 450 px away in one sample. */
    for (int i = 0; i < 4; i++) sample(640, STAND);
    sample(190, STAND);
    sample(190, STAND);
    assert(trajectory.rejections > breaks || trajectory.track_epoch != epoch0);
    printf("SUBWAY_TRACK_SWAP_PASS a 450 px jump still breaks the track\n");
    puts("SUBWAY_TRACK_HOST_PASS");
    return 0;
}
