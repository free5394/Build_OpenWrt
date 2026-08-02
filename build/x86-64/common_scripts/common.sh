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

# 耗时统计包装器
time_it() {
	# 1. 记录起始时间
	start_time=$(date +%s.%N)

	# 2. 执行传入的函数及参数
	"$@"

	# 3. 记录结束时间
	end_time=$(date +%s.%N)

	# 4. 计算总耗时（秒，取整）
	elapsed_sec=$(awk "BEGIN {print int($end_time - $start_time)}")

	# 5. 计算时、分、秒
	hours=$((elapsed_sec / 3600))
	mins=$(((elapsed_sec % 3600) / 60))
	secs=$((elapsed_sec % 60))

	# 6. 按阶梯格式化耗时字符串
	if [ "$hours" -gt 0 ]; then
		# 超过 1 小时：1h 30m 12s
		formatted_time="${hours}h ${mins}m ${secs}s"
	elif [ "$mins" -gt 0 ]; then
		# 不满 1 小时但超过 1 分钟：45m 13s
		formatted_time="${mins}m ${secs}s"
	else
		# 不满 1 分钟：15s
		formatted_time="${secs}s"
	fi

	# 7. 使用 printf 代替 echo 输出
	printf "[TIME] '%s' 执行耗时: %s\n" "$*" "$formatted_time"
	return 0
}

# ------------------------------------------------------------------------------
# 环境能力检测（全局执行一次，避免在函数调用时重复探测）
# ------------------------------------------------------------------------------
if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
	_NORM_PATH_HAS_REALPATH=1
else
	_NORM_PATH_HAS_REALPATH=0
fi

# ------------------------------------------------------------------------------
# 路径规范化函数 (POSIX /bin/sh 兼容)
# ------------------------------------------------------------------------------
norm_path() {
	# 0. 参数校验：若未传参，默认返回当前目录绝对路径
	path_in="${1:-.}"

	# 1. 优先分支：使用系统原生的 GNU realpath -m (效率最高，支持软链接解析)
	if [ "$_NORM_PATH_HAS_REALPATH" -eq 1 ]; then
		realpath -m "$path_in"
		return 0
	fi

	# 2. 保底分支：纯 POSIX Shell 手动计算绝对路径与清洗
	# 2.1 确保起点为绝对路径
	case "$path_in" in
	/*) cur_path="$path_in" ;;
	*) cur_path="$(pwd)/$path_in" ;;
	esac

	# 2.2 规范化斜杠：去掉结尾斜杠，将多个连续的 /// 替换为单斜杠 /
	while :; do
		case "$cur_path" in
		*//*) cur_path=$(printf '%s\n' "$cur_path" | sed 's#//#/#g') ;;
		?*/) cur_path="${cur_path%/}" ;;
		*) break ;;
		esac
	done

	# 2.3 逐段解析路径，处理 . 与 .. 目录折叠
	old_ifs="$IFS"
	IFS="/"
	set -- $cur_path
	IFS="$old_ifs"

	out_path=""
	for seg in "$@"; do
		case "$seg" in
		"" | ".")
			# 忽略多余的空段或当前目录标记 .
			continue
			;;
		"..")
			# 遇到 .. 剥离最后一层路径（退回上一级）
			out_path="${out_path%/*}"
			;;
		*)
			# 正常目录段追加
			out_path="$out_path/$seg"
			;;
		esac
	done

	# 2.4 输出结果：若为根目录则为 /，否则输出拼接好的路径
	printf '%s\n' "${out_path:-/}"
	return 0
}

# ==============================================================================
# 子函数 1: 查找基准目录下的直接子目录名称
# 参数: $1 - 基准目录路径
# 输出: 匹配子目录列表（每行一个目录路径）
# ==============================================================================
find_sub_dirs() {
	_base_dir="$1"

	if [ ! -d "$_base_dir" ]; then
		printf "错误: 基准目录 %s 不存在或不是有效的目录！\n" "$_base_dir" >&2
		return 1
	fi

	for _full_path in "$_base_dir"/*; do
		if [ -d "$_full_path" ]; then
			_dir_name="${_full_path##*/}"
			printf "%s\n" "$_dir_name"
		fi
	done
}

# ==============================================================================
# 子函数 2: 在单个目标目录下查找匹配项 （最多深入到第3层级）
# 参数: $1 - 目标目录路径
#       $2... - 关键字列表（通过参数或外部传递）
# ==============================================================================
search_single_target() {
	_target_dir="$1"
	_kw_file="$2"

	if [ ! -d "$_target_dir" ]; then
		printf "警告: 目标目录 '%s' 不存在，已跳过。\n" "$_target_dir" >&2
		return 1
	fi

	find "$_target_dir" -mindepth 1 -maxdepth 3 -type d 2>/dev/null | awk -F/ '
        BEGIN { 
            while ((getline line < ARGV[1]) > 0) {
                kw[line] = 1
            }
            close(ARGV[1])
            ARGV[1] = ""
        }
        {
            if ($NF in kw) {
                print $0
            }
        }
    ' "$_kw_file" -
}

# ==============================================================================
# 子函数 3: 查找所有匹配目录
# 参数: $1 - 基准目录路径
#       $2及后续 - 目标目录路径列表
# ==============================================================================
find_matching_dirs() {
	if [ $# -lt 2 ]; then
		echo "错误: 参数不足！" >&2
		echo "用法: $0 <基准目录路径> <目标目录1> [目标目录2 ...]" >&2
		return 1
	fi

	_base_dir="$1"
	shift

	if [ ! -d "$_base_dir" ]; then
		echo "错误: 基准目录 '$_base_dir' 不存在或不是有效的目录！" >&2
		return 1
	fi

	_tmp_sub_dirs=$(mktemp)
	find_sub_dirs "$_base_dir" >"$_tmp_sub_dirs"
	_ret=$?

	if [ $_ret -ne 0 ]; then
		rm -f "$_tmp_sub_dirs"
		return 1
	fi

	if [ ! -s "$_tmp_sub_dirs" ]; then
		rm -f "$_tmp_sub_dirs"
		return 0
	fi

	for _target in "$@"; do
		search_single_target "$_target" "$_tmp_sub_dirs"
	done

	rm -f "$_tmp_sub_dirs"
}

# ==============================================================================
# 子函数 4: 覆盖匹配的目录 (支持回滚，成功后删除源文件)
# ==============================================================================
update_matching_dirs() {
	if [ $# -lt 2 ]; then
		echo "错误: 参数不足！" >&2
		echo "用法: $0 <基准目录路径> <目标目录1> [目标目录2 ...]" >&2
		return 1
	fi

	_base_dir="$1"

	_match_list=$(mktemp)
	find_matching_dirs "$@" >"$_match_list"

	if [ ! -s "$_match_list" ]; then
		echo "提示: 没有找到匹配的目录，无需更新。"
		rm -f "$_match_list"
		return 0
	fi

	echo "开始处理覆盖任务..."

	while IFS= read -r _target_path; do
		[ -z "$_target_path" ] && continue

		_keyword=$(basename "$_target_path")
		_source_path="${_base_dir}/${_keyword}"

		echo "--------------------------------------------------"
		echo "操作: 用 '$_source_path' 覆盖 '$_target_path'"

		_backup_path="${_target_path}.bak.$$"

		# --- 步骤 A: 备份原目录 ---
		if ! mv "$_target_path" "$_backup_path"; then
			echo "错误: 无法备份目标目录，跳过此项。" >&2
			continue
		fi
		if mv "$_source_path" "$_target_path"; then
			# 清理备份
			rm -rf "$_backup_path"
			echo "操作:覆盖成功。"
			continue
		fi
		echo "警告: 无法移动目标目录，恢复备份并清理源目录 $_source_path。" >&2
		# 恢复备份目录
		mv "$_backup_path" "$_target_path"
		# 清理源目录，避免冲突
		rm -rf "$_source_path"
		return 0

	done <"$_match_list"

	rm -f "$_match_list"
	return 0
}

build_script_info "$@"
