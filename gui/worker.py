import os, sys, time, threading, signal, fcntl, runpy
from pathlib import Path

control = Path(sys.argv[1])
parent = int(sys.argv[2])
mode = sys.argv[3]
value = sys.argv[4]

lock = os.open('/var/run/local.simplevpn.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    print('另一个 VPN 连接正在运行，请先断开。', flush=True)
    sys.exit(1)

def watch():
    while True:
        time.sleep(.5)
        stop = (control / 'stop').exists()
        try:
            os.kill(parent, 0)
        except ProcessLookupError:
            stop = True
        if stop:
            os.kill(os.getpid(), signal.SIGTERM)
            return

threading.Thread(target=watch, daemon=True).start()

args = ['mac_vpn.py', mode, value, '--control-dir', str(control)]
config_file = control / 'config.json'
if config_file.exists():
    args += ['--config', str(config_file)]

sys.argv = args
try:
    runpy.run_path(str(Path(__file__).with_name('mac_vpn.py')), run_name='__main__')
finally:
    try:
        (control / 'link').unlink(missing_ok=True)
    except OSError:
        pass
