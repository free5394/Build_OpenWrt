#!/bin/sh
# 功能：将 ./bin/targets/ 下所有匹配 *wrt*.img.gz 的文件移动至指定目录，
#       并根据 NAME_SUFFIX 环境变量的值决定是否重命名（非空时添加后缀）。

# =============================================
# 1. 严格模式：命令失败即退出
# =============================================
set -e

# 兼容开启管道失败检测（如 bash 环境）
if set -o | grep -q 'pipefail' 2>/dev/null; then
	set -o pipefail
fi

# =============================================
# 2. 日志目录创建与输出重定向
# =============================================
mkdir -p ./logs
exec >./logs/collect_upload.log 2>&1

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
