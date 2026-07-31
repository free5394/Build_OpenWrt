#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 安全地尝试开启 pipefail
if (set -o pipefail) 2>/dev/null; then
	set -o pipefail
fi

# 脚本全名（含后缀）
SCRIPT_FULLNAME="${0##*/}"
# 脚本名（不含后缀）
SCRIPT_NAME="${SCRIPT_FULLNAME%.*}"
# 日志文件路径
LOG_FILE="/tmp/$SCRIPT_NAME.log"

# =============================================
# 统一日志输出重定向（追加模式）
# =============================================
exec >"$LOG_FILE" 2>&1

# =============================================
# 业务变量
# =============================================
# 根密码
root_password="password"

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
	exit 1
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
set system.@system[0].timezone='CST-8'
set system.@system[0].zonename='Asia/Shanghai'
commit system
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
	sed -i 's|https://.*/releases/|https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/|g' "$DISTFEEDS" || {
		log "镜像源替换失败，回滚"
		cp "$DISTFEEDS_BAK" "$DISTFEEDS"
		return 0
	}

	# 验证：统计仍含 https:// 但未替换为清华镜像的行数，确认全部替换
	UNREPLACED=$(grep 'https://' "$DISTFEEDS" | grep -cv 'mirrors.tuna.tsinghua.edu.cn' || true)
	if [ "$UNREPLACED" -eq 0 ]; then
		log "仓库源修补完成（全部已替换）"
	else
		log "仓库源修补未达预期，剩余 $UNREPLACED 行未替换，详情请检查 $DISTFEEDS"
	fi
}

# 禁用 WAN口 IPv6
modify_wan_ipv6() {
	[ -n "$(uci -q get network.wan 2>/dev/null)" ] || {
		log "未检测到 wan 接口，跳过 wan 接口 IPv6 设置"
		return 0
	}
	uci batch <<EOF
set network.wan.ipv6='0'
set network.wan.sourcefilter='0'
set network.wan.delegate='0'
set network.wan.multipath='off'
commit network
EOF
	log "WAN口 IPv6 禁用完成"
}

# 配置wan6口的IPv6参数
modify_wan6_ipv6() {
	# 1. 检查 wan 接口是否存在，不存在则跳过后续配置
	if ! uci -q get network.wan >/dev/null 2>&1; then
		log "未检测到 wan 接口，跳过 wan6 接口 IPv6 配置"
		return 0
	fi

	# 2. 批量写入 wan6 口的 IPv6 配置并提交
	# 说明：batch 内部直接使用 set 指令，不需要加 uci 前缀和 -q 参数
	# 若 wan6 节点不存在，set network.wan6=interface 会自动创建
	uci batch <<EOF
set network.wan6=interface
set network.wan6.device='@wan'
set network.wan6.proto='dhcpv6'
set network.wan6.reqaddress='try'
set network.wan6.reqprefix='auto'
set network.wan6.norelease='1'
set network.wan6.multipath='off'
commit network
EOF
	log "wan6口IPv6配置修改完成"
}

# 修改WAN口为PPPoE
modify_wan_pppoe() {
	[ -n "$(uci -q get network.wan 2>/dev/null)" ] || {
		log "未检测到 wan 接口，跳过 PPPoE 配置"
		return 0
	}
	if [ -z "$pppoe_username" ] || [ -z "$pppoe_password" ]; then
		log "未配置 PPPoE 用户名或密码，跳过 PPPoE 配置"
		return 0
	fi
	uci set network.wan.proto='pppoe'
	uci set network.wan.username="$pppoe_username"
	uci set network.wan.password="$pppoe_password"
	uci commit network
	log "WAN口为PPPoE 配置完成"
}

main() {
	log "[$SCRIPT_NAME] 开始执行"

	modify_timezone
	modify_repositories
	modify_wan_pppoe
	modify_wan_ipv6
	modify_wan6_ipv6
	modify_root_password

	log "[$SCRIPT_NAME] 执行完成"
}

# 调用主函数
main "$@"
exit 0
