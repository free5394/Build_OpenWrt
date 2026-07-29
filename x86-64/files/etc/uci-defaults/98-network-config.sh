#!/bin/sh
# 99-network-config.sh - 网络接口自动检测与配置脚本
# 规则：单网口→LAN；多网口→最后一个为WAN，其余为LAN

# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（如 bash 环境）
if set -o | grep -q 'pipefail' 2>/dev/null; then
	set -o pipefail
fi

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
echo "脚本开始执行 - $(date)"

# 示例命令1：正常执行
echo "当前工作目录: $(pwd)"

log() {
	echo "[$(date '+%H:%M:%S')] $*"
}

die() {
	log "错误: $*"
	echo "错误: $*" >&2
	exit 1
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
	log "单网口模式: $iface → LAN (DHCP)"

	uci set network.lan=device
	uci set network.lan.name='br-lan'
	uci set network.lan.proto='dhcp'
	uci delete network.lan.ipaddr 2>/dev/null
	uci delete network.lan.netmask 2>/dev/null
	uci delete network.lan.gateway 2>/dev/null
	uci delete network.lan.dns 2>/dev/null
	uci commit network || die "UCI 提交失败"
}

# ============================================================
# 4. 配置网络（多网口）
# ============================================================
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
	section
	section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
	if [ -z "$section" ]; then
		die "未找到 br-lan 设备配置段"
	fi

	uci -q delete "network.$section.ports"
	for port in $lan_ifs; do
		uci add_list "network.$section.ports"="$port"
	done
	log "br-lan 端口已更新: $lan_ifs"

	# LAN 静态 IP
	uci set network.lan.proto='static'
	uci set network.lan.netmask='255.255.255.0'

	# 支持自定义路由器后台地址
	IP_FILE="/etc/config/custom_router_ip.txt"
	if [ -f "$IP_FILE" ]; then
		custom_ip=$(cat "$IP_FILE")
		uci set network.lan.ipaddr="$custom_ip"
		log "自定义管理地址: $custom_ip"
	else
		uci set network.lan.ipaddr='192.168.100.1'
		log "默认管理地址: 192.168.100.1"
	fi

	uci commit network || die "UCI 提交失败"
}

# ============================================================
# 5. 验证配置
# ============================================================
verify_config() {
	log "--- 验证网络配置 ---"
	ok=1

	# 检查 LAN 是否已配置
	lan_proto
	lan_proto=$(uci get network.lan.proto 2>/dev/null)
	if [ -z "$lan_proto" ]; then
		log "验证失败: LAN 协议未设置"
		ok=0
	else
		log "LAN 协议: $lan_proto"
	fi

	# 多网口时检查 WAN
	wan_dev=$(uci get network.wan.device 2>/dev/null)
	if [ -n "$wan_dev" ]; then
		wan_proto=$(uci get network.wan.proto 2>/dev/null)
		log "WAN 设备: $wan_dev, 协议: $wan_proto"
	fi

	# 检查 br-lan 端口
	br_ports=$(uci show network | grep 'br-lan' | grep 'ports' 2>/dev/null)
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
		lan_ifs=$(echo "$ifnames" | awk '{$NF=""; print}' | awk '{$1=$1};1')
		configure_multi "$wan_if" $lan_ifs
	fi

	verify_config
	log "========== 网络配置脚本完成 =========="
}

main "$@"
