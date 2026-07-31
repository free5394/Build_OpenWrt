#!/bin/sh
# =============================================
# 严格模式：命令失败即退出；尝试启用 pipefail
# =============================================
set -e

# 在子 shell 中检测 pipefail 支持（POSIX 未要求，dash 等不支持）
# 不再调用 `set -o | grep pipefail` 验证：若 grep 未匹配，
# 在 set -e 下会误终止脚本
if (set -o pipefail 2>/dev/null); then
    set -o pipefail
fi

# ============== 初始化项目根目录（绝对路径） ==============
# 功能：获取当前脚本所在目录的绝对路径，作为相对路径的基准
# 注意：使用 cd && pwd 组合是为了解析符号链接并获得绝对路径
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# ============== 定义 POSIX 兼容的导入函数 ==============
# 参数1: 相对于 SCRIPT_ROOT 的相对路径 (例如 "common_scripts/common.sh")
# 或者是绝对路径
require() {
    _req_path="$1"

    # 如果是相对路径，则拼接到 SCRIPT_ROOT 下
    case "$_req_path" in
    /*) _full_path="$_req_path" ;; # 已经是绝对路径
    *) _full_path="${SCRIPT_ROOT}/${_req_path}" ;;
    esac

    # 检查文件是否存在
    if [ ! -f "$_full_path" ]; then
        echo "Error: Module not found at '$_full_path'" >&2
        exit 1
    fi

    # 生成防重复导入的标记变量名
    # 例如：common_scripts/common.sh -> _LOADED_common_scripts_common_sh
    # 使用 tr 过滤掉路径分隔符和点号，保证变量名合法
    _var_name="$(echo "$_req_path" | tr './-' '__')"
    _loaded_flag="_LOADED_${_var_name}"

    # 检查是否已加载
    eval "_is_loaded=\$$_loaded_flag"
    if [ "$_is_loaded" = "1" ]; then
        return 0
    fi

    # 标记为已加载
    eval "$_loaded_flag=1"

    # 执行导入 (使用 . 命令，这是 POSIX 标准的 source 方式)
    . "$_full_path"
}

# ============== 业务逻辑 ==============
echo "Start building..."

# 导入 a1.sh (路径基于 SCRIPT_ROOT)
require "a/a1.sh"

# 故意重复导入
require "a/a1.sh"

# 调用 a1.sh 中的函数
a1_hello

echo "Build finished."
