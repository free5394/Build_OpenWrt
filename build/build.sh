#!/bin/sh

# =============================================
# 严格模式：命令失败即退出
# =============================================
set -e

# =============================================
# 引入公共模块（强制依赖，最佳实践）
# =============================================
# shellcheck source=/dev/null
# 使用 eval 确保路径解析正确，利用 || exit 1 确保加载失败即终止
# 注意：使用 -- 防止文件名以 - 开头被误认为参数
. "$(dirname -- "$0")/x86-64/common_scripts/common.sh" || {
	printf '错误: 无法加载公共模块 common.sh\n' >&2
	exit 1
}

# =============================================
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")/x86-64/common_scripts/logger.sh" || {
	printf '错误: 无法加载日志模块 logger.sh\n' >&2
	exit 1
}

# =============================================
# 引入环境变量模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")/set-env.sh" || {
	printf '错误: 无法加载环境变量模块 set-env.sh\n' >&2
	exit 1
}

# =============================================
# 引入构建公共函数模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")/x86-64/common_scripts/build_common.sh" || {
	printf '错误: 无法加载构建公共函数模块 build_common.sh\n' >&2
	exit 1
}

# =============================================
# 业务逻辑开始（首次构建：clone → 配置 → 编译 → 上传）
# =============================================
build_enter_workspace || {
	log_error "无法进入工作目录，终止构建"
	exit 1
}

if [ -d "$OPENWRT_DIR" ]; then
	log_error "OpenWrt 目录 '$OPENWRT_DIR' 已经存在"
	exit 1
fi

log_info "开始克隆OpenWrt仓库..."
git clone -b "$OPENWRT_BRANCH" --single-branch --depth 1 "https://github.com/$OPENWRT_REPO.git" "$OPENWRT_DIR"

log_info "复制文件..."
cp -rf "$SCRIPT_DIR/$DEVICE_ARCH"/* "$OPENWRT_DIR/"

build_enter_openwrt_dir || {
	log_error "无法进入 OpenWrt 目录，终止构建"
	exit 1
}

log_info "设置文件权限..."
chmod +x files/etc/uci-defaults/*.sh
chmod +x custom_scripts/*.sh

build_apply_feeds_and_settings

# log_info "生成配置文件..."
# make menuconfig
# ./scripts/diffconfig.sh >"$CUSTOM_CONFIG"

log_info "配置文件..."
cp -f "custom_config/$CUSTOM_CONFIG" .config && make defconfig V=s

build_download
build_compile
build_upload

log_info "全部完成"
