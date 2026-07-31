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
CONFIG_FILE="${CONFIG_FILE:-.config}"

# 修补配置文件
patch_config() {
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
	sed -i '/lan) ipad/s/"[0-9.]*"/"'"$IP_ADDRESS"'"/' "$CONFIG_GENERATE"
	# 校验 IP 是否成功写入，防止上游 config_generate 格式变更导致静默失败
	if grep -q "lan) ipad.*\"$IP_ADDRESS\"" "$CONFIG_GENERATE"; then
		log_info "已修改默认LAN IP地址为: $IP_ADDRESS"
	else
		log_warn "LAN IP 修改后校验未通过，可能上游 config_generate 格式已变更，请检查 $CONFIG_GENERATE"
	fi
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

	# ttyd 免登录（默认开启，设置 TTYD_AUTOLOGIN=0 关闭；免登录有安全风险，禁止在公网暴露 ttyd）
	if [ "${TTYD_AUTOLOGIN:-0}" = "1" ]; then
		sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config
		log_info "已启用 ttyd root 免登录"
	else
		log_info "TTYD_AUTOLOGIN=0，跳过 ttyd 免登录配置"
	fi
}

# 配置 openclash 核心配置
preset_openclash_core() {
	if [ ! -f "$CONFIG_FILE" ]; then
		log_error "配置文件 $CONFIG_FILE 不存在"
		return 1
	fi
	# 精确判断 .config 中是否选中 luci-app-openclash
	if ! grep -q '^CONFIG_PACKAGE_luci-app-openclash=y$' "$CONFIG_FILE"; then
		log_info "未选择 luci-app-openclash，跳过 openclash core 配置"
		return 0
	fi
	_core_ver="${OPENCLASH_CORE_VERSION:-v2}"
	log_info "✅ 已选择 luci-app-openclash，添加 openclash core"
	mkdir -p files/etc/openclash/core
	# 下载 clash_meta 核心（带重试与失败检查）
	META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-$_core_ver.tar.gz"
	if ! wget --tries=3 --timeout=30 --max-redirect=3 -qO /tmp/clash_meta.tar.gz "$META_URL"; then
		log_error "OpenClash 核心下载失败: $META_URL"
		return 1
	fi
	tar xOvzf /tmp/clash_meta.tar.gz > files/etc/openclash/core/clash_meta || {
		log_error "OpenClash 核心解压失败"
		rm -f /tmp/clash_meta.tar.gz
		return 1
	}
	rm -f /tmp/clash_meta.tar.gz
	chmod +x files/etc/openclash/core/clash_meta
	# 下载 GeoIP / GeoSite 数据（带重试）
	wget --tries=3 --timeout=30 --max-redirect=3 -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat || {
		log_warn "GeoIP.dat 下载失败，OpenClash 可运行但 GeoIP 规则不可用"
	}
	wget --tries=3 --timeout=30 --max-redirect=3 -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat || {
		log_warn "GeoSite.dat 下载失败，OpenClash 可运行但 GeoSite 规则不可用"
	}
	log_info "已添加 openclash 核心配置"
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	patch_config
	modify_ip_address
	modify_theme
	apply_custom_settings
	preset_openclash_core

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
