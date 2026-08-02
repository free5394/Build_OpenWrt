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

# 插入自定义Feeds
add_feed() {
	feed_line="$1"
	insert_line="${2:-\$a}"

	# 已存在则跳过
	if grep -qF "$feed_line" feeds.conf.default; then
		log_info "[跳过] 已存在: $feed_line"
		return 0
	fi

	sed -i "${insert_line} $feed_line" feeds.conf.default || {
		log_error "插入 feed 失败: $feed_line"
		return 1
	}
	log_info "[新增] $feed_line"
	return 0
}

# 克隆Git仓库到指定目录
# 参数1: 仓库URL（必选） 参数2: 分支名（可选） 参数3: 目标目录（必选）
clone_repo() {
	repo_url="$1"
	branch="$2"
	target_dir="$3"

	if [ -z "$repo_url" ] || [ -z "$target_dir" ]; then
		log_error "缺少必要参数: clone_repo <仓库URL> [分支] <目标目录>"
		return 1
	fi

	if [ -n "$branch" ]; then
		git clone --depth 1 -b "$branch" "$repo_url" "$target_dir" || {
			log_error "克隆失败: $repo_url (分支: $branch)"
			return 1
		}
		return 0
	fi
	git clone --depth 1 "$repo_url" "$target_dir" || {
		log_error "克隆失败: $repo_url"
		return 1
	}
	return 0
}

# 路径规范化函数（兼容无 realpath -m 的环境）
norm_path() {
	if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
		realpath -m "$1"
	else
		# 退化为手动拼接绝对路径，兼容 BSD/macOS/部分 BusyBox
		case "$1" in
		/*) printf '%s\n' "$1" ;;
		*) printf '%s\n' "$(pwd)/$1" ;;
		esac
		return 0
	fi
}

# DM_DRY_RUN=1
# 功能：扫描基准目录的直接子目录（忽略所有隐藏目录），在目标目录中递归查找匹配项（最多3层深度）并自动删除
# 用法：del_matching_dirs <基准目录A> <目标目录1> [目标目录2 ...]
# 说明：最大递归深度固定为3层（目标目录=0层），删除操作无确认环节
# 可选行为：设置环境变量 DM_DRY_RUN=1 时，仅记录删除目标而不实际执行删除
del_matching_dirs() {
	# 参数校验
	if [ $# -lt 2 ]; then
		log_error "参数数量不足"
		log_error "用法：$SCRIPT_NAME <基准目录A> <目标目录1> [目标目录2 ...]"
		return 1
	fi

	BASE_DIR="$1"
	shift
	# 现在 "$@" 是所有的目标目录（可含空格）

	# ---------- 目标目录基本安全检查 ----------
	for d in "$@"; do
		case "$d" in
		/ | "")
			log_error "目标目录不能为根目录 '/' 或空字符串: '$d'"
			return 1
			;;
		esac
	done

	# ---------- 路径规范化（使用兼容性更好的 norm_path 函数） ----------
	BASE_DIR=$(norm_path "$BASE_DIR") || {
		log_error "无法解析基准目录 '$BASE_DIR'"
		return 1
	}

	# 保存原始目标目录（使用换行分隔，假设路径不含换行符）
	ORIG_TARGETS=$(printf '%s\n' "$@")
	# 清空位置参数，逐个规范化并重新构建 "$@"
	set --
	while IFS= read -r dir; do
		[ -z "$dir" ] && continue
		norm=$(norm_path "$dir") || {
			log_error "无法解析目标目录 '$dir'"
			return 1
		}
		set -- "$@" "$norm"
	done <<EOF
$ORIG_TARGETS
EOF
	# 此时 "$@" 包含所有规范化后的目标目录

	# 检查基准目录是否存在
	if [ ! -d "$BASE_DIR" ]; then
		log_error "基准目录 '$BASE_DIR' 不存在或不是目录"
		return 1
	fi

	# ---------- 可选：提前检查目标目录是否存在 ----------
	for d in "$@"; do
		if [ ! -d "$d" ]; then
			log_warn "目标目录 '$d' 不存在或不是目录，后续 find 可能忽略"
		fi
	done

	# ---------- 获取基准目录的直接可见子目录名（忽略隐藏目录） ----------
	BASE_SUBDIRS=$(
		for subdir in "$BASE_DIR"/*/; do
			[ -d "$subdir" ] || continue
			name=$(basename "$subdir")
			case "$name" in
			.*) continue ;;
			esac
			printf '%s\n' "$name"
		done
	)

	# 去除可能出现的纯空行
	BASE_SUBDIRS=$(printf "%s" "$BASE_SUBDIRS" | sed '/^$/d')

	if [ -z "$BASE_SUBDIRS" ]; then
		log_warn "基准目录 '$BASE_DIR' 中没有有效直接子目录（已忽略隐藏目录），无需处理"
		return 0
	fi

	# ---------- 显示基准子目录 ----------
	BASE_SUBDIRS_ONELINE=$(printf '%s' "$BASE_SUBDIRS" | tr '\n' ' ')
	log_debug "基准目录 '$BASE_DIR' 的有效直接子目录: $BASE_SUBDIRS_ONELINE"

	# ---------- 临时文件统一管理 ----------
	TMP_DIR=""
	cleanup() {
		# 防止重复清理或信号二次触发
		trap - EXIT INT TERM HUP
		[ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR" 2>/dev/null
	}

	TMP_DIR=$(mktemp -d) || {
		log_error "无法创建临时目录"
		return 1
	}
	base_list_file="$TMP_DIR/base.list"
	tmpfile="$TMP_DIR/find.out"
	matched_file="$TMP_DIR/matched.out"

	# 设置清理陷阱（单点集中管理，处理退出与中断信号）
	trap 'cleanup' EXIT INT TERM HUP

	# 将基准子目录列表写入临时文件
	printf '%s\n' "$BASE_SUBDIRS" >"$base_list_file"

	# 搜索所有目标目录下深度 ≤3 的目录
	# 使用 if 捕获 find 失败，避免 set -e 中止，同时记录警告
	if ! find "$@" -maxdepth 3 -type d >"$tmpfile" 2>/dev/null; then
		log_warn "find 命令执行失败，可能部分目标目录不存在或权限不足"
	fi

	if [ ! -s "$tmpfile" ]; then
		log_warn "find 未找到任何目录，可能所有目标目录均无效或为空"
		# 继续执行，后续 awk 处理空文件，正常退出
	fi

	# ---------- 使用 awk 一次性过滤出匹配的目录 ----------
	# 增加防御性处理：显式去尾部斜杠、使用 sub 取 basename（规避 $NF 空值问题）、提前过滤隐藏目录
	awk -F/ '
    NR==FNR { if($0!="") a[$0]; next }
    {
        path=$0; sub(/\/+$/,"",path);          # 去尾部斜杠
        n=path; sub(/^.*\//,"",n);             # 取 basename（不依赖 $NF）
        if (n in a && n !~ /^\./) print path;
    }' "$base_list_file" "$tmpfile" >"$matched_file" 2>/dev/null

	# ---------- 逐行处理匹配结果 ----------
	MATCH_CNT=0
	DEL_CNT=0
	while IFS= read -r MATCH_PATH; do
		[ -z "$MATCH_PATH" ] && continue

		# 硬护栏：拒绝删除根目录或异常短路径
		[ "$MATCH_PATH" = "/" ] && {
			log_error "拒绝删除根目录！"
			return 1
		}
		case "$MATCH_PATH" in
		/*/?*) ;; # 合法：至少两级深度，如 /data/sub
		*)
			log_error "路径异常: $MATCH_PATH"
			continue
			;;
		esac

		# 跳过排除路径（基准目录 + 所有目标目录），统一去除尾部斜杠
		skip=0
		for exclude in "$BASE_DIR" "$@"; do
			m="${MATCH_PATH%/}"
			e="${exclude%/}"
			if [ "$m" = "$e" ]; then
				skip=1
				break
			fi
		done
		[ $skip -eq 1 ] && continue

		DIR_NAME=$(basename "$MATCH_PATH")

		# 统计匹配数
		MATCH_CNT=$((MATCH_CNT + 1))

		# 自动删除匹配的目录（支持 dry-run）
		log_info "匹配项: $MATCH_PATH (匹配基准子目录: '$DIR_NAME')"
		if [ "${DM_DRY_RUN:-0}" = "1" ]; then
			log_info "  DRY-RUN: 跳过实际删除"
		else
			if rm -rf "$MATCH_PATH"; then
				DEL_CNT=$((DEL_CNT + 1))
				log_info "  成功删除: $MATCH_PATH"
			else
				log_error "  删除失败: $MATCH_PATH (权限问题?)"
				return 1
			fi
		fi
	done <"$matched_file"

	log_info "=== 执行完成：匹配 $MATCH_CNT 项，成功删除 $DEL_CNT 项 ==="
	return 0
}

# 更新feeds
update_feeds() {
	custom_feeds_bak="$CUSTOM_BAK/feeds"
	# 检查是否启用备份功能
	if [ "${BAK_ENABLED:-0}" -eq "1" ]; then
		# 检查备份目录是否存在
		if [ -d "$custom_feeds_bak" ]; then
			log_info "feeds 备份已存在，恢复备份"
			cp -rf "$custom_feeds_bak" .
			log_info "feeds 备份恢复完成"
		fi
		log_info "更新feeds..."
		./scripts/feeds update -a

		log_info "开始备份feeds..."
		rm -rf "$CUSTOM_BAK/feeds/" && mkdir -p "$CUSTOM_BAK/feeds/"
		# 查找 feeds 目录下第一层（不含以 .tmp 结尾）的目录，并复制到 bak 目录
		find feeds -mindepth 1 -maxdepth 1 -type d ! -name "*.tmp" -exec cp -rf {} "$CUSTOM_BAK/feeds/" \;
		log_info "feeds备份完成"
		return 0
	fi
	log_info "更新feeds..."
	./scripts/feeds update -a
	return 0
}

# 安装feeds
install_feeds() {
	log_info "安装feeds..."
	./scripts/feeds install -a
	return 0
}

# 添加自定义Feeds
add_custom_feeds() {
	add_feed "src-git kenzo https://github.com/kenzok8/openwrt-packages" '1i'
	add_feed "src-git small https://github.com/kenzok8/small" '2i'
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

	log_info "安装golang..."
	mv feeds/packages/lang/golang feeds/packages/lang/golang.bak
	git clone https://github.com/kenzok8/golang -b 1.26 feeds/packages/lang/golang || {
		log_error "安装golang失败,恢复原始版本"
		mv feeds/packages/lang/golang.bak feeds/packages/lang/golang
		return 1
	}
	return 0
}

# 主函数
main() {
	log_info "$SCRIPT_NAME 脚本开始执行"

	# 添加自定义Feeds
	add_custom_feeds
	update_feeds
	patch_feeds
	install_feeds

	log_info "$SCRIPT_NAME 脚本执行完成"
}

# 调用主函数
main "$@"
