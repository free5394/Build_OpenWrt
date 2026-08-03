#!/bin/sh
# =============================================
# OpenWrt uci-defaults 初始化脚本（改进版）
# 说明：该脚本在首次启动时运行，用于配置系统基础项。
# 下方业务变量均为可选，留空表示跳过对应配置步骤。
# =============================================

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

# 检查 uci 命令是否存在（致命错误，无法继续则退出）
command -v uci >/dev/null 2>&1 || {
	echo "uci not found"
	exit 1
}

# =============================================
# 业务变量（按需修改）
# =============================================
# 根密码（已加密的哈希字符串，若为空则跳过密码修改）
root_password='$6$eAx0vGeWLH768Ag.$4jKvsP1IeRyDhVnGnLD87XtGL.yTtf9chz3OAvXOMNSi.cFEGvywcrlL5vmC3URhyGUcKboWHpcUJK.o.cYP0.'

# PPPoE 用户名和密码（均非空时才会配置 PPPoE）
pppoe_username=""
pppoe_password=""

# LuCI 默认主题（如 argon、bootstrap，留空则跳过）
default_theme=""

# LAN口IP地址（纯 IPv4，例如 192.168.1.1，会自动追加 /24 掩码）
lan_ip_addr=""

# =============================================
# 日志函数
# =============================================
log() {
	msg="[$(date '+%H:%M:%S')] $*"
	echo "$msg"
	logger -t "$SCRIPT_NAME" "$msg" || true
	return 0
}

# =============================================
# 通用 uci 提交安全封装（用于非 network 配置）
# =============================================
uci_commit_safe() {
	config="$1"
	if uci commit "$config"; then
		log "配置 $config 提交成功"
		return 0
	fi
	log "配置 $config 提交失败，回滚 $config 配置"
	uci revert "$config"
	return 1

}

# =============================================
# 修改 root 密码（增加备份恢复）
# =============================================
modify_root_password() {
	if [ -z "$root_password" ]; then
		log "未配置 root 密码，跳过 root 密码修改"
		return 0
	fi
	cp -f /etc/shadow /etc/shadow.bak 2>/dev/null || {
		log "无法备份 /etc/shadow，放弃修改密码"
		return 1
	}
	sed "s|^root:[^:]*:|root:${root_password}:|" /etc/shadow >/etc/shadow.tmp && mv /etc/shadow.tmp /etc/shadow || {
		log "root 密码修改失败，尝试恢复备份"
		cp -f /etc/shadow.bak /etc/shadow
		return 1
	}
	rm -f /etc/shadow.bak
	log "root 密码修改完成"
	return 0
}

# =============================================
# 修改系统时区为东八区（上海）
# =============================================
modify_timezone() {
	uci set system.@system[0].timezone='CST-8'
	uci set system.@system[0].zonename='Asia/Shanghai'
	uci_commit_safe system
	return $?
}

# =============================================
# 修改 LuCI 默认主题
# =============================================
modify_luci_theme() {
	if [ ! -f /etc/config/luci ]; then
		log "未检测到 LuCI 配置文件，跳过主题修改"
		return 0
	fi
	if [ -z "$default_theme" ]; then
		log "未配置 LuCI 默认主题，跳过主题修改"
		return 0
	fi
	uci set luci.main.mediaurlbase="/luci-static/${default_theme}"
	if uci_commit_safe luci; then
		# 安全清理 LuCI 缓存
		rm -f /tmp/luci-indexcache
		[ -d /tmp/luci-modulecache ] && rm -rf /tmp/luci-modulecache/*
		log "LuCI 默认主题已成功修改为: ${default_theme}"
		return 0
	fi
	return 1
}

# =============================================
# 修补仓库源（增强验证与严格回滚）
# =============================================
modify_repositories() {
	DISTFEEDS="/etc/apk/repositories.d/distfeeds.list"
	DISTFEEDS_BAK="$DISTFEEDS.bak"
	mirrors="mirrors.tuna.tsinghua.edu.cn"

	if [ ! -f "$DISTFEEDS" ]; then
		log "未找到 $DISTFEEDS，跳过仓库源修补"
		return 0
	fi
	cp -f "$DISTFEEDS" "$DISTFEEDS_BAK" || {
		log "备份 $DISTFEEDS 失败，放弃修改"
		return 0
	}
	# 替换镜像源（清华源）
	sed -i "s|https://.*/releases/|https://$mirrors/openwrt/releases/|g" "$DISTFEEDS" || {
		log "镜像源替换失败，回滚"
		cp -f "$DISTFEEDS_BAK" "$DISTFEEDS"
		return 1
	}
	# 验证：统计未替换的行（排除注释行，兼容 busybox grep）
	UNREPLACED=$(grep -v '^[[:space:]]*#' "$DISTFEEDS" | grep 'https://' | grep -c -v "$mirrors" 2>/dev/null || echo 0)
	if [ "$UNREPLACED" -eq 0 ]; then
		log "仓库源修补完成（全部已替换）"
		rm -f "$DISTFEEDS_BAK"
		return 0
	fi
	log "仓库源修补未达预期，剩余 $UNREPLACED 行未替换，回滚到原始文件"
	cp -f "$DISTFEEDS_BAK" "$DISTFEEDS"
	return 1
}

# =============================================
# 配置网络（强化校验）
# =============================================
modify_network() {
	need_commit=0
	# 修改 LAN口IP
	if [ -n "$lan_ip_addr" ]; then
		# 严格 IPv4 正则（0.0.0.0 ~ 255.255.255.255）
		ip_regex='^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
		if ! echo "$lan_ip_addr" | grep -Eq "$ip_regex"; then
			log "LAN口IP地址格式非法: '$lan_ip_addr'，跳过修改"
		else
			target_ip="${lan_ip_addr}"
			if [ "${target_ip#*/}" = "${target_ip}" ]; then
				target_ip="${target_ip}/24"
			fi
			uci -q del network.lan.netmask 2>/dev/null || true
			uci set network.lan.ipaddr="${target_ip}"
			log "已将 LAN 口 IP 设置为 ${target_ip}"
			need_commit=1
		fi
	else
		log "未配置 LAN口IP地址，跳过"
	fi

	if ! uci -q get network.wan >/dev/null 2>&1; then
		log "未检测到 wan 接口，跳过 wan 接口配置"
		if [ "$need_commit" -eq 1 ]; then
			uci_commit_safe "network" || return 1
		fi
		return 0
	fi

	# 禁用 wan 接口的 IPv6 配置
	uci set network.wan.ipv6='0'
	uci set network.wan.sourcefilter='0'
	uci set network.wan.delegate='0'

	device='@wan'
	if [ -n "$pppoe_username" ] && [ -n "$pppoe_password" ]; then
		uci set network.wan.proto='pppoe'
		uci set network.wan.username="$pppoe_username"
		uci set network.wan.password="$pppoe_password"
		device="pppoe-wan"
	fi

	# 配置 wan6 接口的 IPv6 参数
	uci set network.wan6=interface
	uci set network.wan6.device="$device"
	uci set network.wan6.proto='dhcpv6'
	uci set network.wan6.reqaddress='try'
	uci set network.wan6.reqprefix='auto'
	uci set network.wan6.norelease='1'

	uci_commit_safe "network" || return 1
	return 0
}

# =============================================
# 主函数：按顺序执行各模块，错误不中断
# =============================================
main() {
	log "[$SCRIPT_NAME] 开始执行"

	modify_timezone || log "配置时区失败，跳过"
	modify_repositories || log "配置仓库源失败，跳过"
	modify_network || log "配置网络失败，跳过"
	modify_luci_theme || log "配置主题失败，跳过"
	modify_root_password || log "配置根密码失败，跳过"

	log "[$SCRIPT_NAME] 执行完成"
}

main "$@"
exit 0
