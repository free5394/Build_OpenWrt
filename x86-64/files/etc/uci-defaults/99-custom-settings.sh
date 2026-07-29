#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（BusyBox ash 不支持时静默忽略）
set -o pipefail 2>/dev/null || true

# 保存脚本名以供提示
SCRIPT_NAME="$(basename "$0")"
log_file="/tmp/$SCRIPT_NAME.log"

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

is_first_boot || {
	log "[$SCRIPT_NAME] 已生效，跳过"
	exit 0
}

echo "脚本开始执行 - $(date)"

# LAN 的 IPv4 地址（纯 IP，留空则不修改）
lan_ip_addr=""

# # PPPoE 用户名和密码
pppoe_username=""
pppoe_password=""

# 修改LAN口IP（纯 IP 校验；合法时补 /24 写入）
modify_lan_ip() {
	[ -n "$lan_ip_addr" ] || return 0

	# 校验：4 段，每段 0-255
	local ip="$lan_ip_addr" i ok=1 seg
	# trim 空白
	ip=$(echo "$ip" | awk '{$1=$1};1')
	set -- $(echo "$ip" | tr '.' ' ')
	[ "$#" -eq 4 ] || {
		log "LAN IP 格式错误: $lan_ip_addr"
		return 0
	}
	for seg in "$1" "$2" "$3" "$4"; do
		case "$seg" in
		*[!0-9]*)
			ok=0
			break
			;;
		esac
		[ "$seg" -ge 0 ] && [ "$seg" -le 255 ] || {
			ok=0
			break
		}
	done
	if [ "$ok" -ne 1 ]; then
		log "LAN IP 格式错误: $lan_ip_addr"
		return 0
	fi

	uci -q batch <<EOF
set network.lan.ipaddr='${ip}/24'
commit network
EOF
}

# 修改WAN口为PPPoE
modify_wan_pppoe() {
	if [ -n "$pppoe_username" ] && [ -n "$pppoe_password" ]; then
		# 旁路由单网口路径下 98 脚本不会创建 network.wan
		[ -n "$(uci -q get network.wan 2>/dev/null)" ] || {
			log "未检测到 network.wan，跳过 PPPoE 配置"
			return 0
		}
		uci -q set network.wan.proto=pppoe
		uci -q set network.wan.username="$pppoe_username"
		uci -q set network.wan.password="$pppoe_password"
		uci commit network
	fi
}

# 修改系统时区为东八区（上海）
modify_timezone() {
	uci set system.@system[0].timezone='CST-8'
	uci set system.@system[0].zonename='Asia/Shanghai'
	uci commit system
}

main() {
	modify_timezone
	modify_wan_pppoe
	modify_lan_ip
}

# 调用主函数
main "$@"
exit 0
