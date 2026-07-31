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
# 业务逻辑开始
# =============================================
log_info "切换到工作目录..."
cd "$GITHUB_WORKSPACE" || {
	log_error "无法切换到工作目录 '$GITHUB_WORKSPACE'"
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

log_info "切换到OpenWrt目录..."
cd "$OPENWRT_DIR" || {
	log_error "无法切换到 OpenWrt 目录 '$OPENWRT_DIR'"
	exit 1
}

log_info "设置文件权限..."
chmod +x files/etc/uci-defaults/*.sh
chmod +x custom_scripts/*.sh

log_info "更新feeds并安装..."
./custom_scripts/apply_custom_feeds.sh

# log_info "生成配置文件..."
# make menuconfig
# ./scripts/diffconfig.sh >"$CUSTOM_CONFIG"

log_info "配置文件..."
cp -f "custom_config/$CUSTOM_CONFIG" .config && make defconfig V=s

log_info "应用自定义设置..."
./custom_scripts/apply_custom_settings.sh

log_info "开始下载依赖..."
make download -j $(($(nproc) + 1)) V=s || make download -j1 V=s

log_info "开始编译OpenWrt..."
echo "$(date '+%Y-%m-%d %H:%M:%S start')" >build.txt
make -j $(($(nproc) + 1)) V=sc || make -j1 V=s
echo "$(date '+%Y-%m-%d %H:%M:%S end')" >>build.txt

log_info "开始上传..."
./custom_scripts/collect_upload.sh

log_info "全部完成"
