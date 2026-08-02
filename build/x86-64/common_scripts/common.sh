#!/bin/sh
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
	if [ "${LOG_SILENT:-0}" -eq "1" ]; then
		printf '========= %s 脚本开始加载 ============\n' "$script_fullname"
		printf '目录: %s\n' "$script_dir"
		printf '父目录: %s\n' "$script_parent_dir"
		printf '全名: %s\n' "$script_fullname"
		printf '名称: %s\n' "$script_name"
		printf '日志文件: %s\n' "$LOG_FILE"
		printf '========= %s 脚本结束加载 ============\n' "$script_fullname"
	fi

}

# =============================================
# 日志文件路径
# =============================================
: "${LOG_FILE:=./logs/$(cur_script_name).log}"

# =============================================
# 统一日志输出重定向（追加模式，按需启用）
# =============================================
mkdir -p "$(dirname -- "$LOG_FILE")"
# exec >>"$LOG_FILE" 2>&1

build_script_info "$@"
