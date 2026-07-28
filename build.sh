#!/bin/sh

export OPENWRT_REPO=immortalwrt/immortalwrt
export OPENWRT_BRANCH=v25.12.1
export OPENWRT_DIR=openwrt
export TARGET_ARCH=x86-64

export PART_SIZE=1024
export GITHUB_WORKSPACE=$(pwd)
export UPLOAD_DIR=uploads

echo "开始克隆OpenWrt仓库..."
git clone -b $OPENWRT_BRANCH --single-branch --depth 1 https://github.com/$OPENWRT_REPO.git $OPENWRT_DIR

echo "复制文件..."
cp -r ./$TARGET_ARCH/* $OPENWRT_DIR/

echo "设置文件权限..."
chmod +x $OPENWRT_DIR/files/etc/uci-defaults/*.sh
chmod +x $OPENWRT_DIR/custom_scripts/*.sh

echo "切换到OpenWrt目录..."
cd $OPENWRT_DIR
mkdir -p logs

echo "更新feeds并安装..."
./custom_scripts/apply_custom_feeds.sh

# echo "生成配置文件..."
# make menuconfig
# ./scripts/diffconfig.sh >default.config

echo "配置文件..."
cp -f full.config .config && make defconfig

echo "应用自定义设置..."
./custom_scripts/apply_custom_settings.sh
./custom_scripts/patch_custom_settings.sh

echo "开始下载依赖..."
make download -j $(($(nproc) + 1)) V=s || make download -j1 V=s

echo "开始编译OpenWrt..."
echo $(date "+%Y-%m-%d %H:%M:%S start") >build.txt
make -j $(($(nproc) + 1)) V=s || make -j1 V=s
echo $(date "+%Y-%m-%d %H:%M:%S end") >>build.txt

echo "开始上传..."
export NAME_SUFFIX=walk6834
./custom_scripts/collect_upload.sh

echo "全部完成"
