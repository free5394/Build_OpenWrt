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

# 修改系统时区为东八区（上海）
modify_timezone() {
	uci batch <<EOF
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system
EOF
}

main() {
	log "[$SCRIPT_NAME] 开始执行"

	modify_timezone
}

# 调用主函数
main "$@"
exit 0
