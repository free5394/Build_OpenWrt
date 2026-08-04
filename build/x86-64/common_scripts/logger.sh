#!/bin/sh
#==================================================
# POSIX Shell 日志模块（严格兼容 sh/dash/ash）
# 使用方法： . ./logger.sh
# 说明：提供日志记录功能，支持 DEBUG/INFO/WARN/ERROR 等级别。
# 日志级别：DEBUG=10, INFO=20, WARN=30, ERROR=40
# 日志级别默认 INFO=20
# 日志重定向：LOG_REDIRECTION_ENABLE=0/1 0 不启用， 1 启用
# 依赖：无外部依赖
#==================================================

# 防止直接执行此脚本，确保它是被 source 的
case "$0" in
*logger.sh)
	echo "This is a library, do not run directly." >&2
	exit 1
	;;
esac

# 如果已经加载过，直接返回，不再重复解析
[ -n "$_SCRIPT_LOGGER_LOADED" ] && return 0
_SCRIPT_LOGGER_LOADED=1

#----- 颜色生成（真正的 ESC 字符）----------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	ESC=$(printf '\033')
	COLOR_RESET="${ESC}[0m"
	COLOR_DEBUG="${ESC}[34m" # 蓝色
	COLOR_INFO="${ESC}[32m"  # 绿色
	COLOR_WARN="${ESC}[33m"  # 黄色
	COLOR_ERROR="${ESC}[31m" # 红色
else
	COLOR_RESET=''
	COLOR_DEBUG=''
	COLOR_INFO=''
	COLOR_WARN=''
	COLOR_ERROR=''
fi

#----- 日志级别定义 ------------------------------------
LOG_LEVEL_DEBUG=10
LOG_LEVEL_INFO=20
LOG_LEVEL_WARN=30
LOG_LEVEL_ERROR=40
: "${LOG_LEVEL:=20}" # 默认 INFO

: "${LOG_REDIRECTION_ENABLE:=0}" # 默认不启用重定向 0 不启用， 1 启用

# 脚本名（纯 shell 参数扩展，高效）
_LOGGER_SCRIPT_NAME="${0##*/}"

#----- 内部核心函数 ------------------------------------
_log() {
	_lvl_val=$1
	_lvl_name=$2
	_color=$3
	shift 3

	# 获取用户传入的格式字符串（第一个参数）
	_user_fmt="${1:-}"

	# 移除格式字符串，剩余参数保存在 $@ 中
	shift

	# 级别过滤
	if [ "$_lvl_val" -lt "${LOG_LEVEL}" ] 2>/dev/null; then
		return 0
	fi

	# 时间戳（不受 locale 干扰）
	_timestamp=$(LC_ALL=C date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

	# 输出：
	# 1. 将 ${_user_fmt} 直接嵌入 printf 的格式字符串位置。
	# 2. 将剩余的用户参数 "$@" 紧跟在前缀参数之后。
	# 3. 将颜色重置码 "$COLOR_RESET" 作为最后一个参数传入。
	# 注意：我们在格式串末尾追加 "%s" 用来对应 "$COLOR_RESET"，
	# 而用户的格式串 "${_user_fmt}" 会消耗掉 "$@" 中的参数。
	printf "%s[%s] [%s] [%-5s] ${_user_fmt}%s\n" \
		"$_color" \
		"$_timestamp" \
		"$_LOGGER_SCRIPT_NAME" \
		"$_lvl_name" \
		"$@" \
		"$COLOR_RESET"
	return 0
}

#----- 对外接口 ----------------------------------------
log_debug() { _log "$LOG_LEVEL_DEBUG" "DEBUG" "$COLOR_DEBUG" "$@"; }
log_info() { _log "$LOG_LEVEL_INFO" "INFO" "$COLOR_INFO" "$@"; }
log_warn() { _log "$LOG_LEVEL_WARN" "WARN" "$COLOR_WARN" "$@"; }
log_error() { _log "$LOG_LEVEL_ERROR" "ERROR" "$COLOR_ERROR" "$@"; }

#==================================================
# 使用示例（取消注释即可测试）
#==================================================
# . ./logger.sh
# LOG_LEVEL=10  # 显示所有日志（DEBUG=10）
# log_debug "开始执行脚本" 1
# log_info  "正在处理数据文件: input.txt" 2
# log_warn  "磁盘空间低于10%" 3
# log_error "无法连接数据库: timeout" 4
# log_error "无法连接数据库: timeout"
# log_error "无法连接数据库: timeout"
# log_error "无法连接数据库: timeout"

# =============================================
# 脚本路径解析（绝对路径优先，含边界处理）
# =============================================
cur_script_dir() {
	# 获取脚本所在目录，优先绝对路径，失败时回退到 dirname 相对路径
	script_dir=$(cd -P -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) ||
		script_dir=$(dirname -- "$0")

	# 移除末尾斜杠，但保留根目录 '/' 不被清空
	case "$script_dir" in
	/) ;;
	*/) script_dir=${script_dir%/} ;;
	esac
	printf '%s\n' "$script_dir"
}

# =============================================
# 脚本名（不含后缀）
# =============================================
cur_script_name() {
	# 脚本全名（含后缀），兼容 $0 为空的极端情况
	script_fullname=${0##*/}

	# 脚本名（不含后缀）
	# 提取最后一个 '.' 之前的内容；如果提取结果为空（如 .bashrc），则保留原文件名
	case "$script_fullname" in
	*.*)
		script_name="${script_fullname%.*}"
		# 防御隐藏文件（如 .bashrc）或仅有后缀名（如 .sh）被截断成空串
		[ -z "$script_name" ] && script_name="$script_fullname"
		;;
	*)
		# 无后缀名（如 Makefile）
		script_name="$script_fullname"
		;;
	esac
	printf '%s\n' "$script_name"
}

# =============================================
# 脚本所在目录的父目录（含边界处理）
# =============================================
cur_script_parent_dir() {
	# 脚本所在目录
	script_dir=$(cur_script_dir)

	# 父目录：截取最后一级路径之前的内容，覆盖绝对/相对/根目录等边界
	case "$script_dir" in
	/*/*) script_parent_dir=${script_dir%/*} ;; # 绝对路径且有父目录（如 /a/b → /a）
	/*) script_parent_dir=/ ;;                  # 绝对路径在根目录下（如 /a → /）
	*/*) script_parent_dir=${script_dir%/*} ;;  # 相对路径含斜杠（如 a/b → a）
	*) script_parent_dir=. ;;                   # 相对路径无斜杠（如 a → .）
	esac
	printf '%s\n' "$script_parent_dir"
}

# =============================================
# 日志文件路径
# =============================================
: "${LOG_DIR:=${GITHUB_WORKSPACE:-.}/logs}"
LOG_FILE="${LOG_DIR}/$(cur_script_name).log"

# =============================================
# 统一日志输出重定向（追加模式，按需启用）
# =============================================
if [ "$LOG_REDIRECTION_ENABLE" -eq 1 ]; then
	mkdir -p "$(dirname -- "$LOG_FILE")"
	exec exec >>"$LOG_FILE" 2>&1
fi

# =============================================
# 脚本加载信息
# =============================================
build_script_info() {
	# 脚本全名（含后缀），兼容 $0 为空的极端情况
	script_fullname=${0##*/}
	# 脚本名（不含后缀）
	script_name=$(cur_script_name)
	# 脚本所在目录
	script_dir=$(cur_script_dir)
	# 脚本所在目录的父目录（含边界处理）
	script_parent_dir=$(cur_script_parent_dir)

	# 加载日志：设置 LOG_SILENT=1 可抑制（CI 环境推荐启用以减少噪声）
	log_debug '========= %s 脚本开始加载 ============' "$script_fullname"
	log_debug '目录: %s' "$script_dir"
	log_debug '父目录: %s' "$script_parent_dir"
	log_debug '全名: %s' "$script_fullname"
	log_debug '名称: %s' "$script_name"
	log_debug '日志文件: %s' "$LOG_FILE"
	log_debug '========= %s 脚本结束加载 ============' "$script_fullname"

}

build_script_info "$@"

# log_debug "debug: %s %s %s %s" 1 2 3 4
# log_info "info: %s %s %s %s" 1 2 3 4
# log_warn "warn: %s %s %s %s" 1 2 3 4
# log_error "error: %s %s %s %s" 1 2 3 4
