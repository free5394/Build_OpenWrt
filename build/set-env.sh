#!/bin/sh

echo "设置环境变量..."

export GITHUB_WORKSPACE="$(pwd)"
_config_name=full

export OPENWRT_REPO=immortalwrt/immortalwrt
export OPENWRT_BRANCH=v25.12.1
export OPENWRT_DIR=openwrt
export DEVICE_ARCH=x86-64

export PART_SIZE=1024
export UPLOAD_DIR=upload
export IP_ADDRESS=192.168.10.1
export UPLOAD_ARTIFACT=true
export UPLOAD_RELEASE=true

# 编译缓存
export USE_CCACHE=1
export CCACHE_DIR=${CCACHE_DIR:-"$HOME/ccache"}
# 忽略目录路径变更带来的 Hash 变化（提高缓存命中率）
export CCACHE_NOHASHDIR=true
# 禁用 ccache 内部压缩以提升 CPU 换缓存的效率（若 SSD/内存空间充足）
export CCACHE_NOCOMPRESS=true

# 自定义备份目录
export BAK_ENABLED=1           # 是否启用备份功能,0 不启用， 1 启用
export CUSTOM_BAK="custom_bak" # 自定义备份目录,相对于 GITHUB_WORKSPACE

# 抑制 common.sh/set-env.sh 的加载日志，减少 CI 噪声
export LOG_SILENT=1

export NAME_SUFFIX=$_config_name
# 自定义配置文件
export CUSTOM_CONFIG=$_config_name.config

# 加载日志：设置 LOG_SILENT=1 可抑制（CI 环境推荐启用以减少噪声）
if [ "${LOG_SILENT:-0}" -eq "1" ]; then
	printf '========= %s 脚本开始加载 ============\n' "set-env.sh"
	printf 'GITHUB_WORKSPACE: %s\n' "$GITHUB_WORKSPACE"
	printf 'OPENWRT_DIR: %s\n' "$OPENWRT_DIR"
	printf 'UPLOAD_DIR: %s\n' "$UPLOAD_DIR"
	printf 'OPENWRT_REPO: %s\n' "$OPENWRT_REPO"
	printf 'OPENWRT_BRANCH: %s\n' "$OPENWRT_BRANCH"
	printf 'CUSTOM_BAK: %s\n' "$CUSTOM_BAK"
	printf '========= %s 脚本结束加载 ============\n' "set-env.sh"
fi
