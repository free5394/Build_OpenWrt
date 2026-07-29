#!/bin/sh
# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（BusyBox ash 不支持时静默忽略）
set -o pipefail 2>/dev/null || true

# 保存脚本名以供提示
SCRIPT_NAME="$(basename "$0")"
log_file="./logs/$SCRIPT_NAME.log"

# =============================================
# 2. 统一日志输出重定向（追加模式）
# =============================================
# exec >"$log_file" 2>&1

# =============================================
# 业务逻辑开始
# =============================================
echo "脚本开始执行 - $(date)"

# 示例命令1：正常执行
echo "当前工作目录: $(pwd)"

# 1. 校验关键环境变量
: "${GITHUB_WORKSPACE:?错误：环境变量 GITHUB_WORKSPACE 未设置}"
: "${UPLOAD_DIR:?错误：环境变量 UPLOAD_DIR 未设置}"

# 2. 定义路径
src_dir="./bin/targets"
dest_dir="$GITHUB_WORKSPACE/$UPLOAD_DIR"

# 3. 创建目标目录（若不存在）
mkdir -p "$dest_dir"

# 4. 检查源目录是否存在
if [ ! -d "$src_dir" ]; then
	echo "警告：源目录 $src_dir 不存在，无文件可处理。" >&2
	exit 0
fi

# 5. 根据 NAME_SUFFIX 执行不同逻辑
if [ -n "$NAME_SUFFIX" ]; then
	echo "NAME_SUFFIX 非空，将重命名文件并移动至 $dest_dir"

	# 使用 find + sh -c 批量处理，传入目标目录和后缀作为参数
	find "$src_dir" -type f -name "*wrt*.img.gz" -exec sh -c '
        dest="$1"
        suffix="$2"
        shift 2
        for f in "$@"; do
            base="${f%.img.gz}"                 # 去除 .img.gz 后缀
            filename=$(basename "$base")        # 取得文件名（不含路径）
            newname="${filename}-${suffix}.img.gz"
            mv -f "$f" "$dest/$newname"
            echo "已移动并重命名：$f -> $dest/$newname"
        done
    ' sh "$dest_dir" "$NAME_SUFFIX" {} +
else
	echo "NAME_SUFFIX 为空，直接移动文件至 $dest_dir"

	# 使用 -exec ... + 批量移动，高效且避免命令行长度限制
	find "$src_dir" -type f -name "*wrt*.img.gz" -exec mv -f {} "$dest_dir/" +
fi

# 6. 压缩日志目录（若存在）
logs_dir="./logs"
if [ ! -d "$logs_dir" ]; then
	echo "警告：日志目录 $logs_dir 不存在，无文件可处理。"
else
	echo "压缩日志目录 $logs_dir"
	tar -czvf "$dest_dir/logs.tar.gz" "$logs_dir"
fi
