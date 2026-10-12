#!/bin/zsh
CLIENT_DIR=${0:A:h}
printf '%s\n' 'macOS UTM SSLVPN 客户端：需要管理员权限创建虚拟网卡和路由。' '密码由 macOS sudo 读取，输入时不会显示。' '保持窗口打开；按 Ctrl+C 断开并清理。'
sudo /usr/bin/python3 -E -s "$CLIENT_DIR/mac_vpn.py" "$@"
printf '%s\n' '程序已退出。按回车关闭此窗口。'
read -r reply
