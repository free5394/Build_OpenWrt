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

DISTFEEDS="/etc/apk/repositories.d/distfeeds.list"
DISTFEEDS_BAK="/tmp/distfeeds.list.bak"

# 文件不存在兜底：避免 sed 对不存在文件返回非零
if [ ! -f "$DISTFEEDS" ]; then
	log "未找到 $DISTFEEDS，跳过仓库源修补"
	exit 0
fi

# 备份以便失败回滚
cp "$DISTFEEDS" "$DISTFEEDS_BAK" || { log "备份 $DISTFEEDS 失败"; exit 0; }

# 删除 kenzo/small 源（BusyBox sed BRE 下用 ; 分隔更稳）
sed -i '/kenzo/d; /small/d' "$DISTFEEDS" || {
	log "删除 kenzo/small 失败，回滚"
	cp "$DISTFEEDS_BAK" "$DISTFEEDS"
	exit 0
}

# 替换镜像源
sed -i 's/mirrors\.vsean\.net/mirrors.pku.edu.cn/g' "$DISTFEEDS" || {
	log "镜像源替换失败，回滚"
	cp "$DISTFEEDS_BAK" "$DISTFEEDS"
	exit 0
}

# 验证：旧域名不存在 AND 新域名存在
if ! grep -q "mirrors.vsean.net" "$DISTFEEDS" && grep -q "mirrors.pku.edu.cn" "$DISTFEEDS"; then
	log "仓库源修补完成"
else
	log "仓库源修补未达预期，详情请检查 $DISTFEEDS"
fi

echo "设置完成"
exit 0
