"""Validate local original PAL resource containers without obtaining game data."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
ROOT=Path(__file__).resolve().parents[1]
REQUIRED_MKF=('abc.mkf','ball.mkf','data.mkf','f.mkf','fbp.mkf','fire.mkf','gop.mkf','map.mkf','mgo.mkf','pat.mkf','rgm.mkf','rng.mkf','sss.mkf')
REQUIRED_TEXT=('word.dat','m.msg')
def check(folder):
    files={p.name.lower():p for p in folder.iterdir() if p.is_file()}
    report={'status':'RESOURCE_FILES_PRESENT','files':{},'missing':[],'invalid':[],'runtime_acceptance':'NOT_RUN'}
    for name in REQUIRED_MKF+REQUIRED_TEXT:
        if name not in files:report['missing'].append(name);continue
        p=files[name];size=p.stat().st_size
        valid=size>0
        if name.endswith('.mkf'):
            with p.open('rb') as f:
                first=f.read(4)
                table_size=struct.unpack('<I',first)[0] if len(first)==4 else 0
                if table_size<8 or table_size%4 or table_size>size or table_size>4*1024*1024:valid=False
                else:
                    f.seek(0);offsets=struct.unpack('<'+str(table_size//4)+'I',f.read(table_size))
                    valid=offsets[0]==table_size and all(a<=b<=size for a,b in zip(offsets,offsets[1:]))
        digest=hashlib.sha256()
        with p.open('rb') as f:
            for block in iter(lambda:f.read(1024*1024),b''):digest.update(block)
        report['files'][name]={'bytes':size,'sha256':digest.hexdigest(),'container_valid':valid}
        if not valid:report['invalid'].append(name)
    if report['missing'] or report['invalid']:report['status']='RESOURCE_CHECK_FAILED'
    # Presence/offset checks do not certify the version, fonts, or compatibility.
    return report
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('folder',type=Path)
    args=parser.parse_args();report=check(args.folder)
    target=ROOT/'build/pal_resources.json';target.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2));raise SystemExit(report['status']!='RESOURCE_FILES_PRESENT')
if __name__=='__main__':main()
