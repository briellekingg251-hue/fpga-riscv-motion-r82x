"""End-to-end functional run in the fusion platform ISS (rv32sim).

Executes the patched 162 MHz resident loader ROM and the real SD packages: the
current R62 card (FRUIT, SUBWAY, PAL, DOOM, SLUG, POSEVIEW) plus GAMES/NES.
A touch script walks: console menu -> TOUCH -> NES -> ROM list -> MARIO ->
START / RIGHT -> hold MENU -> ROM list -> EXIT -> console menu.

The ISS models the CPU at a fixed CPI and the MMIO register maps (GPU FIFO and
rasteriser, GT911 snapshot, SPI SD).  It is a functional check, not a timing
or RTL result.

usage: python -I tools/run_iss.py [--cpi 1] [--label run01]
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nes_common as nc

FUSION = Path("E:/Codex_workplace/cpu_pose_touch_fusion_20261008")
ISS_SOURCE = FUSION / "fusion/tools/iss/rv32sim.c"
SD_VOLUME = FUSION / "games_cpu1575/tools/sd_volume.py"
R62_CARD = FUSION / "firmware_o2_view/games_162_r62_run01/sdcard"
SAVE_SOURCE = FUSION / "fusion/sdcard/GAMES"
FONT = FUSION / "fusion_cpu1575/build/font.hex"
PALETTE = FUSION / "fusion_cpu1575/build/palette.hex"

# LCD (1024x600) coordinates.  Canvas = LCD / 2.
SCRIPT = """\
1500 dump console_mode_menu
1800 tap 200 300
2400 dump console_touch_games
2500 tap 300 {nes_row_y}
7000 dump nes_rom_list
7200 tap 200 {mario_row_y}
10000 dump mario_title
10200 down 896 544
10400 up
12500 dump mario_start
13000 down 200 320
15500 dump mario_running_right
15600 up
16000 down 80 36
16300 dump menu_hold_progress
16900 up
17800 dump nes_rom_list_again
18000 tap 512 540
21000 dump console_after_exit
21500 quit
"""


def build_iss(out: Path) -> Path:
    text = ISS_SOURCE.read_text()
    replacements = [
        # GPU clock of the R62 platform is 60.75 MHz: 162 / 60.75 = 8 / 3.
        ("#define PIX_TO_CPU_NUM 162u   /* GPU runs at 51.2 MHz */",
         "#define PIX_TO_CPU_NUM 8u     /* 162 / 60.75 MHz GPU */"),
        ("#define PIX_TO_CPU_DEN 51u", "#define PIX_TO_CPU_DEN 3u"),
        # An unknown GPU command must fail the run instead of being ignored.
        ("    default: break;\n    }\n    return pix * PIX_TO_CPU_NUM / PIX_TO_CPU_DEN;",
         "    default: fatal(\"unsupported GPU command\", idx); break;\n    }\n"
         "    return pix * PIX_TO_CPU_NUM / PIX_TO_CPU_DEN;"),
        ('printf("[sim] backlight %u%%\n", v)', 'printf("[sim] backlight %u%%\\n", v)'),
        # Optional per-PC histogram over the NES image (--profile FILE): executed
        # instructions, and all cycles (MMIO latency and GPU FIFO stalls
        # included) charged to the instruction that spent them.
        ("static uint8_t *ram;",
         "static uint8_t *ram;\n#define PROF_BASE 0x80100000u\n#define PROF_WORDS 0x20000u\n"
         "static uint64_t *prof, *prof_cyc, prof_mark; static uint32_t prof_pc;\n"
         "static const char *prof_path;"),
        ("    ++instret;\n    cycles += 1 + extra_cpi;",
         "    if (prof) {\n"
         "        if (prof_pc - PROF_BASE < PROF_WORDS * 4u) prof_cyc[(prof_pc - PROF_BASE) >> 2] += cycles - prof_mark;\n"
         "        prof_pc = pc; prof_mark = cycles;\n"
         "        if (pc - PROF_BASE < PROF_WORDS * 4u) ++prof[(pc - PROF_BASE) >> 2];\n"
         "    }\n"
         "    ++instret;\n    cycles += 1 + extra_cpi;"),
        ('        else if (!strcmp(argv[i], "--save-sd")) save_sd = 1;',
         '        else if (!strcmp(argv[i], "--profile") && i + 1 < argc) { prof_path = argv[++i];'
         ' prof = calloc(PROF_WORDS, sizeof *prof); prof_cyc = calloc(PROF_WORDS, sizeof *prof_cyc); }\n'
         '        else if (!strcmp(argv[i], "--save-sd")) save_sd = 1;'),
        ('    dump_frame("final");',
         '    dump_frame("final");\n    if (prof) { FILE *pf = fopen(prof_path, "w");\n'
         '        for (uint32_t k = 0; pf && k < PROF_WORDS; ++k) if (prof[k])\n'
         '            fprintf(pf, "%08x %llu %llu\\n", PROF_BASE + 4u * k, (unsigned long long)prof[k],\n'
         '                    (unsigned long long)prof_cyc[k]);\n'
         '        if (pf) fclose(pf); }'),
    ]
    for old, new in replacements:
        if text.count(old) != 1:
            raise RuntimeError(f"ISS patch target not unique: {old[:50]}")
        text = text.replace(old, new)
    source = out / "rv32sim_nes.c"
    source.write_text(text)
    exe = out / "rv32sim.exe"
    nc.run([nc.HOST_GCC, "-O3", "-std=c11", "-Wall", "-Wextra", "-static", "-o", exe, source],
           out / "iss_build.log", nc.host_env())
    return exe


def build_card(out: Path) -> tuple[Path, list[str]]:
    tree = out / "sdcard"
    if tree.exists():
        shutil.rmtree(tree)
    shutil.copytree(R62_CARD, tree)
    for game in ("FRUIT", "SUBWAY"):
        shutil.copyfile(SAVE_SOURCE / game / "SAVE.DAT", tree / "GAMES" / game / "SAVE.DAT")
    shutil.copytree(nc.ROOT / "build/sdcard/GAMES/NES", tree / "GAMES/NES")
    spec = importlib.util.spec_from_file_location("sd_volume", SD_VOLUME)
    volume = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(volume)
    # The split TOUCH/POSE programs of FRUIT/SUBWAY are accepted as in the
    # fusion game-program runner.
    volume.ABI12_FILES |= {"TOUCH.BIN", "TOUCH.MAN", "POSE.BIN", "POSE.MAN"}
    image = out / "card.img"
    volume.write_image(tree, image)
    catalog = sorted(p.name for p in (tree / "GAMES").iterdir() if p.is_dir())
    return image, catalog


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cpi", type=int, default=1)
    parser.add_argument("--label", default="run01")
    parser.add_argument("--profile", action="store_true", help="write a per-PC instruction histogram")
    args = parser.parse_args()
    out = nc.ROOT / "build/iss" / args.label
    if out.exists():
        shutil.rmtree(out)
    (out / "frames").mkdir(parents=True)
    exe = build_iss(out)
    image, catalog = build_card(out)
    touch_games = [g for g in catalog if g != "POSEVIEW"]
    index = touch_games.index("NES")
    if index >= 4:
        raise RuntimeError("NES is not on the first catalog page; extend the script")
    roms = sorted(p.name for p in (nc.ROOT / "build/sdcard/GAMES/NES").glob("*.NES"))
    row = roms.index("MARIO.NES")
    if row >= 6:
        raise RuntimeError("MARIO.NES is not on the first ROM page")
    script = SCRIPT.format(nes_row_y=160 + 80 * index, mario_row_y=2 * (52 + 30 * row + 15))
    (out / "touch.txt").write_text(script, encoding="ascii")
    rom = nc.ROOT / "build/boot/nes/program.hex"
    argv = [exe, "--hex", rom, "--sd", image, "--font", FONT, "--script", out / "touch.txt",
            "--frames", out / "frames", "--max-ms", "30000"]
    if PALETTE.exists():
        argv += ["--palette", PALETTE]
    if args.cpi > 1:
        argv += ["--cpi", args.cpi]
    if args.profile:
        argv += ["--profile", out / "profile.txt"]
    log = out / "uart.log"
    try:
        nc.run(argv, log, nc.host_env(), cwd=out)
        exit_ok = True
    except RuntimeError:
        exit_ok = False
    text = log.read_text(errors="replace")
    stats = re.findall(r"NES_STAT .*|NES_QUIT .*", text)
    checks = {
        "iss_exit_ok": exit_ok,
        "no_fatal": "rv32sim FATAL" not in text and "NES FATAL" not in text,
        "nes_started": "NES (InfoNES 0.97J) on O2" in text,
        "catalog_7": "NES catalog 7 file(s)" in text,
        "mario_played": "NES_PLAY MARIO.NES mapper 0" in text,
        "menu_quit": "NES_QUIT" in text,
        "exit_to_loader": "NES_EXIT to loader" in text,
        "no_misaligned": bool(re.search(r"NES_QUIT .* misaligned=0\b", text)),
    }
    try:
        from PIL import Image
        for ppm in sorted((out / "frames").glob("*.ppm")):
            Image.open(ppm).save(ppm.with_suffix(".png"))
            ppm.unlink()
    except ImportError:
        pass
    result = {"status": "ISS_NES_PASS" if all(checks.values()) else "ISS_NES_FAIL", "cpi": args.cpi,
              "checks": checks, "stats": stats, "catalog": catalog,
              "inputs": {"rom_hex": nc.sha256(rom), "card_img": nc.sha256(image),
                         "iss_source": nc.sha256(ISS_SOURCE), "game_bin":
                         nc.sha256(nc.ROOT / "build/sdcard/GAMES/NES/GAME.BIN")},
              "scope": "functional ISS; not RTL timing, not board"}
    (out / "RESULT.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("status", "checks", "stats")}, indent=1))
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
