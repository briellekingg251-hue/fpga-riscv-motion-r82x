"""SUBWAY_TRACK: keep the single-player track through a crouch (Subway only).

Board 2026-10-14 (build/board/uart_duck_1.log): every unexpected stand-up and
most crashes coincided with confirm_track() in game_pose_service.c dropping
the track (rej 16 CONTINUITY, 8 GEOMETRY). break_track() calls control_reset(),
which clears the crouch and the lane before pose_input can hold them.

A crouch shortens the torso by 30-40 % within one or two 64 ms samples, and the
torso midpoint falls below the detector box and ROI, which lag one frame. For
SUBWAY only (game_id), confirm_track():
  * geometry: tilt and shoulder/hip offset limits t/3 -> t/2; t/2 of downward
    slack below the ROI and the detector box;
  * continuity: torso, width and ROI size may halve or double against the
    last accepted sample (was +-1/4; a crouch is -40 %, standing up +67 %); the position
    and motion limits that catch a different person are unchanged; a count or
    frame gap may include the samples skipped by soft rejects;
  * a geometry/continuity failure on a confirmed track is a soft reject: the
    sample is dropped without break_track() and without updating the
    reference, up to TRACK_SOFT_MAX (3) in a row; the next one breaks exactly
    as before. AGE/BODY/DETECTOR/SOURCE breaks are unchanged, and the 300 ms
    age check in game_pose_step() still bounds a run of soft rejects;
  * POSEDBG adds the shoulder line (last/min/max since the previous line),
    soft rejects and breaks per cause.
Format: (name, file, expected anchor count, anchor, replacement), as posefix.
"""

SUBWAY_TRACK = [
    ("track soft-reject state", "game_pose_service.c", 1,
     "    uint32_t det_breaks,pose_faults,pending_checked,pending_identity,rejections,last_reject;\n",
     "    uint32_t det_breaks,pose_faults,pending_checked,pending_identity,rejections,last_reject;\n"
     "    uint32_t soft;   /* consecutive soft rejects (Subway) */\n"),
    ("soft reject helper and counters", "game_pose_service.c", 1,
     "static void break_track(uint32_t floor,uint32_t reason) {\n"
     "    if(forward_ms(floor,capture_floor))capture_floor=floor;\n"
     "    trajectory.confirmed=0;\n",
     "#define TRACK_SOFT_MAX 3u\n"
     "#define TRACK_SOFT 2   /* confirm_track(): drop this sample, keep the track */\n"
     "static uint32_t dbg_soft,dbg_breaks[7];\n"
     "static int32_t dbg_sy=-1,dbg_sy_min=0x7fff,dbg_sy_max=-1;\n"
     "/* Geometry failure bits since the last POSEDBG line, and the torso length\n"
     " * and shoulder/hip offset of the last failing sample. */\n"
     "static uint32_t dbg_geo,dbg_hipfill;static int32_t dbg_geo_t,dbg_geo_lean;\n"
     "static void break_track(uint32_t floor,uint32_t reason) {\n"
     "    if(forward_ms(floor,capture_floor))capture_floor=floor;\n"
     "    for(unsigned i=0;i<7u;i++)if(reason&(1u<<i))++dbg_breaks[i];\n"
     "    trajectory.soft=0;\n"
     "    trajectory.confirmed=0;\n"),
    ("soft reject decision", "game_pose_service.c", 1,
     "static uint32_t pose_faults(void) {\n",
     "/* Subway: a crouch can fail one or two geometry/continuity samples of the\n"
     " * same player; skip up to TRACK_SOFT_MAX in a row instead of resetting the\n"
     " * crouch and lane. The reference stays at the last accepted sample. */\n"
     "/* Size continuity. Subway: a crouch shrinks and standing up grows the torso\n"
     " * by up to a factor of two against the last accepted sample; every other\n"
     " * game keeps the original +-1/4. */\n"
     "static int size_jump(int32_t v,int32_t ref,int crouchy,int32_t slack) {\n"
     "    if(crouchy)return v*2<ref-slack || v>ref*2+slack;\n"
     "    return distance32(v-ref)>ref/4+slack;\n"
     "}\n"
     "static int soft_reject(uint32_t reason) {\n"
     "    if(game_id!=CONTROL_GAME_SUBWAY || !trajectory.confirmed || trajectory.soft>=TRACK_SOFT_MAX)return 0;\n"
     "    ++trajectory.soft;++dbg_soft;trajectory.last_reject=reason;\n"
     "    return 1;\n"
     "}\n"
     "static uint32_t pose_faults(void) {\n"),
    ("crouch-tolerant geometry", "game_pose_service.c", 1,
     "    if(w<32 || t<45 || hw<w/3 || hw>w*2 || distance32(sx-hx)>t/3 ||\n"
     "       distance32(p[0].y-p[1].y)>t/3 || distance32(p[6].y-p[7].y)>t/3 ||\n"
     "       x<rx || x>rx+rw || y<ry || y>ry+rh ||\n"
     "       x<b->x0/256-margin || x>b->x1/256+margin ||\n"
     "       y<b->y0/256-margin || y>b->y1/256+margin) {\n"
     "        break_track(s->capture_ms,TRACK_REJECT_GEOMETRY);return 0;\n"
     "    }\n",
     "    dbg_sy=sy;if(sy<dbg_sy_min)dbg_sy_min=sy;if(sy>dbg_sy_max)dbg_sy_max=sy;\n"
     "    /* Subway (board 2026-10-14): a crouch foreshortens the torso by 30-40 %\n"
     "     * and drops its midpoint below the one-frame-old detector box and ROI. */\n"
     "    int crouchy=game_id==CONTROL_GAME_SUBWAY;\n"
     "    int32_t tol=crouchy?t/2:t/3,down=crouchy?t/2:0;\n"
     "    /* Board 2026-10-14: in a side lane the player is off the camera axis, so a\n"
     "     * forward lean in a crouch shifts the shoulders sideways against the hips\n"
     "     * in the image. Subway allows a shoulder/hip offset up to the torso length. */\n"
     "    int32_t lean=crouchy?t:t/3;\n"
     "    /* A fast side step between lanes outruns the one-frame-old ROI and box.\n"
     "     * On a confirmed Subway track, allow the torso outside them sideways by the\n"
     "     * distance the continuity check accepts as one sample's movement; a\n"
     "     * larger jump (another person) still breaks there, as 'jumped'. */\n"
     "    int32_t xs=0;\n"
     "    if(crouchy && trajectory.confirmed) {\n"
     "        uint32_t gap=s->capture_ms-trajectory.last_capture;\n"
     "        xs=trajectory.width*3/4+32+(int32_t)(gap<300u?gap:300u)*2;\n"
     "    }\n"
     "    uint32_t g=(uint32_t)(w<32)|(uint32_t)(t<45)<<1|(uint32_t)(hw<w/3)<<2|(uint32_t)(hw>w*2)<<3|\n"
     "        (uint32_t)(distance32(sx-hx)>lean)<<4|(uint32_t)(distance32(p[0].y-p[1].y)>tol)<<5|\n"
     "        (uint32_t)(distance32(p[6].y-p[7].y)>tol)<<6|(uint32_t)(x<rx-xs || x>rx+rw+xs)<<7|\n"
     "        (uint32_t)(x<b->x0/256-margin-xs || x>b->x1/256+margin+xs)<<8|(uint32_t)(y<ry)<<9|\n"
     "        (uint32_t)(y>ry+rh+down)<<10|(uint32_t)(y<b->y0/256-margin)<<11|\n"
     "        (uint32_t)(y>b->y1/256+margin+down)<<12;\n"
     "    /* Leaving the ROI/box sideways is movement or another person: never soft. */\n"
     "    int xout=(g>>7)&3u;\n"
     "    if(g) {\n"
     "        dbg_geo|=g;dbg_geo_t=t;dbg_geo_lean=distance32(sx-hx);\n"
     "        if(!xout && soft_reject(TRACK_REJECT_GEOMETRY))return TRACK_SOFT;\n"
     "        break_track(s->capture_ms,TRACK_REJECT_GEOMETRY);return 0;\n"
     "    }\n"),
    ("crouch-tolerant continuity", "game_pose_service.c", 1,
     "        if(count-trajectory.last_count-1u>1u || fgap-1u>2u ||\n"
     "           !forward_ms(s->capture_ms,trajectory.last_capture) || dt>=300u ||\n"
     "           distance32(x-trajectory.x)>move || distance32(y-trajectory.y)>move ||\n"
     "           distance32(w-trajectory.width)>trajectory.width/4 ||\n"
     "           distance32(t-trajectory.torso)>trajectory.torso/4 ||\n"
     "           distance32(rw-oldw)>oldw/4+4 || distance32(cx-oldcx)>oldw/2+32+(int32_t)dt*2 ||\n"
     "           distance32(cy-oldcy)>oldh/2+32+(int32_t)dt*2) {\n",
     "        /* A position jump means another person (or a lost track): never soft. */\n"
     "        int jumped=distance32(x-trajectory.x)>move || distance32(y-trajectory.y)>move ||\n"
     "           distance32(cx-oldcx)>oldw/2+32+(int32_t)dt*2 ||\n"
     "           distance32(cy-oldcy)>oldh/2+32+(int32_t)dt*2;\n"
     "        if(count-trajectory.last_count-1u>1u+trajectory.soft || fgap-1u>2u+trajectory.soft ||\n"
     "           !forward_ms(s->capture_ms,trajectory.last_capture) || dt>=300u || jumped ||\n"
     "           size_jump(w,trajectory.width,crouchy,0) ||\n"
     "           size_jump(t,trajectory.torso,crouchy,0) ||\n"
     "           size_jump(rw,oldw,crouchy,4)) {\n"
     "            if(!jumped && soft_reject(TRACK_REJECT_CONTINUITY))return TRACK_SOFT;\n"),
    ("accepted sample clears the soft run", "game_pose_service.c", 1,
     "    trajectory.have_seq=1;trajectory.last_seq=s->seq;trajectory.last_frame=s->capture_frame_id;\n",
     "    trajectory.soft=0;\n"
     "    trajectory.have_seq=1;trajectory.last_seq=s->seq;trajectory.last_frame=s->capture_frame_id;\n"),
    ("soft-rejected sample is dropped", "game_pose_service.c", 1,
     "        /* -2 preserves this exact seq until the game's only poll drains it. */\n"
     "        int rc=pose_input_submit(&pending,now,trajectory.pending_identity);\n",
     "        if(trajectory.pending_identity==(uint32_t)TRACK_SOFT) {\n"
     "            /* Soft reject: neither published nor reset; pose_input keeps the\n"
     "             * crouch and lane until a good sample or its 300 ms staleness. */\n"
     "            have_pending=0;trajectory.pending_checked=0;return;\n"
     "        }\n"
     "        /* -2 preserves this exact seq until the game's only poll drains it. */\n"
     "        int rc=pose_input_submit(&pending,now,trajectory.pending_identity);\n"),
    ("POSEDBG shoulder line and break causes", "game_pose_service.c", 1,
     "    dbg_kv(\" rej=\",trajectory.last_reject);dbg_kv(\" rejN=\",trajectory.rejections);\n",
     "    dbg_kv(\" rej=\",trajectory.last_reject);dbg_kv(\" rejN=\",trajectory.rejections);\n"
     "    dbg_kv(\" sy=\",(uint32_t)(dbg_sy<0?0:dbg_sy));\n"
     "    dbg_kv(\" syr=\",(uint32_t)(dbg_sy_max<0?0:dbg_sy_min));dbg_kv(\"-\",(uint32_t)(dbg_sy_max<0?0:dbg_sy_max));\n"
     "    dbg_sy_min=0x7fff;dbg_sy_max=-1;\n"
     "    dbg_kv(\" soft=\",dbg_soft);\n"
     "    dbg_kv(\" geo=\",dbg_geo);dbg_kv(\" gt=\",(uint32_t)dbg_geo_t);dbg_kv(\" gl=\",(uint32_t)dbg_geo_lean);\n"
     "    dbg_geo=0;dbg_kv(\" hf=\",dbg_hipfill);\n"
     "    dbg_kv(\" bA=\",dbg_breaks[0]);dbg_kv(\" bB=\",dbg_breaks[1]);dbg_kv(\" bG=\",dbg_breaks[3]);\n"
     "    dbg_kv(\" bC=\",dbg_breaks[4]);dbg_kv(\" bD=\",dbg_breaks[5]);dbg_kv(\" bS=\",dbg_breaks[6]);\n"),
    ("crouch hips: fill one, soft-skip both", "game_pose_service.c", 1,
     "    if(!joint_ok(s,0) || !joint_ok(s,1) || !joint_ok(s,6) || !joint_ok(s,7)) {\n"
     "        break_track(s->capture_ms,TRACK_REJECT_BODY);return 0;\n"
     "    }\n",
     "    /* Board 2026-10-14: in a crouch the knees often hide one hip. With both\n"
     "     * shoulders and the other hip found, mirror that hip across the shoulder\n"
     "     * midline (also for pose_input, which reads this snapshot). */\n"
     "    if(game_id==CONTROL_GAME_SUBWAY && joint_ok(s,0) && joint_ok(s,1) &&\n"
     "       joint_ok(s,6)!=joint_ok(s,7)) {\n"
     "        unsigned have=joint_ok(s,6)?6u:7u;\n"
     "        const control_joint_t *h=&s->joint[have];control_joint_t *q=&s->joint[have^1u];\n"
     "        int32_t mx=2*((s->joint[0].x+s->joint[1].x)/2)-h->x;\n"
     "        q->x=(int16_t)(mx<0?0:mx>1279?1279:mx);q->y=h->y;q->logit=h->logit;q->valid=1;\n"
     "        ++dbg_hipfill;\n"
     "    }\n"
     "    if(!joint_ok(s,0) || !joint_ok(s,1) || !joint_ok(s,6) || !joint_ok(s,7)) {\n"
     "        /* Both hips hidden but shoulders found: same player, skip the sample. */\n"
     "        if(joint_ok(s,0) && joint_ok(s,1) && soft_reject(TRACK_REJECT_BODY))return TRACK_SOFT;\n"
     "        break_track(s->capture_ms,TRACK_REJECT_BODY);return 0;\n"
     "    }\n"),
    ("faster lane zones", "pose_input.c", 1,
     ".lane_zones=POSE_SUBWAY_ZONES, .zone_hyst_q8=10, .zone_dwell_ms=120 };",
     ".lane_zones=POSE_SUBWAY_ZONES, .zone_hyst_q8=6, .zone_dwell_ms=60 };"),
    ("side-lane lean in pose_input body()", "pose_input.c", 1,
     "    if (*w<c.min_width_px || *t<c.min_torso_px || hw<*w/3 || hw>*w*2 ||\n"
     "        ab(sx-hx)>*t/3 || ab(p[0].y-p[1].y)>*t/3 ||\n"
     "        ab(p[6].y-p[7].y)>*t/3) return 0;\n",
     "    /* Subway: same crouch tolerances as confirm_track() (side-lane lean up to\n"
     "     * the torso length, tilt up to half of it); other games unchanged. */\n"
     "    int32_t lean=game==CONTROL_GAME_SUBWAY?*t:*t/3, tilt=game==CONTROL_GAME_SUBWAY?*t/2:*t/3;\n"
     "    if (*w<c.min_width_px || *t<c.min_torso_px || hw<*w/3 || hw>*w*2 ||\n"
     "        ab(sx-hx)>lean || ab(p[0].y-p[1].y)>tilt ||\n"
     "        ab(p[6].y-p[7].y)>tilt) return 0;\n"),
]
