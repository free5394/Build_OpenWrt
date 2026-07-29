#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（BusyBox ash 不支持时静默忽略）
set -o pipefail 2>/dev/null || true

# 脚本所在目录（绝对路径）
SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P) 2>/dev/null || SCRIPT_DIR=$(dirname -- "$0")
# 脚本全名（含后缀）
SCRIPT_FULLNAME="${0##*/}"
# 脚本名（不含后缀）
SCRIPT_NAME="${SCRIPT_FULLNAME%.*}"
# 日志文件路径
LOG_FILE="./logs/$SCRIPT_NAME.log"

# 引入日志模块（假设 logger.sh 在同目录下）
. "$SCRIPT_DIR"/logger.sh

# check logger.sh
log_debug "目录: $SCRIPT_DIR"
log_debug "全名: $SCRIPT_FULLNAME"
log_debug "名称: $SCRIPT_NAME"
log_debug "日志文件: $LOG_FILE"

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
# exec >"$LOG_FILE" 2>&1

# =============================================
# 业务逻辑开始
# =============================================

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	# 源仓库与分支
	SOURCE_REPO=$(basename "$OPENWRT_REPO")
	{
		log_info "SOURCE_REPO=$SOURCE_REPO"
		log_info "LITE_BRANCH=${OPENWRT_BRANCH#*-}"
	} >>"$GITHUB_ENV"

	# 平台架构
	TARGET_NAME=$(grep -oP "^CONFIG_TARGET_\K[a-z0-9]+(?==y)" .config)
	SUBTARGET_NAME=$(grep -oP "^CONFIG_TARGET_${TARGET_NAME}_\K[a-z0-9]+(?==y)" .config)
	DEVICE_TARGET="$TARGET_NAME-$SUBTARGET_NAME"
	{
		log_info "TARGET_NAME=$TARGET_NAME"
		log_info "SUBTARGET_NAME=$SUBTARGET_NAME"
		log_info "DEVICE_TARGET=$DEVICE_TARGET"
	} >>"$GITHUB_ENV"

	# 内核版本
	KERNEL=$(grep -oP 'KERNEL_PATCHVER:=\K[\d\.]+' "target/linux/$TARGET_NAME/Makefile")
	KERNEL_FILE="include/kernel-$KERNEL"
	[ -e "$KERNEL_FILE" ] || KERNEL_FILE="target/linux/generic/kernel-$KERNEL"
	KERNEL_VERSION=$(grep -oP 'LINUX_KERNEL_HASH-\K[\d\.]+' "$KERNEL_FILE")
	log_info "KERNEL_VERSION=$KERNEL_VERSION" >>"$GITHUB_ENV"

	# 源码更新信息
	{
		log_info "COMMIT_AUTHOR=$(git show -s --date=short --format="作者: %an")"
		log_info "COMMIT_DATE=$(git show -s --date=short --format="时间: %ci")"
		log_info "COMMIT_MESSAGE=$(git show -s --date=short --format="内容: %s")"
		log_info "COMMIT_HASH=$(git show -s --date=short --format="hash: %H")"
	} >>"$GITHUB_ENV"

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
