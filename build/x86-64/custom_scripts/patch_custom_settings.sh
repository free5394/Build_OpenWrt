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
NETWORK_CONFIG="files/etc/uci-defaults/98-network-config.sh"

# 设置根密码
set_password() {
	if [ -z "$ROOT_PASSWORD" ]; then
		log_info "未配置根密码，跳过根密码配置"
		return 0
	fi
	if [ ! -f "$CUSTOM_SETTINGS" ]; then
		log_error "自设置文件 $CUSTOM_SETTINGS 不存在: $CUSTOM_SETTINGS"
		return 1
	fi
	log_info "设置根密码"
	sed -i "s|^root_password=.*|root_password=\"${ROOT_PASSWORD}\"|" "$CUSTOM_SETTINGS"
}

# 设置 PPPoE 配置
set_pppoe() {
	if [ -z "$PPPPOE_USERNAME" ] || [ -z "$PPPPOE_PASSWORD" ]; then
		log_info "未配置 PPPoE 用户名或密码，跳过 PPPoE 配置"
		return 0
	fi
	if [ ! -f "$NETWORK_CONFIG" ]; then
		log_error "网络配置文件 $NETWORK_CONFIG 不存在: $NETWORK_CONFIG"
		return 1
	fi
	log_info "设置 PPPoE 配置"
	sed -i \
		-e "s|^pppoe_username=.*|pppoe_username=\"${PPPPOE_USERNAME}\"|" \
		-e "s|^pppoe_password=.*|pppoe_password=\"${PPPPOE_PASSWORD}\"|" \
		"$NETWORK_CONFIG"
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	set_password
	set_pppoe

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
