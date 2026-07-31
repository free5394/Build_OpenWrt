#!/bin/sh
# =============================================
# 引入公共模块（强制依赖，最佳实践）
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/common.sh || {
	printf '错误: 无法加载公共模块 common.sh\n' >&2
	exit 1
}

# =============================================
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/logger.sh || {
	printf '错误: 无法加载日志模块 logger.sh\n' >&2
	exit 1
}

# =============================================
# 业务逻辑开始
# =============================================

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	# 源仓库与分支
	SOURCE_REPO=$(basename "$OPENWRT_REPO")
	{
		echo "SOURCE_REPO=$SOURCE_REPO"
		echo "LITE_BRANCH=${OPENWRT_BRANCH#*-}"
	} >>"$GITHUB_ENV"

	# 平台架构（使用 sed -nE 替代 grep -oP，避免依赖 PCRE，提升可移植性）
	TARGET_NAME=$(sed -nE 's/^CONFIG_TARGET_([a-z0-9]+)=y$/\1/p' .config | head -n1)
	SUBTARGET_NAME=$(sed -nE "s/^CONFIG_TARGET_${TARGET_NAME}_([a-z0-9]+)=y\$/\1/p" .config | head -n1)
	DEVICE_TARGET="$TARGET_NAME-$SUBTARGET_NAME"
	{
		echo "TARGET_NAME=$TARGET_NAME"
		echo "SUBTARGET_NAME=$SUBTARGET_NAME"
		echo "DEVICE_TARGET=$DEVICE_TARGET"
	} >>"$GITHUB_ENV"

	# 内核版本
	KERNEL=$(sed -nE 's/^KERNEL_PATCHVER:=([0-9.]+)$/\1/p' "target/linux/$TARGET_NAME/Makefile" | head -n1)
	KERNEL_FILE="include/kernel-$KERNEL"
	[ -e "$KERNEL_FILE" ] || KERNEL_FILE="target/linux/generic/kernel-$KERNEL"
	KERNEL_VERSION=$(sed -nE 's/^LINUX_KERNEL_HASH-([0-9.]+)$/\1/p' "$KERNEL_FILE" | head -n1)
	echo "KERNEL_VERSION=$KERNEL_VERSION" >>"$GITHUB_ENV"

	# 源码更新信息
	{
		echo "COMMIT_AUTHOR=$(git show -s --date=short --format="作者: %an")"
		echo "COMMIT_DATE=$(git show -s --date=short --format="时间: %ci")"
		echo "COMMIT_MESSAGE=$(git show -s --date=short --format="内容: %s")"
		echo "COMMIT_HASH=$(git show -s --date=short --format="hash: %H")"
	} >>"$GITHUB_ENV"

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
