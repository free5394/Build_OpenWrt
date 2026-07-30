#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 安全地尝试开启 pipefail
if (set -o pipefail) 2>/dev/null; then
	set -o pipefail
	set -o | grep pipefail
fi

# 脚本全名（含后缀）
SCRIPT_FULLNAME="${0##*/}"
# 脚本名（不含后缀）
SCRIPT_NAME="${SCRIPT_FULLNAME%.*}"
# 日志文件路径
LOG_FILE="/tmp/$SCRIPT_NAME.log"

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
exec >"$LOG_FILE" 2>&1

# =============================================
# 业务变量
# =============================================
# 根密码
root_password=""

# PPPoE 用户名和密码
pppoe_username=""
pppoe_password=""

# =============================================
# 业务逻辑开始
# =============================================
log() {
	echo "[$(date '+%H:%M:%S')] $*"
}

die() {
	log "错误: $*"
}

# 修改root 密码
modify_root_password() {
	if [ -n "$root_password" ]; then
		(
			echo "$root_password"
			sleep 1
			echo "$root_password"
		) | passwd root >/dev/null
	fi
}

# 修改系统时区为东八区（上海）
modify_timezone() {
	uci batch <<EOF
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system
EOF
	log "时区修改完成"
}

# 修补仓库源
modify_repositories() {
	DISTFEEDS="/etc/apk/repositories.d/distfeeds.list"
	DISTFEEDS_BAK="$DISTFEEDS.bak"

	# 文件不存在兜底：避免 sed 对不存在文件返回非零
	if [ ! -f "$DISTFEEDS" ]; then
		log "未找到 $DISTFEEDS，跳过仓库源修补"
		return 0
	fi

	# 备份以便失败回滚
	cp -f "$DISTFEEDS" "$DISTFEEDS_BAK" || {
		log "备份 $DISTFEEDS 失败"
		return 0
	}

	# 删除 kenzo/small 源（BusyBox sed BRE 下用 ; 分隔更稳）
	sed -i '/kenzo/d; /small/d' "$DISTFEEDS" || {
		log "删除 kenzo/small 失败，回滚"
		cp "$DISTFEEDS_BAK" "$DISTFEEDS"
		return 0
	}

	# 替换镜像源
	sed -i 's/mirrors\.vsean\.net/mirrors.pku.edu.cn/g' "$DISTFEEDS" || {
		log "镜像源替换失败，回滚"
		cp "$DISTFEEDS_BAK" "$DISTFEEDS"
		return 0
	}

	# 验证：旧域名不存在 AND 新域名存在
	if ! grep -q "mirrors.vsean.net" "$DISTFEEDS" && grep -q "mirrors.pku.edu.cn" "$DISTFEEDS"; then
		log "仓库源修补完成"
	else
		log "仓库源修补未达预期，详情请检查 $DISTFEEDS"
	fi
}

# 修改WAN口为PPPoE
modify_wan_pppoe() {
	if [ -z "$pppoe_username" ] || [ -z "$pppoe_password" ]; then
		log "未配置 PPPoE 用户名或密码，跳过 PPPoE 配置"
		return 0
	fi
	[ -n "$(uci -q get network.wan 2>/dev/null)" ] || {
		log "未检测到 network.wan，跳过 PPPoE 配置"
		return 0
	}
	uci -q set network.wan.proto=pppoe
	uci -q set network.wan.username="$pppoe_username"
	uci -q set network.wan.password="$pppoe_password"
	# 禁用 IPv6
	uci -q set network.wan.ipv6='0'
	uci -q set network.wan.sourcefilter='0'
	uci -q set network.wan.delegate='0'
	uci commit network

	log "WAN口为PPPoE 配置完成"
}

main() {
	log "[$SCRIPT_NAME] 开始执行"

	modify_timezone
	modify_repositories
	modify_wan_pppoe
	modify_root_password

	log "[$SCRIPT_NAME] 执行完成"
}

# 调用主函数
main "$@"
exit 0
