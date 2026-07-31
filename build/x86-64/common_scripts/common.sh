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
# 脚本路径解析（绝对路径优先，含边界处理）
# =============================================
# 获取脚本所在目录，优先绝对路径，失败时回退到 dirname 相对路径
SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) ||
	SCRIPT_DIR=$(dirname -- "$0")

# 移除末尾斜杠，但保留根目录 '/' 不被清空
case "$SCRIPT_DIR" in
/) ;;
*/) SCRIPT_DIR=${SCRIPT_DIR%/} ;;
esac

# 脚本全名（含后缀），兼容 $0 为空的极端情况
SCRIPT_FULLNAME=${0##*/}
: "${SCRIPT_FULLNAME:=script}"

# 脚本名（不含后缀）
# 提取最后一个 '.' 之前的内容；如果提取结果为空（如 .bashrc），则保留原文件名
case "$SCRIPT_FULLNAME" in
*.*)
	SCRIPT_NAME="${SCRIPT_FULLNAME%.*}"
	# 防御隐藏文件（如 .bashrc）或仅有后缀名（如 .sh）被截断成空串
	[ -z "$SCRIPT_NAME" ] && SCRIPT_NAME="$SCRIPT_FULLNAME"
	;;
*)
	# 无后缀名（如 Makefile）
	SCRIPT_NAME="$SCRIPT_FULLNAME"
	;;
esac

# 父目录：截取最后一级路径之前的内容，覆盖绝对/相对/根目录等边界
case "$SCRIPT_DIR" in
/*/*) SCRIPT_PARENT_DIR=${SCRIPT_DIR%/*} ;; # 绝对路径且有父目录（如 /a/b → /a）
/*) SCRIPT_PARENT_DIR=/ ;;                  # 绝对路径在根目录下（如 /a → /）
*/*) SCRIPT_PARENT_DIR=${SCRIPT_DIR%/*} ;;  # 相对路径含斜杠（如 a/b → a）
*) SCRIPT_PARENT_DIR=. ;;                   # 相对路径无斜杠（如 a → .）
esac

# =============================================
# 日志文件路径
# =============================================
: "${LOG_FILE:=./logs/${SCRIPT_NAME}.log}"

# =============================================
# 统一日志输出重定向（追加模式，按需启用）
# =============================================
# mkdir -p "$(dirname -- "$LOG_FILE")"
# exec >>"$LOG_FILE" 2>&1

# 加载日志：设置 LOG_SILENT=1 可抑制（CI 环境推荐启用以减少噪声）
if [ -z "${LOG_SILENT:-}" ]; then
	printf '========= %s 脚本开始加载 ============\n' "$SCRIPT_FULLNAME"
	printf '父目录: %s\n' "$SCRIPT_PARENT_DIR"
	printf '全名: %s\n' "$SCRIPT_FULLNAME"
	printf '名称: %s\n' "$SCRIPT_NAME"
	printf '日志文件: %s\n' "$LOG_FILE"
	printf '========= %s 脚本结束加载 ============\n' "$SCRIPT_FULLNAME"
fi
