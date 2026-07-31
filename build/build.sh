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
cd "$GITHUB_WORKSPACE"

if [ -d "$OPENWRT_DIR" ]; then
	echo "OpenWrt 目录 '$OPENWRT_DIR' 已经存在"
	exit 1
fi

echo "开始克隆OpenWrt仓库..."
git clone -b "$OPENWRT_BRANCH" --single-branch --depth 1 https://github.com/$OPENWRT_REPO.git "$OPENWRT_DIR"

echo "复制文件..."
cp -rf $SCRIPT_DIR/$DEVICE_ARCH/* $OPENWRT_DIR/

echo "切换到OpenWrt目录..."
cd "$OPENWRT_DIR"

echo "创建日志目录..."
mkdir -p logs

echo "设置文件权限..."
chmod +x files/etc/uci-defaults/*.sh
chmod +x custom_scripts/*.sh

echo "更新feeds并安装..."
./custom_scripts/apply_custom_feeds.sh

# echo "生成配置文件..."
# make menuconfig
# ./scripts/diffconfig.sh >$CUSTOM_CONFIG

echo "配置文件..."
cp -f custom_config/$CUSTOM_CONFIG .config && make defconfig V=s

echo "应用自定义设置..."
./custom_scripts/apply_custom_settings.sh
./custom_scripts/patch_custom_settings.sh

echo "开始下载依赖..."
make download -j $(($(nproc) + 1)) V=s || make download -j1 V=s

echo "开始编译OpenWrt..."
echo "$(date '+%Y-%m-%d %H:%M:%S start')" >build.txt
make -j $(($(nproc) + 1)) V=s || make -j1 V=s
echo "$(date '+%Y-%m-%d %H:%M:%S end')" >>build.txt

echo "开始上传..."
./custom_scripts/collect_upload.sh

echo "全部完成"
