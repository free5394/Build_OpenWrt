#!/bin/sh
#==================================================
# POSIX Shell 日志模块（严格兼容 sh/dash/ash）
# 使用方法： . ./logger.sh
#==================================================

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

# 脚本名（纯 shell 参数扩展，高效）
_LOGGER_SCRIPT_NAME="${0##*/}"

#----- 内部核心函数 ------------------------------------
_log() {
	_lvl_val=$1
	_lvl_name=$2
	_color=$3
	shift 3

	# 级别过滤
	if [ "$_lvl_val" -lt "${LOG_LEVEL}" ] 2>/dev/null; then
		return 0
	fi

	# 时间戳（不受 locale 干扰）
	_timestamp=$(LC_ALL=C date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

	# 输出（颜色用 %s 直接输出真实控制字符）
	printf "%s[%s] [%s] [%-5s] %s%s\n" \
		"$_color" \
		"$_timestamp" \
		"$_LOGGER_SCRIPT_NAME" \
		"$_lvl_name" \
		"$*" \
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
