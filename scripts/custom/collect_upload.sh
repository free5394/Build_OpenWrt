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
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/logger.sh || {
	printf '错误: 无法加载日志模块 logger.sh\n' >&2
	exit 1
}

# =============================================
# 引入公共模块（强制依赖，最佳实践）
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../common_scripts/common.sh || {
	printf '错误: 无法加载公共模块 common.sh\n' >&2
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
		log_warn "脚本异常退出（code=%s），清理未完成的上传目录: %s" "$_exit_code" "$_CLEANUP_DEST_DIR"
		rm -rf "$_CLEANUP_DEST_DIR" || true
	fi
}
trap _cleanup_on_exit EXIT

# 上传镜像
cp_img() {
	# 参数校验
	if [ $# -ne 2 ] && [ $# -ne 3 ]; then
		log_error "参数错误！用法：%s <基准目录> <目标目录> <名称后缀（可选）>" "$0"
		return 2
	fi

	src_dir="$1"
	dest_dir="$2"
	name_suffix="${3:-}"
	if [ -z "$src_dir" ] || [ -z "$dest_dir" ]; then
		log_error "缺少必要参数！用法： %s <基准目录> <目标目录> <名称后缀（可选）>" "$0"
		return 2
	fi

	# 检查源目录是否存在
	if [ ! -d "$src_dir" ]; then
		log_warn "源目录 %s 不存在，无文件可处理。" "$src_dir"
		return 0
	fi

	# 创建目标目录（若不存在）
	mkdir -p "$dest_dir"

	# 处理名称后缀
	if [ -z "$name_suffix" ]; then
		log_info "后缀为空，直接移动文件至 %s" "$dest_dir"

		# 使用 -exec ... + 批量移动，高效且避免命令行长度限制
		find "$src_dir" -type f -name "*wrt*.img.gz" -exec mv -f {} "$dest_dir/" +

		log_info "%s 执行完成" "$0"
		return 0
	fi
	log_info "后缀非空，将重命名文件并移动至 %s" "$dest_dir"

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
	return 0
}

# 压缩目录
compress_dir() {
	# 参数校验
	if [ $# -lt 2 ]; then
		log_error "参数错误！用法：%s <压缩目录> <目标目录> <名称后缀（可选）>" "$0"
		return 2
	fi
	src_dir="$1"
	dest_dir="$2"
	name_suffix="${3:-}"
	if [ -z "$src_dir" ] || [ -z "$dest_dir" ]; then
		log_error "缺少必要参数！用法： %s <压缩目录> <目标目录> <名称后缀（可选）>" "$0"
		return 2
	fi
	if [ ! -d "$src_dir" ] || [ ! -d "$dest_dir" ]; then
		log_error "<压缩目录>( %s ) 或者 <目标目录>( %s ) 不存在" "$src_dir" "$dest_dir"
		return 2
	fi
	# 1. 获取 src_dir 的父目录: /home/user/build
	parent_dir=$(dirname "$src_dir")
	# 2. 获取 src_dir 的最后一层目录名: artifacts
	base_name=$(basename "$src_dir")
	# 创建目标目录（若不存在）
	mkdir -p "$dest_dir"
	compress_file="$dest_dir/$base_name.tar.gz"
	if [ -n "$name_suffix" ]; then
		compress_file="$dest_dir/$base_name-$name_suffix.tar.gz"
	fi
	# 压缩目录（不用 -v 避免CI日志冗长；V=sc 已在 build_common.sh 中配置）
	log_info "压缩目录 %s 到 %s" "$src_dir" "$compress_file"
	# 3. 执行压缩
	# -C "$parent_dir" : 告诉 tar 先进入父目录
	# "$base_name"     : 告诉 tar 只打包当前目录下的 artifacts 文件夹
	tar -czf "$compress_file" -C "$parent_dir" "$base_name" || {
		log_warn "压缩失败，继续上传"
		return 1
	}
	return 0
}

# 校验关键环境变量
verify_params() {
	if [ -z "$GITHUB_WORKSPACE" ]; then
		log_error "缺少必环境变量: GITHUB_WORKSPACE"
		return 2
	fi
	if [ -z "$UPLOAD_DIR" ]; then
		log_error "缺少必环境变量: UPLOAD_DIR"
		return 2
	fi
	if [ -z "$LOG_DIR" ]; then
		log_error "缺少必环境变量: LOG_DIR"
		return 2
	fi
	if [ -z "$CUSTOM_CONFIG" ]; then
		log_error "缺少必环境变量: CUSTOM_CONFIG"
		return 2
	fi
	if [ ! -d "$GITHUB_WORKSPACE" ]; then
		log_warn "工作空间目录 %s 不存在，无文件可处理。" "$GITHUB_WORKSPACE"
		return 2
	fi
	return 0
}

# 上传配置文件
cp_config() {
	# 参数校验
	if [ $# -ne 2 ]; then
		log_error "参数错误！用法：%s <配置文件> <目标目录>" "$0"
		return 2
	fi
	config_file="$1"
	dest_dir="$2"
	if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
		log_warn "配置文件 %s 不存在，跳过上传" "$config_file"
		return 1
	fi
	if [ -z "$dest_dir" ] || [ ! -d "$dest_dir" ]; then
		log_warn "目标目录 %s 不存在，跳过上传" "$dest_dir"
		return 1
	fi
	log_info "复制文件 %s 到 %s" "$config_file" "$dest_dir"
	cp -rf "$config_file" "$dest_dir"
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
	log_info "已生成 sha256sums 校验文件: %s" "$dest_dir/sha256sums"
	return 0
}

# 主函数
main() {
	log_info "%s 开始执行" "$0"

	verify_params "$@" || exit 1

	# 定义路径
	src_dir="./bin/targets"
	dest_dir="$GITHUB_WORKSPACE/$UPLOAD_DIR"
	log_dir="$GITHUB_WORKSPACE/$LOG_DIR"
	# 设置清理目标，供 EXIT trap 在异常退出时使用
	_CLEANUP_DEST_DIR="$dest_dir"

	# 全名 带后缀
	file_name=$(basename "$CUSTOM_CONFIG")
	# 去除后缀
	name="${file_name%.*}"

	mkdir -p "$dest_dir" "$log_dir"
	cp_img "$src_dir" "$dest_dir" "$name" || log_warn "镜像上传失败，继续上传"
	compress_dir "$log_dir" "$dest_dir" "$name" || log_warn "日志压缩失败，继续上传"
	cp_config "$file_name" "$dest_dir" || log_warn "配置文件上传失败，继续上传"
	generate_checksums "$dest_dir" || log_warn "校验文件生成失败，继续上传"

	# 全部步骤成功完成，取消清理 trap 避免误删产物
	trap - EXIT
	log_info "%s 执行完成" "$0"
}

# 调用主函数
main "$@"
