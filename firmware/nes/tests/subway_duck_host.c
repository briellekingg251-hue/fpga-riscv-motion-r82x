/* Host test of the shoulder-line crouch in the patched Subway pose_input.c.
 *
 * Drives pose_input_submit() with 15.6 fps samples (64 ms apart) of a
 * realistic body: standing torso 200 px; crouch foreshortens it by 40 % and
 * the hips drop less than the shoulders (shoulders 250 -> 400, hips 450 -> 520).
 * Build: gcc -I<fw> <fw>/pose_input.c subway_duck_host.c */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pose_input.h"

#define STEP_MS 64u
static unsigned checks;
#define CHECK(c) do { ++checks; if (!(c)) { fprintf(stderr, "FAIL %s:%d %s (t=%u)\n", \
    __FILE__, __LINE__, #c, now); exit(1); } } while (0)

static uint32_t now = 1000, seq, epoch;

static int duck(void) { return (pose_input_state() & POSE_INPUT_DUCK) != 0; }

/* Shoulders (0,1), hips (6,7) and knees (8,9) at the given heights; tilt
 * lowers the right shoulder (rejected by body() when > torso/2 in Subway).
 * expect_valid is the published pose_valid. */
static control_frame_t last;
static void sample_ex(int shoulder_y, int hip_y, int knee_y, int tilt, int expect_valid)
{
    control_pose_snapshot_t s;
    memset(&s, 0, sizeof s);
    s.seq = ++seq; s.session_epoch = epoch; s.track_epoch = 1; s.flags = CONTROL_POSE_VALID;
    s.capture_ms = now; s.complete_ms = now + 5;
    const int x[12] = {565, 715, 0, 0, 0, 0, 580, 700, 585, 695, 0, 0};
    const int y[12] = {shoulder_y - tilt / 2, shoulder_y + tilt / 2, 0, 0, 0, 0,
                       hip_y, hip_y, knee_y, knee_y, 0, 0};
    for (unsigned j = 0; j < 12; ++j) {
        int on = (j <= 1) || (j == 6 || j == 7) || ((j == 8 || j == 9) && knee_y > 0);
        s.joint[j].x = (int16_t)x[j]; s.joint[j].y = (int16_t)y[j];
        s.joint[j].logit = 0; s.joint[j].valid = (uint32_t)on;
    }
    CHECK(pose_input_submit(&s, now + 10, 1) == 1);
    control_poll(&last);
    CHECK(last.pose_valid == (uint32_t)expect_valid);
    CHECK(last.actions.duck_held == (uint32_t)duck());
    now += STEP_MS;
}

static void sample(int shoulder_y, int hip_y, int knee_y) { sample_ex(shoulder_y, hip_y, knee_y, 0, 1); }

static void stand(unsigned n) { for (unsigned i = 0; i < n; ++i) sample(250, 450, 580); }

static void session(void)
{
    /* The publication sequence is global and keeps increasing across
     * sessions (pose_input rejects one that goes backwards). */
    control_reset(++epoch);
}

int main(void)
{
    /* 1. standing is never a crouch */
    session();
    for (unsigned i = 0; i < 16; ++i) { sample(250, 450, 580); CHECK(!duck()); }

    /* 2. realistic crouch: enters on the 2nd sample (60 ms debounce) and is
     *    held for 2 s although the torso is 40 % shorter than calibrated */
    sample(400, 520, 590); CHECK(!duck());
    sample(400, 520, 590); CHECK(duck());
    for (unsigned i = 0; i < 31; ++i) { sample(400 + (int)(i % 3), 520, 590); CHECK(duck()); }

    /* 3. standing up releases on the 2nd sample and stays released */
    sample(250, 450, 580); CHECK(duck());
    sample(250, 450, 580); CHECK(!duck());
    for (unsigned i = 0; i < 8; ++i) { sample(250, 450, 580); CHECK(!duck()); }

    /* 4. hysteresis: 370 enters; 340 (above 324) keeps; 320 releases */
    sample(370, 500, 590); sample(370, 500, 590); CHECK(duck());
    sample(340, 490, 590); sample(340, 490, 590); CHECK(duck());
    sample(320, 480, 590); sample(320, 480, 590); CHECK(!duck());

    /* 5. exactly at the line counts; one sample below the line does not */
    stand(4);
    sample(360, 500, 590); sample(360, 500, 590); CHECK(duck());
    stand(2); CHECK(!duck());
    sample(380, 500, 590); CHECK(!duck());
    sample(250, 450, 580); CHECK(!duck());
    stand(3); CHECK(!duck());

    /* 6. crouch without knees in the picture */
    sample(410, 525, 0); sample(410, 525, 0); CHECK(duck());
    for (unsigned i = 0; i < 10; ++i) { sample(410, 525, 0); CHECK(duck()); }
    stand(2); CHECK(!duck());

    /* 7. a fresh session that starts crouched (no calibration yet) */
    session();
    sample(400, 520, 590); CHECK(!duck());
    sample(400, 520, 590); CHECK(duck());
    for (unsigned i = 0; i < 31; ++i) { sample(400, 520, 590); CHECK(duck()); }
    stand(2); CHECK(!duck());
    /* after standing, it calibrates upright and still crouches normally */
    stand(10);
    CHECK(pose_input_state() & POSE_INPUT_CALIBRATED);
    sample(400, 520, 590); sample(400, 520, 590); CHECK(duck());
    sample(400, 520, 590); CHECK(duck());

    /* 8. crouch with one leaning sample in four (body() rejects tilt > t/3):
     *    crouch, lane and pose_valid hold for the whole 2 s */
    stand(6);
    CHECK(last.actions.target_lane == 2);
    sample(400, 520, 590); sample(400, 520, 590); CHECK(duck());
    for (unsigned i = 0; i < 32; ++i) {
        if (i % 4 == 3) sample_ex(400, 520, 590, 70, 1);
        else sample(400, 520, 590);
        CHECK(duck()); CHECK(last.actions.target_lane == 2);
    }
    /* 9. three rejects in a row still hold; the fourth releases (scenario 8
     *    ended on a reject, so restart the run with a good sample) */
    sample(400, 520, 590); CHECK(duck());
    sample_ex(400, 520, 590, 70, 1); sample_ex(400, 520, 590, 70, 1); sample_ex(400, 520, 590, 70, 1);
    CHECK(duck());
    sample_ex(400, 520, 590, 70, 0); CHECK(!duck()); CHECK(last.actions.target_lane == 0);
    /* 10. a held state still times out when samples stop (camera loss) */
    stand(6); sample(400, 520, 590); sample(400, 520, 590); CHECK(duck());
    sample_ex(400, 520, 590, 70, 1); CHECK(duck());
    now += 400; pose_input_tick(now); CHECK(!duck());
    /* 11. standing with one leaning sample keeps the lane */
    stand(8); CHECK(last.actions.target_lane == 2);
    sample_ex(250, 450, 580, 110, 1); CHECK(last.actions.target_lane == 2); CHECK(!duck());
    stand(1); CHECK(last.actions.target_lane == 2);

    printf("SUBWAY_SHOULDER_DUCK_HOST_PASS checks=%u\n", checks);
    return 0;
}
