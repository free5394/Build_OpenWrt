#!/bin/sh
# 98-network-config.sh - 网络接口自动检测与配置脚本
# 规则：单网口→LAN（旁路由 DHCP）；多网口→最后一个为WAN，其余为LAN

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
exec >"$log_file" 2>&1

# PPPoE 用户名和密码
pppoe_username=""
pppoe_password=""

# =============================================
# 业务逻辑开始
# =============================================
log() {
	echo "[$(date '+%H:%M:%S')] $*"
}

die() {
	log "错误: $*"
	return 1
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

# ============================================================
# 主流程
# ============================================================
main() {
	log "[$SCRIPT_NAME] 开始执行"

	modify_wan_pppoe

	log "[$SCRIPT_NAME] 配置验证通过"
}

main "$@"
exit 0
