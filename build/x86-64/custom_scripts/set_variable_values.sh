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

# =============================================
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/logger.sh || {
	printf '错误: 无法加载日志模块 logger.sh\n' >&2
	exit 1
}

# =============================================
# 引入公共模块（强制依赖，最佳实践）
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/common.sh || {
	printf '错误: 无法加载公共模块 common.sh\n' >&2
	exit 1
}

# =============================================
# 业务逻辑开始
# =============================================
set_repo_info() {
	# 源码更新信息（使用 heredoc 写入多行环境变量，符合 GitHub 推荐格式）
	current_dir=$(pwd)
	cd "$GITHUB_WORKSPACE"
	cat >>"$GITHUB_ENV" <<EOF
COMMIT_AUTHOR=$(git show -s --date=short --format='作者: %an')
COMMIT_DATE=$(git show -s --date=short --format='时间: %ci')
COMMIT_MESSAGE=$(git show -s --date=short --format='内容: %s')
COMMIT_HASH=$(git show -s --date=short --format='hash: %H')
EOF
	cd "$current_dir"
	return 0
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	# GITHUB_ENV 仅在 GitHub Actions 环境可用；本地执行时跳过写入
	if [ -z "${GITHUB_ENV:-}" ]; then
		log_warn "GITHUB_ENV 未设置，跳过环境变量写入（本地执行可忽略）"
		return 0
	fi

	# 源仓库与分支
	SOURCE_REPO=$(basename "$OPENWRT_REPO")
	echo "SOURCE_REPO=$SOURCE_REPO" >>"$GITHUB_ENV"

	# 平台架构（使用 sed -nE 替代 grep -oP，避免依赖 PCRE，提升可移植性）
	TARGET_NAME=$(sed -nE 's/^CONFIG_TARGET_([a-z0-9]+)=y$/\1/p' .config | head -n1)
	SUBTARGET_NAME=$(sed -nE "s/^CONFIG_TARGET_${TARGET_NAME}_([a-z0-9]+)=y\$/\1/p" .config | head -n1)
	DEVICE_TARGET="$TARGET_NAME-$SUBTARGET_NAME"
	cat >>"$GITHUB_ENV" <<EOF
TARGET_NAME=$TARGET_NAME
SUBTARGET_NAME=$SUBTARGET_NAME
DEVICE_TARGET=$DEVICE_TARGET
EOF

	# 内核版本
	KERNEL=$(sed -nE 's/^KERNEL_PATCHVER:=([0-9.]+)$/\1/p' "target/linux/$TARGET_NAME/Makefile" | head -n1)
	KERNEL_FILE="include/kernel-$KERNEL"
	[ -e "$KERNEL_FILE" ] || KERNEL_FILE="target/linux/generic/kernel-$KERNEL"
	KERNEL_VERSION=$(sed -nE 's/^LINUX_KERNEL_HASH-([0-9.]+)$/\1/p' "$KERNEL_FILE" | head -n1)
	echo "KERNEL_VERSION=$KERNEL_VERSION" >>"$GITHUB_ENV"

	log_info "SOURCE_REPO=%s" "$SOURCE_REPO"
	log_info "TARGET_NAME=%s" "$TARGET_NAME"
	log_info "SUBTARGET_NAME=%s" "$SUBTARGET_NAME"
	log_info "DEVICE_TARGET=%s" "$DEVICE_TARGET"
	log_info "KERNEL=%s" "$KERNEL"
	log_info "KERNEL_FILE=%s" "$KERNEL_FILE"
	log_info "KERNEL_VERSION=%s" "$KERNEL_VERSION"

	set_repo_info || true

	log_info "$SCRIPT_NAME 脚本执行完成"
	return 0
}

# 调用主函数
main "$@"
