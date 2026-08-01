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

# =============================================
# 引入公共模块（强制依赖，最佳实践）
# =============================================
# shellcheck source=/dev/null
# 使用 eval 确保路径解析正确，利用 || exit 1 确保加载失败即终止
# 注意：使用 -- 防止文件名以 - 开头被误认为参数
. "$(dirname -- "$0")/x86-64/common_scripts/common.sh" || {
	printf '错误: 无法加载公共模块 common.sh\n' >&2
	exit 1
}

# =============================================
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")/x86-64/common_scripts/logger.sh" || {
	printf '错误: 无法加载日志模块 logger.sh\n' >&2
	exit 1
}

# =============================================
# 引入环境变量模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")/set-env.sh" || {
	printf '错误: 无法加载环境变量模块 set-env.sh\n' >&2
	exit 1
}

# =============================================
# 引入构建公共函数模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")/x86-64/common_scripts/build_common.sh" || {
	printf '错误: 无法加载构建公共函数模块 build_common.sh\n' >&2
	exit 1
}

# =============================================
# 业务逻辑开始（重新构建：清理 → 重新配置 → 编译 → 上传）
# =============================================
build_enter_workspace || {
	log_error "无法进入工作目录，终止构建"
	exit 1
}

if [ ! -d "$OPENWRT_DIR" ]; then
	log_error "OpenWrt 目录 '$OPENWRT_DIR' 不存在"
	exit 1
fi

log_info "删除上传文件夹..."
rm -rf "$UPLOAD_DIR"

build_enter_openwrt_dir || {
	log_error "无法进入 OpenWrt 目录，终止构建"
	exit 1
}

# 清理 dl 目录
clean_dl_share

log_info "清理旧构建..."
make clean # 清理编译产物
# make dirclean                 # 清理更彻底（包括工具链）
# make distclean                # 完全清理（需重新配置）

# 构建流程
# 生成配置文件
build_make_new_config "$@"

# 补全配置文件
# build_make_custom_config "$@"
