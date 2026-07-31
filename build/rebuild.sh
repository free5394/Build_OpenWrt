#!/bin/sh

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
echo "切换到工作目录..."
cd "$GITHUB_WORKSPACE" || {
	printf "错误: 无法切换到工作目录 '$GITHUB_WORKSPACE'\n" >&2
	exit 1
}

if [ ! -d "$OPENWRT_DIR" ]; then
	echo "OpenWrt 目录 '$OPENWRT_DIR' 不存在"
	exit 1
fi

echo "删除上传文件夹..."
rm -rf "$UPLOAD_DIR"

echo "切换到OpenWrt目录..."
cd "$OPENWRT_DIR" || {
	printf "错误: 无法切换到 OpenWrt 目录 '$OPENWRT_DIR'\n" >&2
	exit 1
}

echo "清理旧构建..."
make clean # 清理编译产物
# make dirclean                 # 清理更彻底（包括工具链）
# make distclean                # 完全清理（需重新配置）

echo "更新feeds并安装..."
./custom_scripts/apply_custom_feeds.sh

echo "生成配置文件..."
rm -rf .config
make menuconfig
./scripts/diffconfig.sh >$CUSTOM_CONFIG

echo "应用自定义设置..."
./custom_scripts/apply_custom_settings.sh

echo "开始下载依赖..."
make download -j $(($(nproc) + 1)) V=s || make download -j1 V=s

echo "开始编译OpenWrt..."
echo "$(date '+%Y-%m-%d %H:%M:%S start')" >build.txt
make -j $(($(nproc) + 1)) V=s || make -j1 V=s
echo "$(date '+%Y-%m-%d %H:%M:%S end')" >>build.txt

echo "开始上传..."
./custom_scripts/collect_upload.sh

echo "全部完成"
