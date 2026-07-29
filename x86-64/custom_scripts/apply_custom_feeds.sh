#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（BusyBox ash 不支持时静默忽略）
set -o pipefail 2>/dev/null || true

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
log_info "脚本开始执行 - $(date)"

# 示例命令1：正常执行
log_info "当前工作目录: $(pwd)"

# 查找目录
find_dir() {
	dir="$1"
	name="$2"
	find "$dir" -maxdepth 3 -type d -name "$name" -print -quit 2>/dev/null
}

# 插入自定义Feeds
add_feed() {
	feed_line="$1"
	insert_line="${2:-\$a}"

	# 已存在则跳过
	if grep -qF "$feed_line" feeds.conf.default; then
		log_info "[跳过] 已存在: $feed_line"
		return
	fi

	sed -i "${insert_line} $feed_line" feeds.conf.default
	log_info "[新增] $feed_line"
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
		git clone --depth 1 -b "$branch" "$repo_url" "$target_dir" 2>/dev/null
	else
		git clone --depth 1 "$repo_url" "$target_dir" 2>/dev/null
	fi

}

# 功能：扫描基准目录的直接子目录（忽略所有隐藏目录），在目标目录中递归查找匹配项（最多3层深度）并自动删除
# 用法：./script.sh <基准目录A> <目标目录1> [目标目录2 ...]
# 说明：最大递归深度固定为3层（目标目录=0层），删除操作无确认环节
del_matching_dirs() {
	# 参数校验
	if [ $# -lt 2 ]; then
		log_error "参数数量不足"
		log_error "用法：$SCRIPT_NAME <基准目录A> <目标目录1> [目标目录2 ...]"
		exit 1
	fi

	BASE_DIR="$1"
	shift # 现在 "$@" 是所有的目标目录（可含空格）

	# ---------- 路径规范化（若有 realpath 则使用，否则保留原路径） ----------
	if command -v realpath >/dev/null 2>&1; then
		# 规范化基准目录
		BASE_DIR=$(realpath -m "$BASE_DIR") || {
			log_error "无法解析基准目录 '$BASE_DIR'"
			exit 1
		}

		# 保存原始目标目录（使用换行分隔，假设路径不含换行符，OpenWrt 环境满足）
		ORIG_TARGETS=$(printf '%s\n' "$@")

		# 清空位置参数，逐个规范化并重新构建 "$@"
		set --
		oldIFS="$IFS"
		IFS='
'
		for dir in $ORIG_TARGETS; do
			norm=$(realpath -m "$dir") || {
				log_error "无法解析目标目录 '$dir'"
				exit 1
			}
			set -- "$@" "$norm"
		done
		IFS="$oldIFS"
		# 此时 "$@" 包含所有规范化后的目标目录
	else
		log_warn "未找到 realpath，跳过路径规范化，脚本将使用原始路径"
		# "$@" 已经是原始目标目录，保持不变
	fi

	# 检查基准目录是否存在
	if [ ! -d "$BASE_DIR" ]; then
		log_error "基准目录 '$BASE_DIR' 不存在或不是目录"
		exit 1
	fi

	# ---------- 获取基准目录的直接可见子目录名（忽略隐藏目录） ----------
	BASE_SUBDIRS=$(
		for subdir in "$BASE_DIR"/*/; do
			[ -d "$subdir" ] || continue
			name=$(basename "$subdir")
			case "$name" in .*) continue ;; esac
			printf '%s\n' "$name"
		done
	)
	# 去除可能出现的纯空行
	BASE_SUBDIRS=$(printf "%s" "$BASE_SUBDIRS" | sed '/^$/d')

	if [ -z "$BASE_SUBDIRS" ]; then
		log_warn "基准目录 '$BASE_DIR' 中没有有效直接子目录（已忽略隐藏目录），无需处理"
		exit 0
	fi

	# ---------- 显示基准子目录 ----------
	log_info "=== 基准目录 '$BASE_DIR' 的有效直接子目录 ==="
	printf "%s" "$BASE_SUBDIRS" | sed 's/^/  /'
	log_info "======================================"

	# ---------- 创建临时文件保存 find 输出（避免管道子 shell 导致变量丢失） ----------
	tmpfile=$(mktemp) || {
		log_error "无法创建临时文件"
		exit 1
	}
	trap 'rm -f "$tmpfile"' EXIT

	# 搜索所有目标目录下深度 ≤3 的目录（此时 "$@" 正确包含所有目标目录）
	find "$@" -maxdepth 3 -type d >"$tmpfile" 2>/dev/null

	while IFS= read -r MATCH_PATH; do
		# 跳过排除路径（基准目录 + 所有目标目录）
		skip=0
		for exclude in "$BASE_DIR" "$@"; do
			if [ "$MATCH_PATH" = "$exclude" ]; then
				skip=1
				break
			fi
		done
		[ $skip -eq 1 ] && continue

		DIR_NAME=$(basename "$MATCH_PATH")
		# 跳过隐藏目录
		case "$DIR_NAME" in .*) continue ;; esac

		# 检查目录名是否在基准子目录集合中
		printf "%s" "$BASE_SUBDIRS" | grep -Fxq "$DIR_NAME" || continue

		# 自动删除匹配的目录
		log_info "自动删除匹配项: $MATCH_PATH (匹配基准子目录: '$DIR_NAME')"
		if rm -rf "$MATCH_PATH"; then
			log_info "  成功删除: $MATCH_PATH"
		else
			log_error "  删除失败: $MATCH_PATH (权限问题?)"
			exit 1
		fi
	done <"$tmpfile"

	log_info "=== 执行完成 ==="
	log_info "注意："
	log_info "  1. **删除操作无确认环节**，所有匹配项已自动删除"
	log_info "  2. 基准目录的所有隐藏子目录（以.开头）已被忽略"
	log_info "  3. 仅处理了深度≤3的匹配目录（目标目录=0层）"
}

# 添加自定义Feeds
add_custom_feeds() {
	# 添加自定义Feeds
	add_feed "src-git kenzo https://github.com/kenzok8/openwrt-packages" '1i'
	add_feed "src-git small https://github.com/kenzok8/small" '2i'

	log_info "更新feeds..."
	./scripts/feeds update -a

	log_info "删除出错插件"
	rm -rf feeds/small/luci-app-fchomo
	rm -rf feeds/kenzo/luci-app-eqos

	# echo "删除冲突的插件..."
	# rm -rf feeds/luci/applications/luci-app-mosdns
	# rm -rf feeds/packages/net/{alist,adguardhome,mosdns,xray*,v2ray*,sing*,smartdns}
	# rm -rf feeds/packages/utils/v2dat

	log_info "删除冲突的插件..."
	del_matching_dirs feeds/kenzo feeds/luci feeds/packages feeds/routing feeds/telephony feeds/video
	del_matching_dirs feeds/small feeds/luci feeds/packages feeds/routing feeds/telephony feeds/video

	log_info "安装golang..."
	rm -rf feeds/packages/lang/golang
	git clone https://github.com/kenzok8/golang -b 1.26 feeds/packages/lang/golang

	log_info "安装feeds..."
	./scripts/feeds install -a
}

# 主函数
main() {
	# 添加自定义Feeds
	add_custom_feeds
}

# 调用主函数
main "$@"
