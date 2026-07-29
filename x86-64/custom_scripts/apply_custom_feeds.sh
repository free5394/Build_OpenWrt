#!/bin/sh

# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（如 bash 环境）
if set -o | grep -q 'pipefail' 2>/dev/null; then
	set -o pipefail
fi

# =============================================
# 2. 日志目录创建与输出重定向
# =============================================
# mkdir -p ./logs
# exec >./logs/apply_custom_feeds.log 2>&1

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

# 添加自定义Feeds
add_custom_feeds() {
	# 添加自定义Feeds
	add_feed "src-git kenzo https://github.com/kenzok8/openwrt-packages" '1i'
	add_feed "src-git small https://github.com/kenzok8/small" '2i'

	echo "更新feeds..."
	./scripts/feeds update -a

	echo "删除冲突的插件..."
	rm -rf feeds/luci/applications/luci-app-mosdns
	rm -rf feeds/packages/net/{alist,adguardhome,mosdns,xray*,v2ray*,sing*,smartdns} feeds/packages/utils/v2dat feeds/packages/lang/golang

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
