# UTM SSLVPN for macOS (utmssl-mac)

纯原生、零外部依赖的 macOS UTM3.0 SSLVPN 客户端，提供 **原生图形界面 (App)** 与 **轻量级命令行 (CLI)** 双模式支持。

- **原生 GUI 交互**：内置 Swift 开发的 Cocoa 图形界面，支持在窗口内直接配置服务器与端口，支持浏览器 `utmssl://` 协议回调自动捕获会话。
- **零外部依赖**：基于 macOS 自带的 `/usr/bin/python3` 与原生系统网络接口（`utun` 虚拟网卡），无需 `pip install` 任何第三方包。
- **一键打包**：提供自动化构建脚本，利用系统自带的 `swiftc` 编译器即可秒级构建独立的 `.app` 应用程序。
- **安全与私网分流**：
  - 强制 TLS 1.2+ 及标准证书验证，不弱化网络安全。
  - 严格限制为服务端下发的私网路由（RFC 1918），拒绝默认路由劫持与公网路由接管。
  - 正常断开连接或退出应用时，自动清理添加的临时私网路由并关闭虚拟网卡。

---

## 快速开始

### 方式一：使用原生图形界面 (GUI App) — 推荐

#### 1. 一键编译生成应用
在项目根目录下执行构建脚本（首次运行或拉取更新后）：

```bash
./build_app.sh
```

脚本将利用 macOS 自带的 Swift 编译器在当前目录生成 **`UTM_SSLVPN.app`**。您可以直接双击运行，或将其拖入 `/Applications` 文件夹。

#### 2. 在图形界面中配置与连接
1. **配置参数**：
   - 打开应用后，在“连接参数配置”区域填入：
     - **服务器地址**：例如 `118.249.86.190` 或 VPN 域名
     - **隧道端口**：例如 `10443`
     - **登录页路径**：默认为 `/internal-server/pages/index.html`
   - 参数会在连接时自动保存至 macOS 用户偏好中，下次打开自动加载。
2. **日常连接流程**：
   - 点击 **“① 打开 VPN 登录页”**，浏览器将自动弹出公司 VPN 门户。
   - 在网页中正常输入账号、密码并登录。
   - 登录成功后，在网页上点击“连接”，浏览器会询问是否允许打开应用，点击允许。
   - 回到应用界面，点击 **“连接 VPN”**，在 macOS 授权弹窗中输入锁屏密码。
   - 界面变为 **“● 已连接”**，此时系统已安全建立隧道并接入私网路由。
3. **断开连接**：
   - 点击界面上的 **“断开 VPN”** 或直接按 `⌘ + Q` 退出应用，程序将自动还原网络路由与虚拟网卡。

---

### 方式二：使用命令行模式 (CLI)

如果您习惯使用终端，也可以脱离图形界面直接运行：

#### 1. 配置文件（可选）
复制模板文件 `config.example.json` 为 `config.json`：
```bash
cp config.example.json config.json
```
填入您的网关参数：
```json
{
  "server": "118.249.86.190",
  "port": 10443,
  "default_page": "~/Desktop/SSLVPN 客户端.html"
}
```

#### 2. 运行连接
```bash
# 自动读取保存的网页
sudo /usr/bin/python3 mac_vpn.py --page "$HOME/Desktop/SSLVPN 客户端.html"

# 或直接传入 utmssl 链接
sudo /usr/bin/python3 mac_vpn.py --link "utmssl://服务器:端口/conn?会话值"

# 或直接在访达中双击
双击 "启动VPN.command"
```

---

## 命令行高级参数

```text
用法: mac_vpn.py [-h] [--config CONFIG] [--page PAGE] [--link LINK]
                  [--link-file LINK_FILE] [--control-dir CONTROL_DIR]
                  [--server SERVER] [--port PORT] [--probe]

可选参数:
  --config CONFIG        配置文件路径 (JSON)
  --page PAGE            保存的 VPN 登录网页路径 (默认: ~/Desktop/SSLVPN 客户端.html)
  --link LINK            直接传入 utmssl://... 连接链接 (无需保存网页)
  --server SERVER        指定/校验 VPN 服务器域名或 IP
  --port PORT            指定/校验 VPN 隧道端口
  --probe                仅探测握手与会话有效性，不修改系统路由与网卡
```

---

## 运行测试

运行离线协议与配置解析单元测试：

```bash
python3 -m unittest discover -s . -p 'test_*.py'
```

---

## 安全注意事项

1. **凭据安全**：保存的登录网页和连接链接中包含短期认证会话值，请妥善保管。`.gitignore` 已默认过滤所有 HTML 文件及本地 `config.json`，防止敏感凭据外泄。
2. **规范退出**：请通过应用界面的“断开 VPN”或终端的 `Ctrl + C` 正常断开连接，以便客户端执行路由清理。请尽量避免使用 `kill -9` 强杀进程导致系统临时路由残留。
