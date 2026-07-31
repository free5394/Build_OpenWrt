#!/bin/sh

echo "设置环境变量..."

export GITHUB_WORKSPACE="$(pwd)"
export NAME_SUFFIX=full

export OPENWRT_REPO=immortalwrt/immortalwrt
export OPENWRT_BRANCH=v25.12.1
export OPENWRT_DIR=openwrt
export DEVICE_ARCH=x86-64

export PART_SIZE=1024
export UPLOAD_DIR=upload
export IP_ADDRESS=192.168.100.1
export ROOT_PASSWORD=password
export PPPOE_USERNAME=a123
export PPPOE_PASSWORD=p456
export UPLOAD_ARTIFACT=true
export UPLOAD_RELEASE=true

# 编译缓存
export USE_CCACHE=1
export CCACHE_DIR=${CCACHE_DIR:-/tmp/ccache}

# 自定义配置文件
export CUSTOM_CONFIG=standard.config

printf '========= %s 脚本开始加载 ============\n' "set-env.sh"
printf 'GITHUB_WORKSPACE: %s\n' "$GITHUB_WORKSPACE"
printf 'OPENWRT_DIR: %s\n' "$OPENWRT_DIR"
printf 'UPLOAD_DIR: %s\n' "$UPLOAD_DIR"
printf 'OPENWRT_REPO: %s\n' "$OPENWRT_REPO"
printf 'OPENWRT_BRANCH: %s\n' "$OPENWRT_BRANCH"
printf '========= %s 脚本结束加载 ============\n' "set-env.sh"
