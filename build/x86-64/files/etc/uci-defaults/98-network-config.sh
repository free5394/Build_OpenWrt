#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 安全地尝试开启 pipefail
if (set -o pipefail) 2>/dev/null; then
	set -o pipefail
	set -o | grep pipefail
fi

# 脚本全名（含后缀）
SCRIPT_FULLNAME="${0##*/}"
# 脚本名（不含后缀）
SCRIPT_NAME="${SCRIPT_FULLNAME%.*}"
# 日志文件路径
LOG_FILE="/tmp/$SCRIPT_NAME.log"

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
exec >"$LOG_FILE" 2>&1

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
}

# 修改WAN口为PPPoE
modify_wan_pppoe() {
	if [ -z "$pppoe_username" ] || [ -z "$pppoe_password" ]; then
		log "未配置 PPPoE 用户名或密码，跳过 PPPoE 配置"
		return 0
	fi
	[ -n "$(uci -q get network.wan 2>/dev/null)" ] || {
		log "未检测到 network.wan，跳过 PPPoE 配置"
		return 0
	}
	uci -q set network.wan.proto=pppoe
	uci -q set network.wan.username="$pppoe_username"
	uci -q set network.wan.password="$pppoe_password"
	uci commit network
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
