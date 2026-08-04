#!/bin/sh

echo "设置环境变量..."

# 工作目录
export GITHUB_WORKSPACE="$(pwd)"
export OPENWRT_REPO=immortalwrt/immortalwrt
export OPENWRT_BRANCH=v25.12.1
export OPENWRT_DIR=openwrt
export UPLOAD_DIR=upload
export LOG_DIR=logs

# 自定义配置文件
# export CUSTOM_CONFIG="custom_config/standard.config"
export CUSTOM_CONFIG="custom_config/full.config"

export PART_SIZE=1024
export IP_ADDRESS=192.168.10.1
export UPLOAD_ARTIFACT=true
export UPLOAD_RELEASE=true

# 自定义备份目录
export BAK_ENABLED=1           # 是否启用备份功能,0 不启用， 1 启用
export CUSTOM_BAK="custom_bak" # 自定义备份目录,相对于 GITHUB_WORKSPACE

# 编译缓存
export USE_CCACHE=1
export CCACHE_DIR=${CCACHE_DIR:-"$HOME/ccache"}
# 忽略目录路径变更带来的 Hash 变化（提高缓存命中率）
export CCACHE_NOHASHDIR=true
# 禁用 ccache 内部压缩以提升 CPU 换缓存的效率（若 SSD/内存空间充足）
export CCACHE_NOCOMPRESS=true
