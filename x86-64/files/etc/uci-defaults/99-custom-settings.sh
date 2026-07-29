#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（BusyBox ash 不支持时静默忽略）
set -o pipefail 2>/dev/null || true

# 保存脚本名以供提示
SCRIPT_NAME="$(basename "$0")"
log_file="/tmp/uci-defaults.log"

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
exec >>"$log_file" 2>&1

# =============================================
# 业务逻辑开始
# =============================================
log() {
	echo "[$(date '+%H:%M:%S')] $*"
}

# 首次启动探针：时区已设为 Asia/Shanghai 视为已完成
is_first_boot() {
	[ "$(uci -q get system.@system[0].zonename)" = "Asia/Shanghai" ]
}

is_first_boot || { log "[$SCRIPT_NAME] 已生效，跳过"; exit 0; }

echo "脚本开始执行 - $(date)"

# 系统后台密码（为空则不修改）
root_password="password"

# LAN 的 IPv4 地址
lan_ip_address=""

# # PPPoE 用户名和密码
pppoe_username=""
pppoe_password=""

# 修改root 密码
modify_root_password() {
	if [ -n "$root_password" ]; then
		(
			echo "$root_password"
			sleep 1
			echo "$root_password"
		) | passwd root >/dev/null
	fi
}

# 修改LAN口IP
modify_lan_ip() {
	# 修改默认LAN口IP
	if [ -n "$lan_ip_address" ]; then
		[ -n "$(uci -q get network.lan.ipaddr)" ] || (uci set network.lan.ipaddr="$lan_ip_address/24" && uci commit network)
	fi
}

# 修改WAN口为PPPoE
modify_wan_pppoe() {
	if [ -n "$pppoe_username" ] && [ -n "$pppoe_password" ]; then
		uci set network.wan.proto=pppoe
		uci set network.wan.username="$pppoe_username"
		uci set network.wan.password="$pppoe_password"
		uci commit network
	fi
}

# 修改系统时区为东八区（上海）
modify_timezone() {
	uci set system.@system[0].timezone='CST-8'
	uci set system.@system[0].zonename='Asia/Shanghai'
	uci commit system
}

# # 修改Web界面默认主题为 Argon
modify_luci_theme() {
	uci set luci.main.mediaurlbase='/luci-static/argon'
	uci commit luci
}

main() {
	# 检查是否首次启动（避免重复执行）
	[ -f /etc/config/network ] || exit 0

	modify_root_password
	# modify_lan_ip
	modify_timezone
	modify_wan_pppoe
	# modify_luci_theme
}

# 调用主函数
main "$@"

echo "自定义设置完成"
