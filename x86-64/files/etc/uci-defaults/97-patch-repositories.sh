#!/bin/sh
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

sed -i '/kenzo\|small/d' /etc/apk/repositories.d/distfeeds.list

sed -i 's/mirrors\.vsean\.net/mirrors.pku.edu.cn/g' /etc/apk/repositories.d/distfeeds.list

# 检查关键词是否已删除
grep -Hn "kenzo\|small" /etc/apk/repositories.d/distfeeds.list || echo "无匹配行（删除成功）"

# 检查镜像源是否替换完成
grep "mirrors.pku.edu.cn" /etc/apk/repositories.d/distfeeds.list || echo "镜像源替换失败"

echo "设置完成"
