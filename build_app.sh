#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="UTM_SSLVPN.app"
APP_DIR="${SCRIPT_DIR}/${APP_NAME}"

echo "==> 正在构建 ${APP_NAME}..."

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# 1. 复制配置文件与资源文件
cp "${SCRIPT_DIR}/gui/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${SCRIPT_DIR}/gui/worker.py" "${APP_DIR}/Contents/Resources/worker.py"
cp "${SCRIPT_DIR}/gui/repair.py" "${APP_DIR}/Contents/Resources/repair.py"
cp "${SCRIPT_DIR}/mac_vpn.py" "${APP_DIR}/Contents/Resources/mac_vpn.py"
cp "${SCRIPT_DIR}/protocol.py" "${APP_DIR}/Contents/Resources/protocol.py"

if [ -f "${SCRIPT_DIR}/gui/AppIcon.icns" ]; then
    cp "${SCRIPT_DIR}/gui/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# 2. 编译 Swift 图形界面
echo "==> 正在编译 Swift 源代码..."
/usr/bin/swiftc -O \
    "${SCRIPT_DIR}/gui/App.swift" \
    -o "${APP_DIR}/Contents/MacOS/SimpleVPN" \
    -target arm64-apple-macosx13.0

# 3. 本地临时代码签名（消除 macOS 安全隔离限制并应用新图标）
echo "==> 正在对应用进行本地代码签名..."
/usr/bin/codesign --force --deep --sign - "${APP_DIR}"

# 4. 同步更新 outputs 目录下的旧版应用，避免用户点开旧文件
OUTPUTS_APP="${SCRIPT_DIR}/../outputs/轻松VPN-0.2.3.app"
if [ -d "${OUTPUTS_APP}" ]; then
    echo "==> 正在同步更新 outputs 目录下的应用..."
    rm -rf "${OUTPUTS_APP}"
    cp -R "${APP_DIR}" "${OUTPUTS_APP}"
fi

# 刷新 Finder 图标缓存
touch "${APP_DIR}"

echo "==> 构建成功！生成应用路径："
echo "    ${APP_DIR}"
echo ""
echo "您可以在访达（Finder）中直接双击 ${APP_NAME} 运行，或将其拖入 /Applications 文件夹。"
