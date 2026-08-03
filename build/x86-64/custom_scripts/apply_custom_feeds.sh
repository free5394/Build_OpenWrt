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
# 业务逻辑开始
# =============================================

# 克隆Git仓库到指定目录
# 参数1: 仓库URL（必选） 参数2: 目标目录（必选） 参数3: 分支名（可选）
clone_repo() {
	repo_url="$1"
	target_dir="$2"
	branch="$3"

	if [ -z "$repo_url" ] || [ -z "$target_dir" ]; then
		log_error "缺少必要参数:%s  <仓库URL> <目标目录>" "$0"
		return 1
	fi

	target_dir="${target_dir%/}"
	custom_repo_bak="$CUSTOM_BAK/${target_dir##*/}"
	# 检查备份目录是否存在
	if [ "${BAK_ENABLED:-0}" -eq "1" ] && [ -d "$custom_repo_bak" ]; then
		log_info "仓库备份存在，恢复备份 $custom_repo_bak 到 $target_dir"
		mkdir -p "$custom_repo_bak"
		mkdir -p "$target_dir"
		rsync -aq --delete "$custom_repo_bak/" "$target_dir/"
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
	if [ "${BAK_ENABLED:-0}" -eq "1" ]; then
		log_info "仓库备份，备份 $target_dir 到 $custom_repo_bak"
		mkdir -p "$custom_repo_bak"
		mkdir -p "$target_dir"
		rsync -aq --delete "$target_dir/" "$custom_repo_bak/"
	fi
	log_info "克隆仓库 $repo_url 到 $target_dir 完成"
	return 0
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

# 更新feeds
update_feeds() {
	custom_feeds_bak="$CUSTOM_BAK/feeds"
	target_dir="feeds"
	# 检查是否启用备份功能 并且备份目录存在
	if [ "${BAK_ENABLED:-0}" -eq "1" ] && [ -d "$custom_feeds_bak" ]; then
		log_info "feeds备份存在，恢复备份 $custom_feeds_bak 到当前目录"
		mkdir -p "$custom_feeds_bak"
		mkdir -p "$target_dir"
		rsync -aq --delete "$custom_feeds_bak/" "$target_dir/"
	fi
	log_info "更新feeds..."
	./scripts/feeds update -a
	# 检查是否启用备份功能
	if [ "${BAK_ENABLED:-0}" -eq "1" ]; then
		log_info "feeds备份，备份 feeds 到 $custom_feeds_bak"
		mkdir -p "$custom_feeds_bak"
		mkdir -p "$target_dir"
		# 只备份 feeds 目录下第一层目录，不备份 .tmp 文件目录
		rsync -aq --delete --exclude='/*.tmp/' --include='/*/' --exclude='/*' "$target_dir/" "$custom_feeds_bak/"
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
