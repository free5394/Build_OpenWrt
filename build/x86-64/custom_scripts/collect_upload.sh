#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 安全地尝试开启 pipefail
if (set -o pipefail) 2>/dev/null; then
	set -o pipefail
	set -o | grep pipefail
fi

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

# 可选：动态调整日志级别
LOG_LEVEL=20 # 显示日志，包括INFO、WARN、ERROR

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

cp_img() {
	log_info "cp_img 开始执行"
	# 参数校验
	if [ $# -ne 2 ] && [ $# -ne 3 ]; then
		log_error "错误：参数数量只能为 2 或 3，当前为 %d\n" "$#"
		log_info "用法：%s <基准目录> <目标目录> <名称后缀>\n" "cp_img"
		return 1
	fi

	src_dir="$1"
	dest_dir="$2"
	name_suffix="$3"
	if [ -z "$src_dir" ] || [ -z "$dest_dir" ]; then
		log_error "缺少必要参数: cp_img <基准目录> <目标目录> <名称后缀（可选）>"
		return 1
	fi

	# 检查源目录是否存在
	if [ ! -d "$src_dir" ]; then
		log_warn "源目录 $src_dir 不存在，无文件可处理。"
		log_info "cp_img 执行完成"
		return 0
	fi

	# 创建目标目录（若不存在）
	mkdir -p "$dest_dir"

	# 处理名称后缀
	if [ -z "$name_suffix" ]; then
		log_info "NAME_SUFFIX 为空，直接移动文件至 $dest_dir"

		# 使用 -exec ... + 批量移动，高效且避免命令行长度限制
		find "$src_dir" -type f -name "*wrt*.img.gz" -exec mv -f {} "$dest_dir/" +

		log_info "cp_img 执行完成"
		return 0
	fi
	log_info "NAME_SUFFIX 非空，将重命名文件并移动至 $dest_dir"

	# 使用 find + sh -c 批量处理，传入目标目录和后缀作为参数
	find "$src_dir" -type f -name "*wrt*.img.gz" -exec sh -c '
        dest="$1"
        suffix="$2"
        shift 2
        for f in "$@"; do
            base="${f%.img.gz}"                 # 去除 .img.gz 后缀
            filename=$(basename "$base")        # 取得文件名（不含路径）
            newname="${filename}-${suffix}.img.gz"
            mv -f "$f" "$dest/$newname"
            echo "已移动并重命名：$f -> $dest/$newname"
        done
    ' sh "$dest_dir" "$name_suffix" {} +
	log_info "cp_img 执行完成"
}

compress_logs() {
	log_info "compress_logs 开始执行"
	# 参数校验
	if [ $# -ne 1 ]; then
		log_error "错误：参数数量只能为 1，当前为 %d\n" "$#"
		log_info "用法：%s <目标目录>\n" "compress_logs"
		return 1
	fi
	dest_dir="$1"
	if [ -z "$dest_dir" ]; then
		log_error "缺少必要参数: compress_logs <目标目录>"
		return 1
	fi

	logs_dir="./logs"
	if [ ! -d "$logs_dir" ]; then
		log_warn "日志目录 $logs_dir 不存在，无文件可处理。"
		return 0
	fi

	# 创建目标目录（若不存在）
	mkdir -p "$dest_dir"

	log_info "压缩日志目录 $logs_dir"
	tar -czvf "$dest_dir/logs.tar.gz" "$logs_dir"
	log_info "compress_logs 执行完成"
}

# 校验关键环境变量
verify_params() {
	if [ -z "$GITHUB_WORKSPACE" ] || [ -z "$UPLOAD_DIR" ]; then
		log_error "缺少必要参数: GITHUB_WORKSPACE UPLOAD_DIR"
		exit 1
	fi
	if [ ! -d "$GITHUB_WORKSPACE" ]; then
		log_warn "工作空间目录 $GITHUB_WORKSPACE 不存在，无文件可处理。"
		exit 1
	fi
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	verify_params "$@"

	# 定义路径
	src_dir="./bin/targets"
	dest_dir="$GITHUB_WORKSPACE/$UPLOAD_DIR"

	cp_img "$src_dir" "$dest_dir" "$NAME_SUFFIX"

	compress_logs "$dest_dir"

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
