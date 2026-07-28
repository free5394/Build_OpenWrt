#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（如 bash 环境）
if set -o | grep -q 'pipefail' 2>/dev/null; then
	set -o pipefail
fi

# =============================================
# 2. 日志目录创建与输出重定向
# =============================================
mkdir -p ./logs
exec >./logs/apply_custom_settings.log 2>&1

# =============================================
# 业务逻辑开始
# =============================================
echo "脚本开始执行 - $(date)"

# 示例命令1：正常执行
echo "当前工作目录: $(pwd)"

# 修补配置文件
patch_config() {
	CONFIG_FILE=".config"
	# 设置固件rootfs大小
	if [ -n "${PART_SIZE:-}" ]; then
		sed -i '/ROOTFS_PARTSIZE/d' "$CONFIG_FILE"
		echo "CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE" >>"$CONFIG_FILE"
	fi
}

# 方案一, 修改默认LAN IP地址
modify_ip_address() {
	CONFIG_GENERATE="package/base-files/files/bin/config_generate"
	# 根据环境变量替换默认LAN IP地址
	if [ -n "${IP_ADDRESS:-}" ]; then
		sed -i '/lan) ipad/s/".*"/"'"$IP_ADDRESS"'"/' "$CONFIG_GENERATE"
	fi
}

modify_theme() {
	# 替换默认主题为 luci-theme-argon
	sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

	# 更改argon主题背景
	BG_SRC="$GITHUB_WORKSPACE/images/bg1.jpg"
	BG_DST="feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg"
	if [ -f "$BG_SRC" ]; then
		cp -f "$BG_SRC" "$BG_DST" && echo "已替换 Argon 主题背景" || echo "Argon 主题背景替换失败"
	fi
}

apply_custom_settings() {
	# 更改默认 Shell 为 zsh
	# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

	# ttyd免登录
	sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config
}

# 主函数
main() {
	patch_config
	modify_ip_address
	modify_theme
	apply_custom_settings
}

# 调用主函数
main "$@"
