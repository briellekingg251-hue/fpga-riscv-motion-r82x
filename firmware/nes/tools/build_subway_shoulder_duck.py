"""Rebuild the 162 MHz pose games with the user's Subway crouch rule.

User request (board test 2026-10-14): crouching was still poorly recognised;
"trigger crouch when the shoulders are below half of the picture".

This reproduces fusion tools/build_pose_r62_games.py exactly (posefix patches,
then the R61 patches, 162 MHz, banner "O2 CPU 162MHZ"; the fusion scripts are
loaded, never edited) and appends SUBWAY_SHOULDER to SUBWAY's pose_input.c:

  * crouch = shoulder midpoint at or below camera line 360 of 720 (half the
    picture); stand up once it is back above line 324 (5 % hysteresis); the
    existing 60 ms debounce (one 15.6 fps sample) still applies;
  * the rule runs first on every accepted pose sample, so it needs neither a
    standing calibration nor knees;
  * a crouch foreshortens the torso by more than the 25 % scale tolerance, so
    the ZONE-mode scale-change reset is skipped while a crouch is held or
    pending, and calibration happens upright only (otherwise that reset would
    cancel the crouch every frame);
  * it replaces the R61 "shoulder and hip drop by 30 % of the torso" rule;
  * up to 3 consecutive body-gate rejects of otherwise fresh samples hold the
    crouch and lane (a foreshortened, slightly leaning crouch fails body()'s
    torso-relative gates more easily); stale/invalid samples, track resets
    and longer runs release as before.

SUBWAY_TRACK (tools/subway_track_patches.py) keeps the track through a
crouch in game_pose_service.c confirm_track().

SUBWAY_SHOULDER is a standalone list so the fusion session's official games
build can import it unchanged.  The threshold is POSE_DUCK_SHOULDER_Y.

usage: python -I tools/build_subway_shoulder_duck.py [OUT_NAME]
       (default OUT_NAME games_162_subway_shoulder_run04 under fusion firmware_o2_view/)
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from subway_track_patches import SUBWAY_TRACK  # noqa: E402

FUSION = Path("E:/Codex_workplace/cpu_pose_touch_fusion_20261008")
HZ = 162000000
LABEL = "O2 CPU 162MHZ"
BASE_CARD = FUSION / "firmware_o2_view/games_162_run01/sdcard"
ROM = FUSION / "firmware_o2_view/build_162_run01/program.hex"

_RETIRED_RULE = (
    "    uint32_t want=frame.actions.duck_held;\n"
    "    int32_t ds=sy-base_shoulder_y, dh=hy-base_hip_y;\n"
    "    /* R61: knees are optional. Learn the thigh baseline while standing once\n"
    "     * knees are seen; without it (or without knees now) the shoulder and hip\n"
    "     * drop alone mark a crouch. */\n"
    "    if (!base_leg && leg>0 && !want && ds<frac(base_torso,c.duck_exit_q8) &&\n"
    "        dh<frac(base_torso,c.duck_exit_q8)) base_leg=leg;\n"
    "    if (!want && ds>=frac(base_torso,c.duck_enter_q8) && dh>=frac(base_torso,c.duck_enter_q8) &&\n"
    "        (!leg || !base_leg || leg<=frac(base_leg,c.knee_compress_q8))) want=1;\n"
    "    if (want && (ds<=frac(base_torso,c.duck_exit_q8) ||\n"
    "                 dh<=frac(base_torso,c.duck_exit_q8))) want=0;\n"
    "    if (want!=frame.actions.duck_held) {\n"
    "        if (duck_candidate!=want+1) { duck_candidate=want+1; duck_candidate_ms=ms; }\n"
    "        if (elapsed(ms,duck_candidate_ms,c.debounce_ms)) {\n"
    "            frame.actions.duck_held=want; duck_candidate=0;\n"
    "        }\n"
    "    } else duck_candidate=0;\n")

# (name, file, expected anchor count, anchor, replacement) -- the posefix format.
SUBWAY_SHOULDER = [
    ("shoulder crouch line", "pose_input.c", 1,
     "#define POSE_SUBWAY_ZONES 1   /* default lane mode: body position (zones) */\n#endif\n",
     "#define POSE_SUBWAY_ZONES 1   /* default lane mode: body position (zones) */\n#endif\n"
     "/* Board request 2026-10-14: crouch while the shoulder midpoint is in the\n"
     " * lower half of the 1280x720 camera picture (y grows downwards). */\n"
     "#ifndef POSE_DUCK_SHOULDER_Y\n"
     "#define POSE_DUCK_SHOULDER_Y 360\n"
     "#endif\n"
     "#define POSE_DUCK_RELEASE_Y (POSE_DUCK_SHOULDER_Y-36)   /* 5% hysteresis */\n"),
    ("shoulder crouch rule", "pose_input.c", 1,
     "static void subway(int32_t x,int32_t sy,int32_t hy,int32_t w,int32_t t,\n",
     "/* Shoulder-line crouch: needs no standing calibration and no knees. The\n"
     " * existing debounce (60 ms, one 15.6 fps sample) filters a single outlier. */\n"
     "static void subway_duck(int32_t sy,uint32_t ms) {\n"
     "    uint32_t want=frame.actions.duck_held;\n"
     "    if (!want && sy>=POSE_DUCK_SHOULDER_Y) want=1;\n"
     "    else if (want && sy<POSE_DUCK_RELEASE_Y) want=0;\n"
     "    if (want!=frame.actions.duck_held) {\n"
     "        if (duck_candidate!=want+1) { duck_candidate=want+1; duck_candidate_ms=ms; }\n"
     "        if (elapsed(ms,duck_candidate_ms,c.debounce_ms)) {\n"
     "            frame.actions.duck_held=want; duck_candidate=0;\n"
     "        }\n"
     "    } else duck_candidate=0;\n"
     "}\n"
     "static void subway(int32_t x,int32_t sy,int32_t hy,int32_t w,int32_t t,\n"),
    ("crouch first; no scale reset while ducking", "pose_input.c", 1,
     "    if (c.lane_zones) subway_zone(x,ms);\n"
     "    if (calibrated && (ab(w-base_width)>frac(base_width,c.scale_tolerance_q8) ||\n",
     "    if (c.lane_zones) subway_zone(x,ms);\n"
     "    subway_duck(sy,ms);\n"
     "    /* A crouch foreshortens the torso by more than the scale tolerance: the\n"
     "     * scale-change reset must not cancel a held or pending crouch. */\n"
     "    int ducking=frame.actions.duck_held || duck_candidate;\n"
     "    if (!ducking && calibrated && (ab(w-base_width)>frac(base_width,c.scale_tolerance_q8) ||\n"),
    ("calibrate upright only", "pose_input.c", 1,
     "    if (!calibrated) {\n        /* Startup must be an upright",
     "    if (!calibrated) {\n"
     "        if (ducking) { stable_on=0; return; }   /* calibrate upright only */\n"
     "        /* Startup must be an upright"),
    ("retire the torso-drop crouch", "pose_input.c", 1, _RETIRED_RULE,
     "    /* Crouch is decided by subway_duck() above (shoulder line). */\n"
     "    int32_t ds=sy-base_shoulder_y;\n"),
]


_SUBMIT_OLD = (
    "    int ok=identity && (s->flags&CONTROL_POSE_VALID) &&\n"
    "        !(s->flags&~(CONTROL_POSE_VALID|CONTROL_POSE_TRACK_RESET)) &&\n"
    "        now-s->capture_ms<c.stale_ms && now-s->complete_ms<c.stale_ms &&\n"
    "        s->complete_ms-s->capture_ms<c.stale_ms &&\n"
    "        (!have_timestamp || newer(s->capture_ms,last_capture)) && body(s,&x,&sy,&hy,&w,&t,&leg);\n"
    "    if (ok && unread && !track_reset) return -2;\n"
    "    frame.actions.event_seq=0; frame.actions.move=CONTROL_MOVE_NONE;\n"
    "    for (unsigned i=0;i<2;i++) frame.hand[i].segment_valid=0;\n"
    "    if (!ok || track_reset) break_motion();\n"
    "    input_seq=s->seq; have_seq=1; track=s->track_epoch; have_track=1;\n"
    "    frame.seq=s->seq; frame.session_epoch=session; frame.track_epoch=track;\n"
    "    frame.capture_ms=s->capture_ms; frame.complete_ms=s->complete_ms;\n"
    "    frame.pose_valid=(uint32_t)ok; unread=1;\n"
    "    view_ok=(uint32_t)ok; if (ok) view=*s;\n"
    "    if (ok) {\n"
    "        last_capture=s->capture_ms; have_capture=have_timestamp=1;\n"
    "        if (game==CONTROL_GAME_SUBWAY) subway(x,sy,hy,w,t,leg,s->capture_ms);\n"
    "        else fruit(s);\n"
    "    } else have_capture=0;\n")
_SUBMIT_NEW = (
    "    int sample_ok=identity && (s->flags&CONTROL_POSE_VALID) &&\n"
    "        !(s->flags&~(CONTROL_POSE_VALID|CONTROL_POSE_TRACK_RESET)) &&\n"
    "        now-s->capture_ms<c.stale_ms && now-s->complete_ms<c.stale_ms &&\n"
    "        s->complete_ms-s->capture_ms<c.stale_ms &&\n"
    "        (!have_timestamp || newer(s->capture_ms,last_capture));\n"
    "    int ok=sample_ok && body(s,&x,&sy,&hy,&w,&t,&leg);\n"
    "    /* Board 2026-10-14: body()'s torso-relative gates tighten as a crouch\n"
    "     * foreshortens the torso, so one slightly leaning sample would end the\n"
    "     * slide. Subway holds its crouch and lane (pose_valid stays set) through\n"
    "     * up to SUBWAY_HOLD_SAMPLES consecutive body rejects of otherwise fresh,\n"
    "     * valid samples. A track reset, a stale/invalid sample or a longer run\n"
    "     * releases as before; tick() still times a held state out. */\n"
    "    int hold=!ok && sample_ok && !track_reset && game==CONTROL_GAME_SUBWAY &&\n"
    "        subway_holds<SUBWAY_HOLD_SAMPLES &&\n"
    "        (frame.actions.duck_held || duck_candidate || frame.actions.target_lane);\n"
    "    if (ok && unread && !track_reset) return -2;\n"
    "    subway_holds=hold?subway_holds+1u:0u;\n"
    "    frame.actions.event_seq=0; frame.actions.move=CONTROL_MOVE_NONE;\n"
    "    for (unsigned i=0;i<2;i++) frame.hand[i].segment_valid=0;\n"
    "    if ((!ok && !hold) || track_reset) break_motion();\n"
    "    input_seq=s->seq; have_seq=1; track=s->track_epoch; have_track=1;\n"
    "    frame.seq=s->seq; frame.session_epoch=session; frame.track_epoch=track;\n"
    "    frame.capture_ms=s->capture_ms; frame.complete_ms=s->complete_ms;\n"
    "    frame.pose_valid=(uint32_t)(ok || hold); unread=1;\n"
    "    view_ok=(uint32_t)ok; if (ok) view=*s;\n"
    "    if (ok) {\n"
    "        last_capture=s->capture_ms; have_capture=have_timestamp=1;\n"
    "        if (game==CONTROL_GAME_SUBWAY) subway(x,sy,hy,w,t,leg,s->capture_ms);\n"
    "        else fruit(s);\n"
    "    } else have_capture=(uint32_t)hold;\n")

SUBWAY_SHOULDER += [
    ("hold counter", "pose_input.c", 1,
     "static void break_motion(void) {\n"
     "    calibrated=stable_on=armed=candidate=duck_candidate=had_event=0;\n",
     "#define SUBWAY_HOLD_SAMPLES 3u   /* ~190 ms at 15.6 fps */\n"
     "static uint32_t subway_holds;\n"
     "static void break_motion(void) {\n"
     "    calibrated=stable_on=armed=candidate=duck_candidate=had_event=0;\n"
     "    subway_holds=0;\n"),
    ("hold crouch and lane through brief body rejects", "pose_input.c", 1, _SUBMIT_OLD, _SUBMIT_NEW),
]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    out = FUSION / "firmware_o2_view" / (sys.argv[1] if len(sys.argv) > 1 else "games_162_subway_shoulder_run04")
    if out.exists():
        raise SystemExit(f"{out} exists; never overwritten")
    r61 = load("pose_r61", FUSION / "tools/build_pose_r61_games.py")
    posefix = load("posefix", FUSION / "tools/build_pose_fix_games.py")
    for path in (BASE_CARD.parent / "RESULT.json", ROM.parent / "RESULT.json"):
        if json.loads(path.read_text())["CPU_Hz"] != HZ:
            raise SystemExit(f"not a {HZ} Hz build: {path}")
    # Same composition as build_pose_r62_games.py, plus SUBWAY_SHOULDER.
    posefix.HZ = HZ
    posefix.BASE_CARD = BASE_CARD
    posefix.VIEW_144_ROM = ROM
    posefix.TREE_PATCHES = {
        "FRUIT": posefix.TREE_PATCHES["FRUIT"] + r61.ALL_PATCHES,
        "SUBWAY": posefix.TREE_PATCHES["SUBWAY"] + r61.ALL_PATCHES + r61.SUBWAY_EXTRA + SUBWAY_SHOULDER + SUBWAY_TRACK,
        "POSEVIEW": posefix.TREE_PATCHES["POSEVIEW"] + r61.ALL_PATCHES[:2],
    }
    base_load = posefix.load

    def load_with_label(name, path):
        module = base_load(name, path)
        if name == "rebuild_fw_clock_posefix":
            patch_clock = module.patch_clock
            module.patch_clock = lambda o, hz, _label: patch_clock(o, hz, LABEL)
        return module

    posefix.load = load_with_label
    sys.argv = ["build_pose_fix_games.py", str(out)]
    posefix.main()
    result = json.loads((out / "RESULT.json").read_text())
    result["status"] = "R62_POSE_GAMES_SUBWAY_SHOULDER_DUCK_BUILT"
    result["builder"] = {"script": str(Path(__file__)), "reproduces": str(FUSION / "tools/build_pose_r62_games.py"),
                         "extra_subway_patches": [p[0] for p in SUBWAY_SHOULDER + SUBWAY_TRACK], "banner": LABEL,
                         "boot_ROM_compared_with": str(ROM)}
    (out / "RESULT.json").write_text(json.dumps(result, indent=2))
    print("BUILT", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
