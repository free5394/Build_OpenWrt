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

# 全局变量：上传目录路径（由 main 设置，供 trap 清理使用）
_CLEANUP_DEST_DIR=""

# 清理函数：脚本异常退出时删除未完成的上传目录，避免残留半成品产物
_cleanup_on_exit() {
	_exit_code=$?
	# 仅在异常退出且上传目录已设置时清理
	if [ "$_exit_code" -ne 0 ] && [ -n "$_CLEANUP_DEST_DIR" ] && [ -d "$_CLEANUP_DEST_DIR" ]; then
		log_warn "脚本异常退出（code=$_exit_code），清理未完成的上传目录: $_CLEANUP_DEST_DIR"
		rm -rf "$_CLEANUP_DEST_DIR" || true
	fi
}
trap _cleanup_on_exit EXIT

cp_img() {
	log_info "cp_img 开始执行"
	# 参数校验
	if [ $# -ne 2 ] && [ $# -ne 3 ]; then
		log_error "错误：参数数量只能为 2 或 3，当前为 $#"
		log_info "用法：cp_img <基准目录> <目标目录> <名称后缀>"
		return 1
	fi

	src_dir="$1"
	dest_dir="$2"
	name_suffix="${3:-}"
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
	return 0
}

compress_logs() {
	log_info "compress_logs 开始执行"
	# 参数校验
	if [ $# -ne 1 ] && [ $# -ne 2 ]; then
		log_error "错误：参数数量只能为 1 或 2，当前为 $#"
		log_info "用法：compress_logs <目标目录> <名称后缀（可选）>"
		return 1
	fi
	dest_dir="$1"
	name_suffix="${2:-}"
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
	log_file="$dest_dir/logs.tar.gz"
	if [ -n "$name_suffix" ]; then
		log_file="$dest_dir/logs-$name_suffix.tar.gz"
	fi
	# 压缩日志目录（不用 -v 避免CI日志冗长；V=sc 已在 build_common.sh 中配置）
	log_info "压缩日志目录 $logs_dir"
	tar -czf "$log_file" "$logs_dir" || {
		log_warn "日志压缩失败，继续上传"
		return 1
	}
	log_info "compress_logs 执行完成"
	return 0
}

# 校验关键环境变量
verify_params() {
	if [ -z "$GITHUB_WORKSPACE" ] || [ -z "$UPLOAD_DIR" ]; then
		log_error "缺少必要参数: GITHUB_WORKSPACE UPLOAD_DIR"
		return 1
	fi
	if [ ! -d "$GITHUB_WORKSPACE" ]; then
		log_warn "工作空间目录 $GITHUB_WORKSPACE 不存在，无文件可处理。"
		return 1
	fi
	return 0
}

# 为上传目录中的所有文件生成 sha256sums 校验文件
generate_checksums() {
	dest_dir="$1"
	if [ -z "$dest_dir" ] || [ ! -d "$dest_dir" ]; then
		log_warn "目标目录不存在，跳过 sha256sums 生成"
		return 0
	fi
	checksum_file="$dest_dir/sha256sums"
	# 在目标目录内执行，使校验文件中只含文件名（不含路径），便于用户验证
	(
		cd "$dest_dir" || exit 1
		# 对除 sha256sums 自身外的所有文件计算校验值
		find . -type f ! -name "sha256sums" -print0 | sort -z | xargs -0 sha256sum
	) >"$checksum_file"
	log_info "已生成 sha256sums 校验文件: $checksum_file"
	return 0
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	verify_params "$@" || exit 1

	# 定义路径
	src_dir="./bin/targets"
	dest_dir="$GITHUB_WORKSPACE/$UPLOAD_DIR"
	# 设置清理目标，供 EXIT trap 在异常退出时使用
	_CLEANUP_DEST_DIR="$dest_dir"

	cp_img "$src_dir" "$dest_dir" "$NAME_SUFFIX"

	compress_logs "$dest_dir" "$NAME_SUFFIX" || true

	generate_checksums "$dest_dir"

	# 全部步骤成功完成，取消清理 trap 避免误删产物
	trap - EXIT
	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
