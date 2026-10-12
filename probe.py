#!/usr/bin/env python3
"""Authentication/configuration probe only. Does not create a VPN interface."""
import argparse
import getpass
import json
import socket
import ssl
from protocol import parse_link, auth_frame, read_frame, config_summary

def main():
    p = argparse.ArgumentParser(description='实验性 UTM SSLVPN 握手验证；不修改路由或 DNS')
    p.add_argument('--cafile', help='由单位 IT 提供的 PEM CA 证书')
    p.add_argument('--server-name', help='由单位 IT 确认、与证书匹配的服务器域名')
    args = p.parse_args()
    link = getpass.getpass('粘贴本机网页生成的 utmssl:// 连接链接（输入不显示、不保存）：')
    try:
        host, port, token = parse_link(link)
        ctx = ssl.create_default_context(cafile=args.cafile)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        with socket.create_connection((host, port), timeout=10) as raw:
            with ctx.wrap_socket(raw, server_hostname=args.server_name or host) as conn:
                print('TLS 验证成功：', conn.version())
                conn.sendall(auth_frame(token))
                for _ in range(8):
                    kind, payload = read_frame(conn)
                    print('收到报文：类型 0x%04x，长度 %d' % (kind, len(payload)))
                    if kind == 0x0201:
                        print(json.dumps(config_summary(payload)))
                        print('收到与静态分析格式一致的配置。尚未建立 VPN 或验证内网访问。')
                        return 0
                print('未收到预期的配置报文，需要对照 Windows 行为。')
                return 2
    except ssl.SSLCertVerificationError:
        print('证书验证失败；需要 IT 提供可信 CA 和匹配域名。没有发送会话值。')
    except ssl.SSLError:
        print('TLS 协商失败；需要核对服务器支持的 TLS 版本。没有自动降级或关闭验证。')
    except (ValueError, UnicodeError, EOFError, OSError):
        print('连接或报文验证失败。请核对链接有效期、隧道端口和协议版本；未输出会话值。')
    return 1

if __name__ == '__main__':
    raise SystemExit(main())
