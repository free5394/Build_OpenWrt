#!/bin/sh
# =============================================
# 严格模式：命令失败即退出；尝试启用 pipefail
# =============================================
set -e

# 在子 shell 中检测 pipefail 支持（POSIX 未要求，dash 等不支持）
# 不再调用 `set -o | grep pipefail` 验证：若 grep 未匹配，
# 在 set -e 下会误终止脚本
if (set -o pipefail 2>/dev/null); then
	set -o pipefail
fi

# =============================================
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/logger.sh || {
	printf '错误: 无法加载日志模块 logger.sh\n' >&2
	exit 1
}

# =============================================
# 引入公共模块（强制依赖，最佳实践）
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/common.sh || {
	printf '错误: 无法加载公共模块 common.sh\n' >&2
	exit 1
}

# =============================================
# 业务逻辑开始
# =============================================
CUSTOM_SETTINGS="files/etc/uci-defaults/99-custom-settings.sh"
CONFIG_FILE="${CONFIG_FILE:-.config}"
MODIFY_LAN_IP_TYPE=2 # 默认 方案二, 修改默认LAN IP地址
MODIFY_THEME_TYPE=2  # 默认 方案二, 修改默认主题

# 修补配置文件
patch_config() {
	if [ -z "$PART_SIZE" ]; then
		log_warn "PART_SIZE is empty"
		return 0
	fi
	if [ ! -f "$CONFIG_FILE" ]; then
		log_error "配置文件 $CONFIG_FILE 不存在"
		return 1
	fi
	sed -i -e '/^CONFIG_TARGET_ROOTFS_PARTSIZE=/d' \
		-e '$a CONFIG_TARGET_ROOTFS_PARTSIZE='"$PART_SIZE" \
		"$CONFIG_FILE"
	log_info "已设置固件rootfs大小为: $PART_SIZE"
	return 0
}

# 方案一, 修改默认LAN IP地址
modify_lan_ip_address_1() {
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
		return 0
	fi
	log_warn "LAN IP 修改后校验未通过，可能上游 config_generate 格式已变更，请检查 $CONFIG_GENERATE"
	return 0
}

# 方案二, 修改默认LAN IP地址
modify_lan_ip_address_2() {
	if [ -z "$IP_ADDRESS" ]; then
		log_info "未配置 IP地址，跳过 IP地址配置"
		return 0
	fi
	if [ ! -f "$CUSTOM_SETTINGS" ]; then
		log_error "自设置文件 $CUSTOM_SETTINGS 不存在"
		return 1
	fi
	log_info "设置 IP地址为: $IP_ADDRESS"
	awk -v ip_address="$IP_ADDRESS" '
    /^lan_ip_addr=/ { printf "lan_ip_addr=\"%s\"\n", ip_address; next }
    { print }
	' "$CUSTOM_SETTINGS" >"$CUSTOM_SETTINGS.tmp" && mv -f "$CUSTOM_SETTINGS.tmp" "$CUSTOM_SETTINGS" || {
		log_error "脚本 $CUSTOM_SETTINGS IP地址写入失败"
		return 1
	}
	return 0
}

# 修改默认LAN IP地址
modify_lan_ip_address() {
	if [ "${MODIFY_LAN_IP_TYPE}" = "0" ]; then
		log_info "跳过修改默认LAN IP地址"
		return 0
	fi
	if [ "${MODIFY_LAN_IP_TYPE}" = "1" ]; then
		modify_lan_ip_address_1
		return 0
	fi
	modify_lan_ip_address_2
	return 0
}

# 方案一, 修改默认主题为 luci-theme-argon
modify_theme_1() {
	sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile 2>/dev/null || {
		log_warn "luci-theme-argon 替换失败，可能 feeds 未安装"
		return 1
	}
	return 0
}

# 方案二, 修改默认主题为 luci-theme-argon
modify_theme_2() {
	if [ ! -f "$CUSTOM_SETTINGS" ]; then
		log_error "自设置文件 $CUSTOM_SETTINGS 不存在"
		return 1
	fi
	log_info "设置默认主题为: argon"
	awk -v theme="argon" '
    /^default_theme=/ { printf "default_theme=\"%s\"\n", theme; next }
    { print }
	' "$CUSTOM_SETTINGS" >"$CUSTOM_SETTINGS.tmp" && mv -f "$CUSTOM_SETTINGS.tmp" "$CUSTOM_SETTINGS" || {
		log_error "脚本 $CUSTOM_SETTINGS 主题写入失败"
		return 1
	}
	return 0
}

# 修改默认主题为 luci-theme-argon
modify_theme() {
	if [ "${MODIFY_THEME_TYPE}" = "0" ]; then
		log_info "跳过修改默认主题"
		return 0
	fi
	if [ "${MODIFY_THEME_TYPE}" = "1" ]; then
		modify_theme_1
		return 0
	fi
	modify_theme_2
	return 0
}

# 替换argon主题背景
cp_background_img() {
	BG_SRC="$GITHUB_WORKSPACE/images/bg1.jpg"
	BG_DST=$(find feeds -type f -path "*/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg" 2>/dev/null | head -n 1)
	# 替换默认主题背景
	if [ ! -f "$BG_SRC" ]; then
		log_warn "背景文件 $BG_SRC 不存在"
		return 0
	fi
	if [ ! -f "$BG_DST" ]; then
		log_warn "背景文件 $BG_DST 不存在"
		return 0
	fi
	cp -f "$BG_SRC" "$BG_DST" && log_info "已替换 Argon 主题背景" || log_warn "Argon 主题背景替换失败"
	return 0
}

# 配置 ttyd 免登录
apply_ttyd_auto_login() {
	# ttyd 免登录（默认关闭，设置 TTYD_AUTOLOGIN=1 开启；免登录有安全风险，禁止在公网暴露 ttyd）
	if [ "${TTYD_AUTOLOGIN:-0}" = "0" ]; then
		log_info "TTYD_AUTOLOGIN=0，跳过 ttyd 免登录配置"
		return 0
	fi
	sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config
	log_info "已启用 ttyd root 免登录"
	return 0
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
	# 先解压到临时目录再 mv，避免 tar 路径遍历风险
	_tmp_dir=$(mktemp -d)
	tar xzf /tmp/clash_meta.tar.gz -C "$_tmp_dir" || {
		log_error "OpenClash 核心解压失败"
		rm -rf "$_tmp_dir" /tmp/clash_meta.tar.gz
		return 1
	}
	_core_bin=$(find "$_tmp_dir" -type f -name "clash*" | head -1)
	if [ -z "$_core_bin" ]; then
		log_error "解压后未找到 clash_meta 二进制文件"
		rm -rf "$_tmp_dir" /tmp/clash_meta.tar.gz
		return 1
	fi
	mv -f "$_core_bin" files/etc/openclash/core/clash_meta
	rm -rf "$_tmp_dir" /tmp/clash_meta.tar.gz
	chmod +x files/etc/openclash/core/clash_meta
	# 下载 GeoIP / GeoSite 数据（带重试）
	wget --tries=3 --timeout=30 --max-redirect=3 -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat || {
		log_warn "GeoIP.dat 下载失败，OpenClash 可运行但 GeoIP 规则不可用"
	}
	wget --tries=3 --timeout=30 --max-redirect=3 -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat || {
		log_warn "GeoSite.dat 下载失败，OpenClash 可运行但 GeoSite 规则不可用"
	}
	log_info "已添加 openclash 核心配置"
	return 0
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	patch_config || true
	modify_lan_ip_address || true
	modify_theme || true
	cp_background_img || true
	apply_ttyd_auto_login || true
	preset_openclash_core || true

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
