"""Execute one evidence-producing tool with explicit exit status and hashes."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--cwd', required=True)
p.add_argument('--timeout', type=int, default=10800)
p.add_argument('command', nargs=argparse.REMAINDER)
a = p.parse_args()
cwd = Path(a.cwd)
cwd.mkdir(parents=True, exist_ok=True)
command = a.command
if command and command[0] == '--':
    command = command[1:]
if not command:
    p.error('command required')
env = os.environ.copy()
temp = cwd / 'tmp'
temp.mkdir(exist_ok=True)
env.update(TEMP=str(temp), TMP=str(temp))
record = {'command': command, 'cwd': str(cwd), 'status': 'RUNNING',
          'started': datetime.now(timezone.utc).isoformat()}
exe = Path(command[0])
if exe.is_file():
    record['executable_sha256'] = hashlib.sha256(exe.read_bytes()).hexdigest()
status = cwd / 'job.json'
status.write_text(json.dumps(record, indent=2))
try:
    with (cwd / 'tool.log').open('w') as log:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log,
                                   stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        record['pid'] = process.pid
        status.write_text(json.dumps(record, indent=2))
        try:
            rc = process.wait(timeout=a.timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            process.wait(timeout=30)
            raise
    record.update(returncode=rc, status='EXIT_0' if rc == 0 else 'FAILED')
except subprocess.TimeoutExpired:
    record.update(status='TIMEOUT')
except OSError as error:
    record.update(status='START_FAILED', error=str(error))
finally:
    record['finished'] = datetime.now(timezone.utc).isoformat()
    status.write_text(json.dumps(record, indent=2))
print(json.dumps(record))
raise SystemExit(0 if record['status'] == 'EXIT_0' else 1)
