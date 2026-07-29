#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（BusyBox ash 不支持时静默忽略）
set -o pipefail 2>/dev/null || true

# 保存脚本名以供提示
SCRIPT_NAME="$(basename "$0")"
log_file="./logs/$SCRIPT_NAME.log"

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
# exec >"$log_file" 2>&1

# =============================================
# 业务逻辑开始
# =============================================
echo "脚本开始执行 - $(date)"

# 示例命令1：正常执行
echo "当前工作目录: $(pwd)"

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
		echo "[跳过] 已存在: $feed_line"
		return
	fi

	sed -i "${insert_line} $feed_line" feeds.conf.default
	echo "[新增] $feed_line"
}

# 克隆Git仓库到指定目录
# 参数1: 仓库URL（必选） 参数2: 分支名（可选） 参数3: 目标目录（必选）
clone_repo() {
	repo_url="$1"
	branch="$2"
	target_dir="$3"

	if [ -z "$repo_url" ] || [ -z "$target_dir" ]; then
		echo "[错误] 缺少必要参数: clone_repo <仓库URL> [分支] <目标目录>"
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
		printf "错误：参数数量不足\n"
		printf "用法：%s <基准目录A> <目标目录1> [目标目录2 ...]\n" "$SCRIPT_NAME"
		exit 1
	fi

	BASE_DIR="$1"
	shift # 现在 "$@" 是所有的目标目录（可含空格）

	# ---------- 路径规范化（若有 realpath 则使用，否则保留原路径） ----------
	if command -v realpath >/dev/null 2>&1; then
		# 规范化基准目录
		BASE_DIR=$(realpath -m "$BASE_DIR") || {
			printf "错误：无法解析基准目录 '%s'\n" "$BASE_DIR" >&2
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
				printf "错误：无法解析目标目录 '%s'\n" "$dir" >&2
				exit 1
			}
			set -- "$@" "$norm"
		done
		IFS="$oldIFS"
		# 此时 "$@" 包含所有规范化后的目标目录
	else
		printf "警告：未找到 realpath，跳过路径规范化，脚本将使用原始路径\n" >&2
		# "$@" 已经是原始目标目录，保持不变
	fi

	# 检查基准目录是否存在
	if [ ! -d "$BASE_DIR" ]; then
		printf "错误：基准目录 '%s' 不存在或不是目录\n" "$BASE_DIR" >&2
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
		printf "警告：基准目录 '%s' 中没有有效直接子目录（已忽略隐藏目录），无需处理\n" "$BASE_DIR"
		exit 0
	fi

	# ---------- 显示基准子目录 ----------
	printf "=== 基准目录 '%s' 的有效直接子目录 ===\n" "$BASE_DIR"
	printf "%s" "$BASE_SUBDIRS" | sed 's/^/  /'
	printf "======================================\n"

	# ---------- 创建临时文件保存 find 输出（避免管道子 shell 导致变量丢失） ----------
	tmpfile=$(mktemp) || {
		printf "错误：无法创建临时文件\n" >&2
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
		printf "自动删除匹配项: %s (匹配基准子目录: '%s')\n" "$MATCH_PATH" "$DIR_NAME"
		if rm -rf "$MATCH_PATH"; then
			printf "  成功删除: %s\n" "$MATCH_PATH"
		else
			printf "  删除失败: %s (权限问题?)\n" "$MATCH_PATH" >&2
			exit 1
		fi
	done <"$tmpfile"

	printf "\n=== 执行完成 ===\n"
	printf "注意：\n"
	printf "  1. **删除操作无确认环节**，所有匹配项已自动删除\n"
	printf "  2. 基准目录的所有隐藏子目录（以.开头）已被忽略\n"
	printf "  3. 仅处理了深度≤3的匹配目录（目标目录=0层）\n"
}

# 添加自定义Feeds
add_custom_feeds() {
	# 添加自定义Feeds
	add_feed "src-git kenzo https://github.com/kenzok8/openwrt-packages" '1i'
	add_feed "src-git small https://github.com/kenzok8/small" '2i'

	echo "更新feeds..."
	./scripts/feeds update -a

	# echo "删除冲突的插件..."
	# rm -rf feeds/luci/applications/luci-app-mosdns
	# rm -rf feeds/packages/net/{alist,adguardhome,mosdns,xray*,v2ray*,sing*,smartdns}
	# rm -rf feeds/packages/utils/v2dat

	echo "删除冲突的插件..."
	del_matching_dirs feeds/kenzo feeds/luci feeds/packages feeds/routing feeds/telephony feeds/video
	del_matching_dirs feeds/small feeds/luci feeds/packages feeds/routing feeds/telephony feeds/video

	echo "删除出错插件"
	rm -rf feeds/small/luci-app-fchomo

	echo "安装golang..."
	rm -rf feeds/packages/lang/golang
	git clone https://github.com/kenzok8/golang -b 1.26 feeds/packages/lang/golang

	echo "安装feeds..."
	./scripts/feeds install -a
}

# 主函数
main() {
	# 添加自定义Feeds
	add_custom_feeds
}

# 调用主函数
main "$@"
