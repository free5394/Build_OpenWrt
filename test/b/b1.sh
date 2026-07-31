#!/bin/sh

# =============================================
# 引入日志模块
# =============================================
# shellcheck source=/dev/null
. "$(dirname -- "$0")"/../a/logger.sh || {
    printf '错误: 无法加载日志模块 logger.sh\n' >&2
    exit 1
}

# check logger.sh
log_debug "目录: $SCRIPT_DIR"
log_debug "全名: $SCRIPT_FULLNAME"
log_debug "名称: $SCRIPT_NAME"
log_debug "日志文件: $LOG_FILE"

log_debug "这是一条 debug 日志"
log_info "这是一条 info 日志"
log_warn "这是一条 warn 日志"
log_error "这是一条 error 日志"
