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
# 工具函数
# =============================================

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
		log_error "参数不足，至少需要2个参数！用法: $0 <基准目录路径> <目标目录1> [目标目录2 ...]" >&2
		return 1
	fi

	_base_dir="$1"

	_match_list=$(mktemp)
	find_matching_dirs "$@" >"$_match_list"

	if [ ! -s "$_match_list" ]; then
		log_info "没有找到匹配的目录，无需更新。"
		rm -f "$_match_list"
		return 0
	fi

	log_info "开始处理覆盖任务..."

	while IFS= read -r _target_path; do
		[ -z "$_target_path" ] && continue

		_keyword=$(basename "$_target_path")
		_source_path="${_base_dir}/${_keyword}"

		_backup_path="${_target_path}.bak.$$"

		# --- 步骤 A: 备份原目录 ---
		if ! mv "$_target_path" "$_backup_path"; then
			log_warn "无法备份目标目录，跳过此项。"
			continue
		fi
		log_info "操作: 用 '$_source_path' 覆盖 '$_target_path'"
		if mv "$_source_path" "$_target_path"; then
			# 清理备份
			rm -rf "$_backup_path"
			log_info "覆盖成功。"
			continue
		fi
		log_warn "无法移动目标目录，恢复备份并清理源目录 $_source_path。"
		# 恢复备份目录
		mv "$_backup_path" "$_target_path"
		# 清理源目录，避免冲突
		rm -rf "$_source_path"
		return 0

	done <"$_match_list"

	rm -f "$_match_list"
	return 0
}

# =============================================
# 业务逻辑开始
# =============================================

# 更新feeds
update_feeds() {
	bak_dir="$GITHUB_WORKSPACE/$CUSTOM_BAK/feeds"
	target_dir="feeds"

	bak_dir=$(norm_path "$bak_dir")
	target_dir=$(norm_path "$target_dir")

	# 检查是否启用备份功能 并且备份目录存在
	if [ "${BAK_ENABLED:-0}" -eq "1" ] && [ -d "$bak_dir" ]; then
		log_info "feeds备份存在，恢复备份 $bak_dir 到当前目录"
		mkdir -p "$bak_dir"
		mkdir -p "$target_dir"
		rsync -aq --delete "$bak_dir/" "$target_dir/"
	fi
	log_info "更新feeds..."
	./scripts/feeds update -a
	# 检查是否启用备份功能
	if [ "${BAK_ENABLED:-0}" -eq "1" ]; then
		log_info "feeds备份，备份 feeds 到 $bak_dir"
		mkdir -p "$bak_dir"
		mkdir -p "$target_dir"
		# 只备份 feeds 目录下第一层目录，不备份 .tmp 文件目录
		rsync -aq --delete --exclude='/*.tmp/' --include='/*/' --exclude='/*' "$target_dir/" "$bak_dir/"
	fi
	return 0
}

# 安装feeds
install_feeds() {
	log_info "安装feeds..."
	./scripts/feeds install -a
	return 0
}

# 更新package
update_package() {
	community_dir="package/community"
	clone_repo "https://github.com/kenzok8/openwrt-packages" "$community_dir/kenzo"
	clone_repo "https://github.com/kenzok8/small" "$community_dir/small"

	log_info "删除出错插件"
	# luci-app-fchomo: small feed 中此插件编译报错，等待上游修复后可移除此行
	rm -rf "$community_dir"/small/luci-app-fchomo
	# luci-app-eqos: kenzo feed 中此插件与官方 luci-app-eqos 冲突导致编译报错，等待上游修复后可移除此行
	# rm -rf "$community_dir"/kenzo/luci-app-eqos

	log_info "覆盖原始package目录"
	update_matching_dirs "$community_dir/kenzo" "feeds"
	update_matching_dirs "$community_dir/small" "feeds"

	log_info "更新package完成"
	return 0
}

# 更新golang
update_golang() {
	golang_dir="feeds/packages/lang/golang"
	golang_dir_tmp="$golang_dir.tmp"
	custom_golang_bak="$CUSTOM_BAK/golang"
	# 确保目标目录存在
	mkdir -p "$golang_dir"
	# 备份当前golang目录
	mv "$golang_dir" "$golang_dir_tmp"
	# 检查备份目录是否存在
	if [ "${BAK_ENABLED:-0}" -eq "1" ] && [ -d "$custom_golang_bak" ]; then
		log_info "golang 备份存在，恢复备份 $custom_golang_bak 到 $golang_dir"
		mkdir -p "$custom_golang_bak"
		mkdir -p "$golang_dir"
		rsync -aq --delete "$custom_golang_bak/" "$golang_dir/"
		log_info "golang 备份恢复完成"
		return 0
	fi
	log_info "更新golang..."
	git clone https://github.com/kenzok8/golang -b 1.26 "$golang_dir" || {
		log_warn "更新golang失败,恢复原始版本"
		mv "$golang_dir_tmp" "$golang_dir"
		return 0
	}
	rm -rf "$golang_dir_tmp"
	if [ "${BAK_ENABLED:-0}" -eq "1" ]; then
		log_info "golang 备份，备份 $golang_dir 到 $custom_golang_bak"
		mkdir -p "$custom_golang_bak"
		mkdir -p "$golang_dir"
		rsync -aq --delete "$golang_dir/" "$custom_golang_bak/"
		log_info "golang 备份完成"
	fi
	return 0

}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	# 添加自定义Feeds
	update_feeds
	update_package
	update_golang
	install_feeds

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
