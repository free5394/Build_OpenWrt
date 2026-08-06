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
# 业务逻辑开始
# =============================================
# 源仓库与分支
get_openwrt_info() {
	printf "SOURCE_REPO=%s\n" "$(basename "$OPENWRT_REPO")"
	return 0
}

# 目标架构
get_target_info() {
	# 平台架构（使用 sed -nE 替代 grep -oP，避免依赖 PCRE，提升可移植性）
	TARGET_NAME=$(sed -nE 's/^CONFIG_TARGET_([a-z0-9]+)=y$/\1/p' .config | head -n1)
	SUBTARGET_NAME=$(sed -nE "s/^CONFIG_TARGET_${TARGET_NAME}_([a-z0-9]+)=y\$/\1/p" .config | head -n1)
	DEVICE_TARGET="$TARGET_NAME-$SUBTARGET_NAME"
	printf "DEVICE_TARGET=%s\n" "$DEVICE_TARGET"
	printf "TARGET_NAME=%s\n" "$TARGET_NAME"
	printf "SUBTARGET_NAME=%s\n" "$SUBTARGET_NAME"

	# 内核版本
	KERNEL_VERSION=$(sed -nE 's/^KERNEL_PATCHVER:=([0-9.]+)$/\1/p' "target/linux/$TARGET_NAME/Makefile" | head -n1)
	printf "KERNEL_VERSION=%s\n" "$KERNEL_VERSION"
	return 0
}

# 仓库信息
get_repo_info() {
	# 记录当前目录
	current_dir="$(pwd)"
	# 切换到 工作目录
	cd "$GITHUB_WORKSPACE"
	printf "COMMIT_AUTHOR=%s\n" "$(git show -s --date=short --format='作者: %an')"
	printf "COMMIT_DATE=%s\n" "$(git show -s --date=short --format='时间: %ci')"
	printf "COMMIT_MESSAGE=%s\n" "$(git show -s --date=short --format='内容: %s')"
	printf "COMMIT_HASH=%s\n" "$(git show -s --date=short --format='hash: %H')"
	# 切换回当前目录
	cd "$current_dir"
	return 0
}

# 校验关键环境变量
verify_env() {
	if [ -z "$GITHUB_WORKSPACE" ]; then
		log_error "缺少必环境变量: GITHUB_WORKSPACE"
		return 2
	fi
	if [ ! -d "$GITHUB_WORKSPACE" ]; then
		log_warn "工作空间目录 %s 不存在，无文件可处理。" "$GITHUB_WORKSPACE"
		return 2
	fi
	return 0
}

# 工作流
work_flow() {
	# 源仓库与分支
	openwrt_info="$(get_openwrt_info)"
	# 目标架构
	target_info="$(get_target_info)"
	# 仓库信息
	repo_info="$(get_repo_info)"

	log_info "获取到的环境变量:"
	log_info "$openwrt_info"
	log_info "$target_info"
	log_info "$repo_info"
	# GITHUB_ENV 仅在 GitHub Actions 环境可用；本地执行时跳过写入
	if [ -z "${GITHUB_ENV:-}" ]; then
		log_warn "GITHUB_ENV 未设置，跳过环境变量写入（本地执行可忽略）"
		return 0
	fi
	{
		echo "$openwrt_info"
		echo "$target_info"
		echo "$repo_info"
	} >>"$GITHUB_ENV"
}

# 处理任务
process_task() {
	# 记录当前目录
	current_dir="$(pwd)"
	# 切换到 OpenWrt 根目录
	cd "$OPENWRT_DIR"

	"$@" || {
		log_error "任务 %s 失败" "$*"
		cd "$current_dir"
		return 1
	}

	# 切换回当前目录
	cd "$current_dir"
	return 0
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"
	verify_env "$@" || exit 1
	process_task work_flow
	log_info "$SCRIPT_NAME 脚本执行完成"
	return 0
}

# 调用主函数
main "$@"
