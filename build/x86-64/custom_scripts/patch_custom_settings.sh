#!/bin/sh
# =============================================
# 引入公共模块（强制依赖，最佳实践）
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/common.sh || {
	printf '错误: 无法加载公共模块 common.sh\n' >&2
	exit 1
}

# =============================================
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/logger.sh || {
	printf '错误: 无法加载日志模块 logger.sh\n' >&2
	exit 1
}

# =============================================
# 业务逻辑开始
# =============================================

CUSTOM_SETTINGS="files/etc/uci-defaults/99-custom-settings.sh"

# 设置根密码
set_password() {
	if [ -z "$ROOT_PASSWORD" ]; then
		log_info "未配置根密码，跳过根密码配置"
		return 0
	fi
	if [ ! -f "$CUSTOM_SETTINGS" ]; then
		log_error "自设置文件 $CUSTOM_SETTINGS 不存在"
		return 1
	fi
	log_info "设置根密码"
	awk -v pwd="$ROOT_PASSWORD" '
		/^root_password=/ { printf "root_password=\"%s\"\n", pwd; next }
		{ print }
	' "$CUSTOM_SETTINGS" > "$CUSTOM_SETTINGS.tmp" && mv -f "$CUSTOM_SETTINGS.tmp" "$CUSTOM_SETTINGS" || {
		log_error "根密码写入失败"
		return 1
	}
	return 0
}

# 设置 PPPoE 配置
set_pppoe() {
	if [ -z "$PPPOE_USERNAME" ] || [ -z "$PPPOE_PASSWORD" ]; then
		log_info "未配置 PPPoE 用户名或密码，跳过 PPPoE 配置"
		return 0
	fi
	if [ ! -f "$CUSTOM_SETTINGS" ]; then
		log_error "网络配置文件 $CUSTOM_SETTINGS 不存在"
		return 1
	fi
	log_info "设置 PPPoE 配置"
	awk -v user="$PPPOE_USERNAME" -v pass="$PPPOE_PASSWORD" '
		/^pppoe_username=/ { printf "pppoe_username=\"%s\"\n", user; next }
		/^pppoe_password=/ { printf "pppoe_password=\"%s\"\n", pass; next }
		{ print }
	' "$CUSTOM_SETTINGS" > "$CUSTOM_SETTINGS.tmp" && mv -f "$CUSTOM_SETTINGS.tmp" "$CUSTOM_SETTINGS" || {
		log_error "PPPoE 配置写入失败"
		return 1
	}
	return 0
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
