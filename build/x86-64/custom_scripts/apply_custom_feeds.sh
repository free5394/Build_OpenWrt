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

	custom_repo_bak="$CUSTOM_BAK/${target_dir##*/}"
	# 检查备份目录是否存在
	if [ "${BAK_ENABLED:-0}" -eq "1" ] && [ -d "$custom_repo_bak" ]; then
		log_info "仓库备份存在，恢复备份 $custom_repo_bak 到 $target_dir"
		mkdir -p "$target_dir"
		cp -rf "$custom_repo_bak" "$target_dir"
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
		cp -rf "$target_dir" "$custom_repo_bak"
	fi
	log_info "克隆仓库 $repo_url 到 $target_dir 完成"
	return 0
}

# 更新feeds
update_feeds() {
	custom_feeds_bak="$CUSTOM_BAK/feeds"
	# 检查是否启用备份功能 并且备份目录存在
	if [ "${BAK_ENABLED:-0}" -eq "1" ] && [ -d "$custom_feeds_bak" ]; then
		log_info "feeds备份存在，恢复备份 $custom_feeds_bak 到当前目录"
		cp -rf "$custom_feeds_bak" .
	fi
	log_info "更新feeds..."
	./scripts/feeds update -a
	# 检查是否启用备份功能
	if [ "${BAK_ENABLED:-0}" -eq "1" ]; then
		log_info "feeds备份，备份 feeds 到 $custom_feeds_bak"
		rm -rf "$CUSTOM_BAK/feeds/" && mkdir -p "$CUSTOM_BAK/feeds/"
		# 查找 feeds 目录下第一层（不含以 .tmp 结尾）的目录，并复制到 bak 目录
		find feeds -mindepth 1 -maxdepth 1 -type d ! -name "*.tmp" -exec cp -rf {} "$CUSTOM_BAK/feeds/" \;
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

	# log_info "删除出错插件"
	# # luci-app-fchomo: small feed 中此插件编译报错，等待上游修复后可移除此行
	# rm -rf feeds/small/luci-app-fchomo
	# # luci-app-eqos: kenzo feed 中此插件与官方 luci-app-eqos 冲突导致编译报错，等待上游修复后可移除此行
	# rm -rf feeds/kenzo/luci-app-eqos

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
		cp -rf "$custom_golang_bak" "$(dirname "$golang_dir")/" || {
			log_warn "golang备份恢复失败，恢复原始版本"
			# 恢复原始版本
			mv "$golang_dir_tmp" "$golang_dir"
			return 0
		}
		rm -rf "$golang_dir_tmp"
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
		rm -rf "$custom_golang_bak" && mkdir -p "$custom_golang_bak"
		cp -rf "$golang_dir" "$custom_golang_bak"
		log_info "golang 备份完成"
	fi
	return 0

}

# patch feeds
patch_feeds() {
	log_info "删除出错插件"
	# luci-app-fchomo: small feed 中此插件编译报错，等待上游修复后可移除此行
	rm -rf feeds/small/luci-app-fchomo
	# luci-app-eqos: kenzo feed 中此插件与官方 luci-app-eqos 冲突导致编译报错，等待上游修复后可移除此行
	rm -rf feeds/kenzo/luci-app-eqos

	# echo "删除冲突的插件..."
	# rm -rf feeds/luci/applications/luci-app-mosdns
	# rm -rf feeds/packages/net/{alist,adguardhome,mosdns,xray*,v2ray*,sing*,smartdns}
	# rm -rf feeds/packages/utils/v2dat

	log_info "删除冲突的插件..."
	del_matching_dirs feeds/kenzo feeds/luci feeds/packages feeds/routing feeds/telephony feeds/video || log_warn "del_matching_dirs(kenzo) 部分失败，继续"
	del_matching_dirs feeds/small feeds/luci feeds/packages feeds/routing feeds/telephony feeds/video || log_warn "del_matching_dirs(small) 部分失败，继续"

	update_golang
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
