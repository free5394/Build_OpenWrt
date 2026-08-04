#!/bin/sh
# 防止直接执行此脚本，确保它是被 source 的
case "$0" in
*common.sh)
	echo "This is a library, do not run directly." >&2
	exit 1
	;;
esac

# 如果已经加载过，直接返回，不再重复解析
[ -n "$_SCRIPT_COMMON_LOADED" ] && return 0
_SCRIPT_COMMON_LOADED=1

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
	path_in="$1"
	cur_path=""

	if [ -z "$path_in" ]; then
		log_error "参数错误: 缺少必要参数:%s  <路径>" "$0"
		return 2
	fi

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

# ------------------------------------------------------------------------------
# 克隆Git仓库到指定目录
# 参数1: 仓库URL（必选） 参数2: 目标目录（必选） 参数3: 分支名（可选）
# ------------------------------------------------------------------------------
clone_repo() {
	repo_url="$1"
	target_dir="$2"
	branch="$3"

	if [ -z "$repo_url" ] || [ -z "$target_dir" ]; then
		log_error "缺少必要参数:%s  <仓库URL> <目标目录>" "$0"
		return 1
	fi
	target_dir="${target_dir%/}"
	bak_dir="${GITHUB_WORKSPACE}/${CUSTOM_BAK}/${target_dir##*/}"
	# 规范化路径
	bak_dir=$(norm_path "$bak_dir")
	target_dir=$(norm_path "$target_dir")
	log_info "克隆仓库 $repo_url 到 $target_dir"
	# 检查备份目录是否存在
	if [ "${BAK_ENABLED:-0}" -eq 1 ] && [ -d "$bak_dir" ]; then
		log_info "仓库备份存在，恢复备份 $bak_dir 到 $target_dir"
		mkdir -p "$bak_dir" "$target_dir"
		rsync -aq --delete "$bak_dir/" "$target_dir/"
		return 0
	fi

	if [ -n "$branch" ]; then
		git clone --depth 1 -b "$branch" "$repo_url" "$target_dir" || {
			log_error "克隆失败: $repo_url (分支: $branch)"
			return 1
		}
	else
		git clone --depth 1 "$repo_url" "$target_dir" || {
			log_error "克隆失败: $repo_url"
			return 1
		}
	fi
	if [ "${BAK_ENABLED:-0}" -eq 1 ]; then
		log_info "仓库备份，备份 $target_dir 到 $bak_dir"
		mkdir -p "$bak_dir" "$target_dir"
		rsync -aq --delete "$target_dir/" "$bak_dir/"
	fi
	log_info "克隆仓库 $repo_url 到 $target_dir 完成"
	return 0
}
