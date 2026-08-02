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
# 根密码 （已加密）
root_password='$6$eAx0vGeWLH768Ag.$4jKvsP1IeRyDhVnGnLD87XtGL.yTtf9chz3OAvXOMNSi.cFEGvywcrlL5vmC3URhyGUcKboWHpcUJK.o.cYP0.'

# PPPoE 用户名和密码
pppoe_username=""
pppoe_password=""

# LuCI 默认主题 argon bootstrap
default_theme=""

# LAN口IP地址
lan_ip_addr=""

# =============================================
# 业务逻辑开始
# =============================================
log() {
	echo "[$(date '+%H:%M:%S')] $*"
	return 0
}

# 修改root 密码
modify_root_password() {
	if [ -z "$root_password" ]; then
		log "未配置 root 密码，跳过 root 密码修改"
		return 0
	fi
	sed -i "s|^root:[^:]*:|root:${root_password}:|" /etc/shadow || {
		log "root 密码修改失败"
		return 1
	}
	log "root 密码修改完成"
	return 0
}

# 修改系统时区为东八区（上海）
modify_timezone() {
	uci set system.@system[0].timezone='CST-8'
	uci set system.@system[0].zonename='Asia/Shanghai'
	uci commit system || {
		log "时区修改失败"
		return 1
	}
	log "时区修改完成"
	return 0
}

# ==========================================
# 修改 LuCI 默认主题
# ==========================================
modify_luci_theme() {
	# 1. 检查 LuCI 配置文件是否存在
	if [ ! -f /etc/config/luci ]; then
		log "未检测到 LuCI 配置文件 (/etc/config/luci)，跳过主题修改"
		return 0
	fi
	if [ -z "$default_theme" ]; then
		log "未配置 LuCI 默认主题，跳过主题修改"
		return 0
	fi

	# 2. 修改 UCI 配置
	uci set luci.main.mediaurlbase="/luci-static/${default_theme}"
	uci commit luci || {
		log "LuCI 主题提交失败"
		return 1
	}

	# 3. 安全清理 LuCI 缓存
	rm -f /tmp/luci-indexcache
	if [ -d /tmp/luci-modulecache ]; then
		rm -rf /tmp/luci-modulecache/*
	fi

	log "LuCI 默认主题已成功修改为: ${default_theme}"
	return 0
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
		return 1
	}

	# 删除 kenzo/small 源（BusyBox sed BRE 下用 ; 分隔更稳）
	sed -i '/kenzo/d; /small/d' "$DISTFEEDS" || {
		log "删除 kenzo/small 失败，回滚"
		cp -f "$DISTFEEDS_BAK" "$DISTFEEDS"
		return 1
	}

	# 替换镜像源
	sed -i 's|https://.*/releases/|https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/|g' "$DISTFEEDS" || {
		log "镜像源替换失败，回滚"
		cp -f "$DISTFEEDS_BAK" "$DISTFEEDS"
		return 1
	}

	# 验证：统计仍含 https:// 但未替换为清华镜像的行数，确认全部替换
	UNREPLACED=$(grep 'https://' "$DISTFEEDS" | grep -cv 'mirrors.tuna.tsinghua.edu.cn' || true)
	if [ "$UNREPLACED" -eq 0 ]; then
		log "仓库源修补完成（全部已替换）"
	else
		log "仓库源修补未达预期，剩余 $UNREPLACED 行未替换，详情请检查 $DISTFEEDS"
	fi
	return 0
}

# 修改LAN口IP（校验纯 IP，合法时按 CIDR /24 格式写入）
modify_lan_ip() {
	# 1. 检查变量是否为空
	if [ -z "$lan_ip_addr" ]; then
		log "未配置 LAN口IP地址，跳过 IP地址修改"
		return 0
	fi

	# 2. 正则校验是否为纯 IPv4 地址（如 192.168.1.1）
	ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
	if ! echo "$lan_ip_addr" | grep -Eq "$ip_regex"; then
		log "LAN口IP地址格式非法: '$lan_ip_addr'，跳过修改"
		return 0
	fi

	# 3. 如果变量本身没有带掩码，按注释要求自动追加 /24
	target_ip="${lan_ip_addr}"
	if [ "${target_ip#*/}" = "${target_ip}" ]; then
		target_ip="${target_ip}/24"
	fi

	# 4. 写入 UCI (删除旧 netmask，使用标准的 ipaddr CIDR 格式)
	uci del network.lan.netmask
	uci set network.lan.ipaddr="${target_ip}"
	uci commit network || {
		log "LAN口IP地址提交失败"
		return 1
	}
	log "LAN口IP地址已成功修改为: ${target_ip}"
	return 0
}

# 禁用 WAN口 IPv6
modify_wan_ipv6() {
	if ! uci -q get network.wan >/dev/null 2>&1; then
		log "未检测到 wan 接口，跳过 wan 接口 IPv6 设置"
		return 0
	fi
	uci set network.wan.ipv6='0'
	uci set network.wan.sourcefilter='0'
	uci set network.wan.delegate='0'
	uci commit network || {
		log "WAN口 IPv6 禁用提交失败"
		return 1
	}
	log "WAN口 IPv6 禁用完成"
	return 0
}

# 配置wan6口的IPv6参数
modify_wan6_ipv6() {
	# 1. 检查 wan 接口是否存在，不存在则跳过后续配置
	if ! uci -q get network.wan >/dev/null 2>&1; then
		log "未检测到 wan 接口，跳过 wan6 接口 IPv6 配置"
		return 0
	fi

	# 2. 写入 wan6 口的 IPv6 配置并提交
	# 若 wan6 节点不存在，set network.wan6=interface 会自动创建
	uci set network.wan6=interface
	uci set network.wan6.device='@wan'
	uci set network.wan6.proto='dhcpv6'
	uci set network.wan6.reqaddress='try'
	uci set network.wan6.reqprefix='auto'
	uci set network.wan6.norelease='1'
	uci set network.wan6.multipath='off'
	uci commit network || {
		log "wan6口IPv6配置提交失败"
		return 1
	}
	log "wan6口IPv6配置修改完成"
	return 0
}

# 修改WAN口为PPPoE
modify_wan_pppoe() {
	if ! uci -q get network.wan >/dev/null 2>&1; then
		log "未检测到 wan 接口，跳过 PPPoE 配置"
		return 0
	fi
	if [ -z "$pppoe_username" ] || [ -z "$pppoe_password" ]; then
		log "未配置 PPPoE 用户名或密码，跳过 PPPoE 配置"
		return 0
	fi
	uci set network.wan.proto='pppoe'
	uci set network.wan.username="$pppoe_username"
	uci set network.wan.password="$pppoe_password"
	uci commit network || {
		log "WAN口 PPPoE 配置提交失败"
		return 1
	}
	log "WAN口为PPPoE 配置完成"
	return 0
}

main() {
	log "[$SCRIPT_NAME] 开始执行"

	modify_timezone || log "时区修改失败，跳过"
	modify_repositories || log "仓库源修补失败，跳过"
	modify_lan_ip || log "LAN口IP修改失败，跳过"
	modify_wan_pppoe || log "WAN口PPPoE配置失败，跳过"
	modify_wan_ipv6 || log "WAN口IPv6禁用失败，跳过"
	modify_wan6_ipv6 || log "wan6口IPv6配置失败，跳过"
	modify_luci_theme || log "LuCI主题修改失败，跳过"
	modify_root_password || log "root密码修改失败，跳过"

	log "[$SCRIPT_NAME] 执行完成"
}

# 调用主函数
main "$@"
exit 0
