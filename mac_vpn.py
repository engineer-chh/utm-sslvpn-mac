#!/usr/bin/env python3
"""Experimental IPv4 UTM SSLVPN client for macOS. Foreground, server routes only."""
import argparse, ctypes, fcntl, html, ipaddress, json, os, re, select, signal
import socket, ssl, struct, subprocess, sys, time
from pathlib import Path
from protocol import parse_link, auth_frame, read_frame, encode_frame, config_summary

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent / 'config.json'

def load_config(config_path):
    if not config_path:
        return {}
    p = Path(config_path).expanduser()
    if p.is_file():
        try:
            with open(p, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f'警告：读取配置文件 {p} 失败：{e}', file=sys.stderr)
    return {}

def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout

def read_saved_link(path, expected_server=None, expected_port=None):
    path = Path(path).expanduser()
    candidates = [path] if path.is_file() else []
    folder = path.parent / (path.stem + '_files')
    if folder.is_dir(): candidates += list(folder.glob('*.html'))
    for candidate in candidates:
        if candidate.stat().st_size > 2_000_000: continue
        text = candidate.read_bytes().decode('gb18030', errors='replace')
        match = re.search(r'href=[\"\x27](utmssl://[^\"\x27]+)', text, re.I)
        if match:
            host, port, token = parse_link(html.unescape(match.group(1)))
            if expected_server and host != expected_server:
                raise ValueError(f'保存页面中的服务器 ({host}) 与配置的目标服务器 ({expected_server}) 不一致')
            if expected_port and port != int(expected_port):
                raise ValueError(f'保存页面中的端口 ({port}) 与配置的目标端口 ({expected_port}) 不一致')
            return host, port, token
    raise ValueError('未找到连接链接。请重新登录并保存完整网页及其资源文件夹')

def parse_config(data):
    summary = config_summary(data)
    fields = [str(ipaddress.IPv4Address(data[i:i+4])) for i in range(0,20,4)]
    address, mask, peer, dns, wins = fields
    ipaddress.IPv4Network('0.0.0.0/'+mask)
    if address == '0.0.0.0' or peer == '0.0.0.0': raise ValueError('无效的网卡配置')
    routes = []
    for i in range(summary['route_count']):
        at = 24+i*8
        net = str(ipaddress.IPv4Address(data[at:at+4]))
        mask = str(ipaddress.IPv4Address(data[at+4:at+8]))
        route = ipaddress.IPv4Network(net+'/'+mask, strict=False)
        allowed = any(route.subnet_of(n) for n in (
            ipaddress.IPv4Network('10.0.0.0/8'), ipaddress.IPv4Network('172.16.0.0/12'),
            ipaddress.IPv4Network('192.168.0.0/16')))
        if not allowed: raise ValueError('服务端包含非私网路由；当前版本不自动接管该流量')
        if route not in routes: routes.append(route)
    return address, peer, dns, routes

def open_utun():
    tun = socket.socket(32, socket.SOCK_DGRAM, 2)
    try:
        info = bytearray(struct.pack('=I96s', 0, b'com.apple.net.utun_control'))
        fcntl.ioctl(tun.fileno(), 0xc0644e03, info, True)
        control_id = struct.unpack_from('=I', info)[0]
        addr = ctypes.create_string_buffer(struct.pack('=BBHII5I',32,32,2,control_id,0,0,0,0,0,0))
        libc = ctypes.CDLL(None, use_errno=True)
        libc.connect.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        libc.connect.restype = ctypes.c_int
        if libc.connect(tun.fileno(), addr, 32):
            raise OSError(ctypes.get_errno(), '无法创建 utun 网卡')
        name = tun.getsockopt(2,2,64).split(b'\0',1)[0].decode('ascii')
        if not re.fullmatch(r'utun\d+',name):raise ValueError('网卡名称无效')
        return tun, name
    except BaseException:
        tun.close();raise

def check_ipv4(data):
    if len(data)<20 or data[0]>>4!=4:return False
    header=(data[0]&15)*4
    return header>=20 and header<=len(data) and struct.unpack_from('!H',data,2)[0]==len(data)

def tun_packet(data):
    if not check_ipv4(data):
        return None
    return struct.pack('!I', socket.AF_INET) + data

def main():
    ap = argparse.ArgumentParser(description='macOS UTM SSLVPN 客户端；Ctrl+C 断开并清理')
    ap.add_argument('--config', default=str(DEFAULT_CONFIG_PATH) if DEFAULT_CONFIG_PATH.is_file() else None,
                    help='配置文件路径 (JSON)')
    ap.add_argument('--page', default=None,
                    help='保存的 VPN 登录网页路径 (默认为 ~/Desktop/SSLVPN 客户端.html 或配置文件指定值)')
    ap.add_argument('--link', default=None,
                    help='直接提供 utmssl://... 连接链接')
    ap.add_argument('--link-file', default=None,
                    help='临时链接文件路径 (供 GUI 调用)')
    ap.add_argument('--control-dir', default=None,
                    help='控制目录路径 (供 GUI 调用检测停止信号)')
    ap.add_argument('--server', default=None,
                    help='指定/校验 VPN 服务器地址')
    ap.add_argument('--port', type=int, default=None,
                    help='指定/校验 VPN 隧道端口')
    ap.add_argument('--target-url', default=None,
                    help='连接成功后提示打开的内网业务系统 URL')
    ap.add_argument('--probe', action='store_true',
                    help='仅握手与认证探测，不创建 utun 网卡和路由')
    args = ap.parse_args()

    if sys.platform != 'darwin': raise ValueError('仅支持 macOS')

    cfg = load_config(args.config)
    expected_server = args.server or cfg.get('server')
    expected_port = args.port or cfg.get('port')
    target_url = args.target_url or cfg.get('target_url')
    page_path = args.page or cfg.get('default_page') or str(Path.home() / 'Desktop/SSLVPN 客户端.html')

    if not args.probe and os.geteuid() != 0:
        print('连接模式需要管理员权限创建 utun 网卡。请使用 sudo 或随附的启动脚本。')
        return 2

    if args.link_file:
        raw_link = Path(args.link_file).read_text().strip()
        host, port, token = parse_link(raw_link)
        if expected_server and host != expected_server:
            raise ValueError(f'指定链接中的服务器 ({host}) 与配置的目标服务器 ({expected_server}) 不一致')
        if expected_port and port != int(expected_port):
            raise ValueError(f'指定链接中的端口 ({port}) 与配置的目标端口 ({expected_port}) 不一致')
    elif args.link:
        host, port, token = parse_link(args.link)
        if expected_server and host != expected_server:
            raise ValueError(f'指定链接中的服务器 ({host}) 与配置的目标服务器 ({expected_server}) 不一致')
        if expected_port and port != int(expected_port):
            raise ValueError(f'指定链接中的端口 ({port}) 与配置的目标端口 ({expected_port}) 不一致')
    else:
        host, port, token = read_saved_link(page_path, expected_server, expected_port)

    added = []; tun = None; name = None; conn = None
    def stop(*_): raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        context = ssl.create_default_context()
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        raw = socket.create_connection((host, port), timeout=10)
        try: conn = context.wrap_socket(raw, server_hostname=host)
        except BaseException: raw.close(); raise
        conn.sendall(auth_frame(token)); del token
        kind, data = read_frame(conn)
        if kind != 0x201: raise ValueError('未收到配置；请重新登录获取最新会话值')
        address, peer, dns, routes = parse_config(data)
        print(f'TLS 证书验证和 VPN 认证成功；收到 {len(routes)} 条私网路由。', flush=True)
        if args.probe: return 0
        if dns != '0.0.0.0': print('服务器下发了 DNS；此版本仅配置 IP 路由，域名访问尚未实现。', flush=True)
        tun, name = open_utun()
        run('/sbin/ifconfig', name, 'inet', address, peer, 'netmask', '255.255.255.255', 'mtu', '1400', 'up')
        for route in routes:
            run('/sbin/route', '-n', 'add', '-net', str(route), '-interface', name)
            added.append(str(route))
        print('隧道已启动。保持此窗口打开；按 Ctrl+C 断开。', flush=True)
        if target_url:
            print(f'在浏览器打开业务系统：{target_url}', flush=True)
        else:
            print('内网路由已就绪，可直接访问受内网保护的业务系统。', flush=True)

        tx = rx = 0; last = time.monotonic()
        while True:
            if args.control_dir and (Path(args.control_dir) / 'stop').exists():
                break
            ready, _, _ = select.select([tun, conn], [], [], 1)
            if conn in ready or conn.pending():
                kind, packet = read_frame(conn)
                if kind == 0:
                    output = tun_packet(packet)
                    if output is not None:
                        written = tun.send(output)
                        if written != len(output): raise OSError('虚拟网卡写入不完整')
                        rx += 1
                elif kind == 0x201:
                    if packet != data: raise ValueError('服务器变更配置，请重新连接')
                elif kind != 1: raise ValueError('收到尚未支持的控制报文')
            if tun in ready:
                packet = tun.recv(65540)
                if len(packet) >= 4 and struct.unpack('!I', packet[:4])[0] == socket.AF_INET:
                    packet = packet[4:]
                    if check_ipv4(packet): conn.sendall(encode_frame(0, packet)); tx += 1
            if time.monotonic() - last >= 30:
                print('隧道数据包：发送 %d，接收 %d' % (tx, rx), flush=True); last = time.monotonic()
    finally:
        cleanup_failed = False
        for route in reversed(added):
            try: run('/sbin/route', '-n', 'delete', '-net', route, '-interface', name)
            except (OSError, subprocess.CalledProcessError): cleanup_failed = True
        if tun: tun.close()
        if conn: conn.close()
        if added: print('连接已关闭，已尝试清理本次添加的路由。', flush=True)
        if cleanup_failed: print('部分路由清理命令失败；utun 已关闭，请检查网络状态。', flush=True)
    return 0

if __name__ == '__main__':
    try: raise SystemExit(main())
    except KeyboardInterrupt: print('\n已停止。')
    except ssl.SSLCertVerificationError: print('证书验证失败；没有关闭校验。'); sys.exit(1)
    except ssl.SSLError: print('TLS 连接失败。'); sys.exit(1)
    except (ValueError, OSError, EOFError, subprocess.CalledProcessError) as e:
        if isinstance(e, ValueError): print(str(e))
        else: print('连接或网络配置失败（%s）。已执行清理；可先运行 --probe 检查会话是否过期。' % type(e).__name__)
        sys.exit(1)
