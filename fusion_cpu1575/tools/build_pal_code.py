"""Build unchanged open PAL engine/port, without copying commercial data.

Writes only this project. No disk/board access. Resource names and save sizes
are delivered separately; the private licensed resources remain user's input.
"""
from pathlib import Path
import json
import struct
import zlib
import build_pal_game as pal

def main():
    pal.OUT.mkdir(parents=True,exist_ok=True)
    game,sizes=pal.build_engine()
    directory=pal.ROOT/'sdcard/GAMES/PAL'
    directory.mkdir(parents=True,exist_ok=True)
    header=struct.pack('<7I',0x53444731,3,len(game),zlib.crc32(game),
                       pal.LOAD_ADDRESS,pal.LOAD_ADDRESS,pal.GAME_ID)
    (directory/'GAME.BIN').write_bytes(game)
    (directory/'MANIFEST.BIN').write_bytes(header+struct.pack('<I',zlib.crc32(header)))
    for slot in range(1,pal.SAVE_SLOTS+1):
        for side in 'AB':
            save=directory/f'SAVE{slot}{side}.DAT'
            if not save.exists():save.write_bytes(bytes(pal.SAVE_FILE_BYTES))
            elif save.stat().st_size!=pal.SAVE_FILE_BYTES:
                raise SystemExit(f'{save.name}: wrong size; retained unchanged')
    result={'status':'CODE_LINK_PASS','resource_abi':3,'modes':['TOUCH'],
            'load':hex(pal.LOAD_ADDRESS),'elf':sizes,'commercial_resources_copied':False,
            'required_private_resources':pal.DATA_FILES,'full_game_execution_verified':False}
    (pal.OUT/'status.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
