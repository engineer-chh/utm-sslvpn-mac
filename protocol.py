"""UTM3.0 framing inferred from the supplied vnl.exe; not yet server-verified."""
import struct
from urllib.parse import urlsplit

MAX_PAYLOAD = 4096

def parse_link(link):
    u = urlsplit(link.strip())
    if u.scheme != 'utmssl' or u.path != '/conn' or not u.hostname:
        raise ValueError('需要 utmssl://服务器:端口/conn?会话值 格式的连接链接')
    if u.username or u.password or u.fragment:
        raise ValueError('连接链接包含不支持的字段')
    token = u.query.split('&', 1)[0].encode('ascii')
    if not 1 <= len(token) <= 32 or any(x < 33 or x > 126 for x in token):
        raise ValueError('会话值应为 1–32 个 ASCII 字符')
    if not u.port:
        raise ValueError('必须提供网页指定的隧道端口，不能假定与 HTTPS 端口相同')
    return u.hostname, u.port, token

def encode_frame(kind, payload):
    if not 0 <= kind <= 65535 or len(payload) > MAX_PAYLOAD:
        raise ValueError('报文类型或长度超出范围')
    return struct.pack('!HH', kind, len(payload)) + payload

def auth_frame(token):
    if not 1 <= len(token) <= 32:
        raise ValueError('会话值长度无效')
    return encode_frame(0x0101, token.ljust(32, b'\0'))

def read_exact(stream, size):
    data = bytearray()
    while len(data) < size:
        part = stream.recv(size - len(data))
        if not part:
            raise EOFError('连接在完整报文到达前关闭')
        data.extend(part)
    return bytes(data)

def read_frame(stream):
    kind, size = struct.unpack('!HH', read_exact(stream, 4))
    if size > MAX_PAYLOAD:
        raise ValueError('服务端报文超出本原型允许的长度')
    return kind, read_exact(stream, size)

def config_summary(payload):
    if len(payload) < 24:
        raise ValueError('配置报文不足 24 字节')
    routes = struct.unpack_from('!I', payload, 20)[0]
    if routes > 64 or len(payload) not in (24 + routes * 8, 536):
        raise ValueError('配置长度与路由数量不一致；需要进一步核对协议')
    # Do not emit internal IP addresses or DNS values in shareable diagnostics.
    return {'config_bytes': len(payload), 'route_count': routes}
