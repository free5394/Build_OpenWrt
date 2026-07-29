#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（BusyBox ash 不支持时静默忽略）
set -o pipefail 2>/dev/null || true

# 脚本所在目录（绝对路径）
SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P) 2>/dev/null || SCRIPT_DIR=$(dirname -- "$0")
# 脚本全名（含后缀）
SCRIPT_FULLNAME="${0##*/}"
# 脚本名（不含后缀）
SCRIPT_NAME="${SCRIPT_FULLNAME%.*}"
# 日志文件路径
LOG_FILE="./logs/$SCRIPT_NAME.log"

# 引入日志模块（假设 logger.sh 在同目录下）
. "$SCRIPT_DIR"/logger.sh

# 可选：动态调整日志级别
LOG_LEVEL=20 # 显示日志，包括INFO、WARN、ERROR

# check logger.sh
log_debug "目录: $SCRIPT_DIR"
log_debug "全名: $SCRIPT_FULLNAME"
log_debug "名称: $SCRIPT_NAME"
log_debug "日志文件: $LOG_FILE"

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
# exec >"$LOG_FILE" 2>&1

# =============================================
# 业务逻辑开始
# =============================================

CUSTOM_SETTINGS="files/etc/uci-defaults/99-custom-settings.sh"

set_password() {
	# 根据环境变量替换默认密码
	if [ -n "${ROOT_PASSWORD:-}" ]; then
		sed -i "s|^root_password=.*|root_password=\"${PASSWORD}\"|" "$CUSTOM_SETTINGS"
	fi
}

set_pppoe() {
	# 根据环境变量替换PPPoE账号密码（两者均存在时才替换）
	if [ -n "${PPPPOE_USERNAME:-}" ] && [ -n "${PPPPOE_PASSWORD:-}" ]; then
		sed -i "s|^pppoe_username=.*|pppoe_username=\"${PPPPOE_USERNAME}\"|" "$CUSTOM_SETTINGS"
		sed -i "s|^pppoe_password=.*|pppoe_password=\"${PPPPOE_PASSWORD}\"|" "$CUSTOM_SETTINGS"
	fi
}

# 方案二，修改默认LAN IP地址
set_ip_address() {
	# 根据环境变量替换默认LAN IP地址
	if [ -n "${IP_ADDRESS:-}" ]; then
		sed -i "s|^lan_ip_address=.*|lan_ip_address=\"${IP_ADDRESS}\"|" "$CUSTOM_SETTINGS"
	fi
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	set_password
	# set_pppoe
	# set_ip_address

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
