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

	log "[$SCRIPT_NAME] 执行完成"
}

# 调用主函数
main "$@"
exit 0
