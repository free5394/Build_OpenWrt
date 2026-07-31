#!/bin/sh
# 防止直接执行此脚本，确保它是被 source 的
case "$0" in
*a1.sh)
    echo "This is a library, do not run directly." >&2
    exit 1
    ;;
esac

require "a/logger.sh"

# 故意重复导入
require "a/logger.sh"

# 定义模块功能
a1_hello() {
    log_info "A1 hello."
}

log_info "A1 module initialized."

test_a1_hello() {
    log_info "Test a1 hello: %s" "$@"
}

test_a1_hello "$@"
