#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（BusyBox ash 不支持时静默忽略）
set -o pipefail 2>/dev/null || true

# 保存脚本名以供提示
SCRIPT_NAME="$(basename "$0")"
log_file="/tmp/uci-defaults.log"

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
exec >>"$log_file" 2>&1

# =============================================
# 业务逻辑开始
# =============================================
log() {
	echo "[$(date '+%H:%M:%S')] $*"
}

# 首次启动探针：仅当 distfeeds.list 已含 PKU 镜像且不再含旧 vsean 源时视为已完成
is_first_boot() {
	local f=/etc/apk/repositories.d/distfeeds.list
	[ -f "$f" ] || return 1
	grep -q "mirrors.pku.edu.cn" "$f" || return 1
	! grep -q "mirrors.vsean.net" "$f"
}

is_first_boot || { log "[$SCRIPT_NAME] 已生效，跳过"; exit 0; }

echo "脚本开始执行 - $(date)"

sed -i '/kenzo\|small/d' /etc/apk/repositories.d/distfeeds.list

sed -i 's/mirrors\.vsean\.net/mirrors.pku.edu.cn/g' /etc/apk/repositories.d/distfeeds.list

# 检查关键词是否已删除
grep -Hn "kenzo\|small" /etc/apk/repositories.d/distfeeds.list || echo "无匹配行（删除成功）"

# 检查镜像源是否替换完成
grep "mirrors.pku.edu.cn" /etc/apk/repositories.d/distfeeds.list || echo "镜像源替换失败"

echo "设置完成"
exit 0
