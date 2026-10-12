# UTM SSLVPN for macOS (utmssl-mac)

纯 Python 实现的轻量级 macOS UTM3.0 SSLVPN 客户端。无需安装第三方 Python 依赖（使用系统原生 Python 3 与 `utun` 虚拟网卡），开箱即用。

---

## 特性

- **零外部依赖**：基于 macOS 自带的 `/usr/bin/python3`，无需 `pip install`。
- **系统原生虚拟网卡**：基于 macOS 原生 `utun` 控制接口收发 IPv4 数据包。
- **安全与分流**：
  - 强制 TLS 1.2+ 及标准证书验证，不弱化网络安全。
  - 严格限制为服务端下发的私网路由（RFC 1918），拒绝默认路由劫持与公网路由接管。
  - 正常断开（Ctrl+C）时自动删除添加的路由并关闭 `utun` 网卡。
- **灵活配置**：支持从保存的登录网页自动提取参数，或通过命令行参数 / `config.json` 指定服务器、端口及业务跳转。

---

## 快速使用

### 1. 配置（可选）

如需固定配置，可将 `config.example.json` 复制为 `config.json` 并修改：

```bash
cp config.example.json config.json
```

`config.json` 示例：
```json
{
  "server": "vpn.example.com",
  "port": 10443,
  "target_url": "http://10.0.0.2:8080",
  "default_page": "~/Desktop/SSLVPN 客户端.html"
}
```

### 2. 获取会话并连接

1. 在浏览器打开 VPN 登录门户完成登录认证。
2. 将认证成功的连接页面按 `⌘ + S` 保存完整网页到本地（例如桌面：`SSLVPN 客户端.html`，保留同名资源文件夹）。
3. 启动客户端（创建 `utun` 网卡及配置路由需要管理员权限）：

```bash
sudo /usr/bin/python3 mac_vpn.py --page "$HOME/Desktop/SSLVPN 客户端.html"
```

也可直接通过双击 `启动VPN.command` 运行。

### 3. 高级命令行参数

```text
用法: mac_vpn.py [-h] [--config CONFIG] [--page PAGE] [--link LINK]
                  [--server SERVER] [--port PORT] [--target-url TARGET_URL] [--probe]

可选参数:
  --config CONFIG        配置文件路径 (JSON)
  --page PAGE            保存的 VPN 登录网页路径 (默认: ~/Desktop/SSLVPN 客户端.html)
  --link LINK            直接传入 utmssl://... 连接链接 (无需保存网页)
  --server SERVER        指定/校验 VPN 服务器域名或 IP
  --port PORT            指定/校验 VPN 隧道端口
  --target-url URL       连接建立成功后提示打开的内网业务地址
  --probe                仅探测握手与会话有效性，不修改系统路由与网卡
```

---

## 运行测试

离线协议及配置单元测试：

```bash
python3 test_protocol.py
python3 test_mac_vpn.py
```

---

## 注意事项

1. **凭据安全**：保存的登录网页包含临时认证会话值，请妥善保管，**切勿将包含真实会话或公司凭据的 HTML 网页提交至代码仓库**。
2. **DNS 配置**：当前版本主要配置 IPv4 私网路由，建议直接使用内网 IP 进行访问；如需域名解析，可自行配置系统 DNS。
3. **断开清理**：连接使用完毕后，请在终端按 `Ctrl+C` 退出程序，客户端会自动清理路由与虚拟网卡。请避免强杀进程导致残留路由规则。
