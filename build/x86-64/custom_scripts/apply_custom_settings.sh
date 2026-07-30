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
# LOG_FILE="./logs/$SCRIPT_NAME.log"

# 引入日志模块（假设 logger.sh 在同目录下）
. "$SCRIPT_DIR"/logger.sh

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
# exec >"$LOG_FILE" 2>&1

# =============================================
# 业务逻辑开始
# =============================================

# 修补配置文件
patch_config() {
	CONFIG_FILE=".config"
	if [ -z "$PART_SIZE" ]; then
		log_error "PART_SIZE is empty"
		return 0
	fi
	if [ ! -f "$CONFIG_FILE" ]; then
		log_error "配置文件 $CONFIG_FILE 不存在"
		return 1
	fi
	sed -i.bak -e '/^CONFIG_TARGET_ROOTFS_PARTSIZE=/d' \
		-e '$a CONFIG_TARGET_ROOTFS_PARTSIZE='"$PART_SIZE" \
		"$CONFIG_FILE"
	log_info "已设置固件rootfs大小为: $PART_SIZE"
}

# 方案一, 修改默认LAN IP地址
modify_ip_address() {
	CONFIG_GENERATE="package/base-files/files/bin/config_generate"
	if [ -z "$IP_ADDRESS" ]; then
		log_info "未配置 IP地址，跳过 IP地址配置"
		return 0
	fi
	if [ ! -f "$CONFIG_GENERATE" ]; then
		log_error "配置生成文件 $CONFIG_GENERATE 不存在"
		return 1
	fi
	sed -i '/lan) ipad/s/".*"/"'"$IP_ADDRESS"'"/' "$CONFIG_GENERATE"
	log_info "已修改默认LAN IP地址为: $IP_ADDRESS"
}

modify_theme() {
	# 替换默认主题为 luci-theme-argon
	sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

	# 更改argon主题背景
	BG_SRC="$GITHUB_WORKSPACE/images/bg1.jpg"
	# BG_DST="feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg"
	BG_DST="feeds/kenzo/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg"
	if [ ! -f "$BG_SRC" ]; then
		log_error "背景文件 $BG_SRC 不存在"
		return 1
	fi
	cp -f "$BG_SRC" "$BG_DST" && log_info "已替换 Argon 主题背景" || log_warn "Argon 主题背景替换失败"
}

apply_custom_settings() {
	# 更改默认 Shell 为 zsh
	# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

	# ttyd免登录
	sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	patch_config
	modify_ip_address
	modify_theme
	apply_custom_settings

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
