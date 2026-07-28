#!/bin/sh

chmod +x set-env.sh
. ./set-env.sh

echo "切换到OpenWrt目录..."
cd $OPENWRT_DIR
mkdir -p logs

echo "清理旧构建..."
make clean # 清理编译产物
# make dirclean                 # 清理更彻底（包括工具链）
# make distclean                # 完全清理（需重新配置）
rm -rf $UPLOAD_DIR/

echo "更新feeds并安装..."
./custom_scripts/apply_custom_feeds.sh

echo "生成配置文件..."
make menuconfig
./scripts/diffconfig.sh >default.config

echo "应用自定义设置..."
./custom_scripts/apply_custom_settings.sh
./custom_scripts/patch_custom_settings.sh

echo "开始下载依赖..."
(make download -j $(($(nproc) + 1)) V=s || make download -j1 V=s) 1>logs/download.txt 2>&1

echo "开始编译OpenWrt..."
echo "$(date '+%Y-%m-%d %H:%M:%S start')" >build.txt
make -j $(($(nproc) + 1)) V=s || make -j1 V=s
echo "$(date '+%Y-%m-%d %H:%M:%S end')" >>build.txt

echo "开始上传..."
./custom_scripts/collect_upload.sh

echo "全部完成"
