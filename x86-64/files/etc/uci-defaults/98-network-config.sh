#!/bin/sh
# 98-network-config.sh - 网络接口自动检测与配置脚本
# 规则：单网口→LAN（旁路由 DHCP）；多网口→最后一个为WAN，其余为LAN

# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（BusyBox ash 不支持时静默忽略）
set -o pipefail 2>/dev/null || true

# 保存脚本名以供提示
SCRIPT_NAME="$(basename "$0")"
log_file="/tmp/$SCRIPT_NAME.log"

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
exec >>"$log_file" 2>&1

# =============================================
# 业务逻辑开始
# =============================================
echo "脚本开始执行 - $(date)"

log() {
	echo "[$(date '+%H:%M:%S')] $*"
}

die() {
	log "错误: $*"
	exit 1
}

# 首次启动探针：br-lan device section 存在且 ports 已配置视为已完成
is_first_boot() {
	local sec
	sec=$(uci -q show network |
		awk -F'.' '/^network\.@device\[[0-9]+\]\.name=br-lan$/ {print $2; exit}')
	[ -n "$sec" ] || return 1
	local ports
	ports=$(uci -q get "network.$sec.ports" 2>/dev/null)
	[ -n "$ports" ]
}

is_first_boot || {
	log "[$SCRIPT_NAME] 已生效，跳过"
	exit 0
}

# ============================================================
# 1. 检测所有物理网络接口
# ============================================================
get_physical_ifaces() {
	ifaces=""
	for iface in /sys/class/net/*; do
		[ -d "$iface" ] || continue
		name=$(basename "$iface")
		# 排除 lo、虚拟网桥、隧道等
		case "$name" in
		lo | br-* | tun* | tap* | wg* | ppp* | 6in4* | vxlan*) continue ;;
		esac
		# 仅保留 eth*/en* 开头的物理接口
		case "$name" in
		eth* | en*) ifaces="$ifaces $name" ;;
		esac
	done
	# 去首尾空格
	echo "$ifaces" | awk '{$1=$1};1'
}

# ============================================================
# 2. 获取接口数量
# ============================================================
count_ifaces() {
	echo "$1" | awk '{print NF}'
}

# ============================================================
# 3. 配置网络（单网口）
# ============================================================
configure_single() {
	iface="$1"
	log "单网口模式: $iface → LAN (DHCP 旁路由)"

	# 独立 device section：与 interface section 分离，避免 UCI 模型破坏
	uci set network.lan_dev=device
	uci set network.lan_dev.name='br-lan'
	uci set network.lan_dev.ports="$iface"

	# network.lan 保持 interface：旁路由通过 DHCP 上联
	uci set network.lan=interface
	uci set network.lan.device='br-lan'
	uci set network.lan.proto='dhcp'
	uci -q delete network.lan.ipaddr
	uci -q delete network.lan.netmask
	uci -q delete network.lan.gateway
	uci -q delete network.lan.dns
	uci commit network || die "UCI 提交失败"
}

# ============================================================
# 4. 配置网络（多网口）
# ============================================================

# 查找 br-lan device section 名；找不到返回非零
get_br_lan_device_section() {
	local sec
	sec=$(uci -q show network |
		awk -F'.' '/^network\.@device\[[0-9]+\]\.name=br-lan$/ {print $2; exit}')
	if [ -z "$sec" ]; then
		# 兜底：grep + head + awk 兼容 awk 不支持 \d+ 的实现
		sec=$(uci -q show network | grep -F ".name='br-lan'" | head -n1 | awk -F'.' '{print $2}')
	fi
	[ -n "$sec" ] || return 1
	echo "$sec"
}

configure_multi() {
	wan_if="$1"
	shift
	lan_ifs="$*"
	log "多网口模式: WAN=$wan_if, LAN=$lan_ifs"

	# 配置 WAN
	uci set network.wan=interface
	uci set network.wan.device="$wan_if"
	uci set network.wan.proto='dhcp'

	# 配置 WAN6
	uci set network.wan6=interface
	uci set network.wan6.device="$wan_if"
	uci set network.wan6.proto='dhcpv6'

	# 更新 br-lan 的端口
	section=$(get_br_lan_device_section) || die "未找到 br-lan 设备配置段"

	uci -q delete "network.$section.ports"
	for port in $lan_ifs; do
		uci add_list "network.$section.ports"="$port"
	done
	log "br-lan 端口已更新: $lan_ifs"

	# LAN 静态 IP（多网口传统路由；99 脚本可按 lan_ip_addr 覆盖）
	uci set network.lan.proto='static'
	uci set network.lan.netmask='255.255.255.0'
	uci set network.lan.ipaddr='192.168.100.1'
	log "默认管理地址: 192.168.100.1（99 脚本可覆盖）"

	uci commit network || die "UCI 提交失败"
}

# ============================================================
# 5. 验证配置
# ============================================================
verify_config() {
	log "--- 验证网络配置 ---"
	ok=1

	# 检查 LAN 是否已配置
	lan_proto=""
	lan_proto=$(uci -q get network.lan.proto 2>/dev/null)
	if [ -z "$lan_proto" ]; then
		log "验证失败: LAN 协议未设置"
		ok=0
	else
		log "LAN 协议: $lan_proto"
	fi

	# 多网口时检查 WAN
	wan_dev=$(uci -q get network.wan.device 2>/dev/null)
	if [ -n "$wan_dev" ]; then
		wan_proto=$(uci -q get network.wan.proto 2>/dev/null)
		log "WAN 设备: $wan_dev, 协议: $wan_proto"
	fi

	# 检查 br-lan 端口
	br_ports=$(uci -q show network | grep -F 'br-lan' | grep -F 'ports' || true)
	if [ -n "$br_ports" ]; then
		log "br-lan 端口配置: $br_ports"
	fi

	[ "$ok" -eq 1 ] && log "验证通过" || die "配置验证失败"
}

# ============================================================
# 主流程
# ============================================================
main() {
	log "========== 网络配置脚本开始 =========="

	ifnames=$(get_physical_ifaces)

	if [ -z "$ifnames" ]; then
		die "未检测到任何物理网络接口"
	fi

	count=$(count_ifaces "$ifnames")
	log "检测到物理接口 ($count): $ifnames"

	if [ "$count" -eq 1 ]; then
		configure_single "$ifnames"
	elif [ "$count" -gt 1 ]; then
		# 最后一个为 WAN，其余为 LAN
		wan_if=$(echo "$ifnames" | awk '{print $NF}')
		lan_ifs=$(echo "$ifnames" | awk '{$NF=""; $1=$1; print}')
		configure_multi "$wan_if" $lan_ifs
	fi

	verify_config
	log "========== 网络配置脚本完成 =========="
}

main "$@"
exit 0
