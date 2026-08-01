#!/bin/sh
#==================================================
# build.sh 与 rebuild.sh 的公共函数模块
# 依赖：logger.sh（log_info/log_error）、set-env.sh（环境变量）
# 使用方法： . ./build_common.sh
#==================================================

# 切换到工作空间目录
build_enter_workspace() {
	log_info "切换到工作目录..."
	cd "$GITHUB_WORKSPACE" || {
		log_error "无法切换到工作目录 '$GITHUB_WORKSPACE'"
		return 1
	}
	return 0
}

# 切换到 OpenWrt 目录
build_enter_openwrt_dir() {
	log_info "切换到OpenWrt目录..."
	cd "$OPENWRT_DIR" || {
		log_error "无法切换到 OpenWrt 目录 '$OPENWRT_DIR'"
		return 1
	}
	return 0
}

# 更新 feeds 并应用自定义设置
build_apply_feeds_and_settings() {
	log_info "更新feeds并安装..."
	./custom_scripts/apply_custom_feeds.sh

	log_info "应用自定义设置..."
	./custom_scripts/apply_custom_settings.sh
	return 0
}

# 下载依赖（首次并行重试，失败后单线程）
build_download() {
	log_info "开始下载依赖..."
	make download -j $(($(nproc) + 1)) V=s || make download -j1 V=s
	return 0
}

# 编译 OpenWrt（默认 V=sc 减小日志体积，失败重试 V=s；记录时间戳到 build.txt）
build_compile() {
	log_info "开始编译OpenWrt..."
	echo "$(date '+%Y-%m-%d %H:%M:%S start')" >build.txt
	make -j $(($(nproc) + 1)) V=sc || make -j1 V=s
	echo "$(date '+%Y-%m-%d %H:%M:%S end')" >>build.txt
	return 0
}

# 上传产物
build_upload() {
	log_info "开始上传..."
	./custom_scripts/collect_upload.sh
	return 0
}
