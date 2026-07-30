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

echo "目录: $SCRIPT_DIR"
echo "全名: $SCRIPT_FULLNAME"
echo "名称: $SCRIPT_NAME"
echo "日志文件: $LOG_FILE"

# 引入环境变量设置脚本
. "$SCRIPT_DIR"/set-env.sh

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
# exec >"$LOG_FILE" 2>&1

# =============================================
# 业务逻辑开始
# =============================================
echo "切换到工作目录..."
cd "$GITHUB_WORKSPACE"

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

echo "清理构建缓存..."
rm -rf scripts/config/conf scripts/config/*.o tmp/

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
