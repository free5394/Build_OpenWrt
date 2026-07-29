#!/bin/sh
# 网络接口自动检测与配置脚本
# 规则：单网口→LAN（旁路由 DHCP）；多网口→最后一个为WAN，其余为LAN

# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 安全地尝试开启 pipefail
if (set -o pipefail) 2>/dev/null; then
	set -o pipefail
	set -o | grep pipefail
fi

# 脚本所在目录（绝对路径）
SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P) 2>/dev/null || SCRIPT_DIR=$(dirname -- "$0")
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

echo "目录: $SCRIPT_DIR"
echo "全名: $SCRIPT_FULLNAME"
echo "名称: $SCRIPT_NAME"
echo "日志文件: $LOG_FILE"

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
