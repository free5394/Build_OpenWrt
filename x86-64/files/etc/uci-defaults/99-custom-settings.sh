#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（如 bash 环境）
if set -o | grep -q 'pipefail' 2>/dev/null; then
	set -o pipefail
fi

# =============================================
# 2. 日志目录创建与输出重定向
# =============================================
mkdir -p ./logs
exec >./logs/99-custom-settings.log 2>&1

# =============================================
# 业务逻辑开始
# =============================================
echo "脚本开始执行 - $(date)"

# 示例命令1：正常执行
echo "当前工作目录: $(pwd)"

# 系统后台密码（为空则不修改）
root_password="password"

# LAN 的 IPv4 地址
lan_ip_address=""

# # PPPoE 用户名和密码
# pppoe_username=""
# pppoe_password=""

# 修改root 密码
if [ -n "$root_password" ]; then
	(
		echo "$root_password"
		sleep 1
		echo "$root_password"
	) | passwd root >/dev/null
fi

# 修改默认LAN口IP
if [ -n "$lan_ip_address" ]; then
	uci set network.lan.ipaddr="$lan_ip_address/24"
	uci commit network
fi

# if [ -n "$pppoe_username" ] && [ -n "$pppoe_password" ]; then
# 	uci set network.wan.proto=pppoe
# 	uci set network.wan.username="$pppoe_username"
# 	uci set network.wan.password="$pppoe_password"
# 	uci commit network
# fi

# 修改系统时区为东八区（上海）
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system

# # 修改Web界面默认主题为 Argon
# uci set luci.main.mediaurlbase='/luci-static/argon'
# uci commit luci

# 提交所有更改
# uci commit

echo "自定义设置完成"
