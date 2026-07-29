#!/bin/sh

echo "设置环境变量..."

export GITHUB_WORKSPACE="$(pwd)"
export NAME_SUFFIX=full

export OPENWRT_REPO=immortalwrt/immortalwrt
export OPENWRT_BRANCH=v25.12.1
export OPENWRT_DIR=$GITHUB_WORKSPACE/openwwrt
export DEVICE_ARCH=x86-64

export PART_SIZE=1024
export UPLOAD_DIR=$GITHUB_WORKSPACE/uploads
export IP_ADDRESS=192.168.100.1
export ROOT_PASSWORD=password
export PPPPOE_USERNAME=wan
export PPPPOE_PASSWORD=wanpassword
export UPLOAD_ARTIFACT=true
export UPLOAD_RELEASE=true

# 编译缓存
export USE_CCACHE=1
export CCACHE_DIR=${CCACHE_DIR:-/tmp/ccache}
