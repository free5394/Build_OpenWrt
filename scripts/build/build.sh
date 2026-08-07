#!/bin/sh
# =============================================
# 严格模式：命令失败即退出；尝试启用 pipefail
# =============================================
set -e

# 在子 shell 中检测 pipefail 支持（POSIX 未要求，dash 等不支持）
# 不再调用 `set -o | grep pipefail` 验证：若 grep 未匹配，
# 在 set -e 下会误终止脚本
if (set -o pipefail 2>/dev/null); then
	set -o pipefail
fi

# 获取当前脚本所在目录
SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) ||
	SCRIPT_DIR=$(dirname -- "$0")

# 获取scripts目录所在路径
SCRIPT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)

# =============================================
# 引入环境变量模块
# =============================================
# shellcheck source=/dev/null
. "$SCRIPT_ROOT/build/set-env.sh" || {
	printf '错误: 无法加载环境变量模块 set-env.sh\n' >&2
	exit 1
}

# =============================================
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$SCRIPT_ROOT/include/logger.sh" || {
	printf '错误: 无法加载日志模块 logger.sh\n' >&2
	exit 1
}

# =============================================
# 引入公共模块（强制依赖，最佳实践）
# =============================================
# shellcheck source=/dev/null
. "$SCRIPT_ROOT/include/common.sh" || {
	printf '错误: 无法加载公共模块 common.sh\n' >&2
	exit 1
}

# =============================================
# 引入构建公共函数模块
# =============================================
# shellcheck source=/dev/null
. "$SCRIPT_ROOT/include/build-common.sh" || {
	printf '错误: 无法加载构建公共函数模块 build-common.sh\n' >&2
	exit 1
}

# =============================================
# 业务逻辑开始（首次构建：clone → 配置 → 编译 → 上传）
# =============================================
build_env_info || {
	log_error "无法获取环境变量信息，终止构建"
	exit 1
}

# 切换到工作空间目录
build_enter_workspace || {
	log_error "无法进入工作目录，终止构建"
	exit 1
}

if [ -d "$OPENWRT_DIR" ]; then
	log_error "目录 %s 已经存在，终止构建" "$OPENWRT_DIR"
	exit 1
fi

# 克隆 OpenWrt 仓库
build_clone_openwrt() {
	clone_repo "https://github.com/$OPENWRT_REPO.git" "${OPENWRT_DIR%/}" "$OPENWRT_BRANCH"
}

time_it build_clone_openwrt

log_info "复制文件..."
cp -rf target/x86-64/* "$OPENWRT_DIR/"

# 构建流程
build_make_custom_config() {
	pre_build_process
	build_custom_config
	# build_custom_config_patch
	post_build_process

	log_info "全部完成"
	return 0
}

# 补全配置文件
time_it build_make_custom_config "$@"
