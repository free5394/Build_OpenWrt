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

# 工作目录
export GITHUB_WORKSPACE="$(pwd)"
export LOG_DIR="$GITHUB_WORKSPACE/logs"

# =============================================
# 引入环境变量模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")/set-env.sh" || {
	printf '错误: 无法加载环境变量模块 set-env.sh\n' >&2
	exit 1
}

# =============================================
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")/x86-64/common_scripts/logger.sh" || {
	printf '错误: 无法加载日志模块 logger.sh\n' >&2
	exit 1
}

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
# 引入构建公共函数模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")/x86-64/common_scripts/build_common.sh" || {
	printf '错误: 无法加载构建公共函数模块 build_common.sh\n' >&2
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
	clone_repo "https://github.com/$OPENWRT_REPO.git" "${OPENWRT_DIR%/}"
}

time_it build_clone_openwrt

log_info "复制文件..."
cp -rf "$(dirname -- "$0")"/x86-64/* "$OPENWRT_DIR/"

build_enter_openwrt_dir || {
	log_error "无法进入 OpenWrt 目录，终止构建"
	exit 1
}

# 构建流程
build_make_custom_config() {
	pre_build_process
	build_custom_config
	post_build_process

	log_info "全部完成"
	return 0
}

# 补全配置文件
time_it build_make_custom_config "$@"
