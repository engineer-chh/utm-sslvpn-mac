"""Request graceful shutdown of this application's identified workers only."""
import os, sys, subprocess, shlex, signal, time, fcntl
from pathlib import Path

def workers():
    data = subprocess.check_output(['/bin/ps', '-axo', 'pid=,args='], text=True)
    found = []
    for row in data.splitlines():
        bits = row.strip().split(None, 1)
        if len(bits) != 2: continue
        try:
            pid = int(bits[0]); args = shlex.split(bits[1])
        except (ValueError, TypeError): continue
        for i, arg in enumerate(args):
            if Path(arg).name != 'worker.py' or len(args) <= i + 2: continue
            control = Path(args[i+1])
            if not control.is_absolute() or not control.name.startswith('simplevpn-'): continue
            if not str(control).startswith(('/var/folders/', '/private/var/folders/')): continue
            if not args[i+2].isdigit(): continue
            if not any('python' in Path(x).name.lower() for x in args[:i]): continue
            found.append((pid, control)); break
    return found

for pid, control in workers():
    try:
        (control / 'stop').touch(exist_ok=True)
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError: pass
    except PermissionError:
        print('无法请求旧连接退出。', file=sys.stderr)
        sys.exit(1)

for _ in range(24):
    time.sleep(.5)
    fd = os.open('/var/run/local.simplevpn.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        print('旧连接已退出，可以重新连接。')
        sys.exit(0)
    except BlockingIOError: pass
    finally: os.close(fd)

print('旧连接仍未退出。没有强制删除锁或终止进程，请稍后重试。')
sys.exit(1)
