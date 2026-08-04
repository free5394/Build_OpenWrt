#!/bin/sh
#==================================================
# build.sh 与 rebuild.sh 的公共函数模块
# 依赖：logger.sh（log_info/log_error）、set-env.sh（环境变量）
# 使用方法： . ./build_common.sh
#==================================================

# 防止直接执行此脚本，确保它是被 source 的
case "$0" in
*build_common.sh)
	echo "This is a library, do not run directly." >&2
	exit 1
	;;
esac

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

# 建立公共 dl 目录
build_mkdir_dl_share() {
	log_info "建立公共 dl 目录..."
	mkdir -p $HOME/immortalwrt_dl_share
	ln -s $HOME/immortalwrt_dl_share ./dl
	return 0
}

# 清理 dl 目录
clean_dl_share() {
	log_info "清理 dl 目录..."
	rm -rf ./dl
	return 0
}

# 设置文件权限
build_set_permissions_files() {
	log_info "设置文件权限..."
	chmod +x files/etc/uci-defaults/*.sh
	chmod +x custom_scripts/*.sh
	return 0
}

# 更新 feeds
build_apply_feeds_and_settings() {
	log_info "更新feeds并安装..."
	./custom_scripts/apply_custom_feeds.sh
	return 0
}

# 生成或补全配置文件
build_custom_config() {
	log_info "补全配置文件..."
	cp -f "custom_config/$CUSTOM_CONFIG" .config
	make defconfig V=s
	return 0
}

# 生成新配置文件
build_new_config() {
	log_info "生成配置文件..."
	rm -rf .config
	make menuconfig
	./scripts/diffconfig.sh >"$CUSTOM_CONFIG"
	return 0
}

build_custom_config_patch() {
	log_info "补全配置文件..."
	cp -f "custom_config/$CUSTOM_CONFIG" .config
	make defconfig V=s
	log_info "调整配置文件..."
	make menuconfig
	./scripts/diffconfig.sh >"$CUSTOM_CONFIG"
	return 0
}

# 应用自定义设置
build_apply_custom_settings() {
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
	make -j $(($(nproc) + 1)) V=sc || make -j1 V=s
	return 0
}

# 上传产物
build_upload() {
	log_info "开始上传..."
	./custom_scripts/collect_upload.sh
	return 0
}

# 构建前流程
pre_build_process() {
	build_mkdir_dl_share
	build_set_permissions_files
	build_apply_feeds_and_settings
}

# 构建后流程
post_build_process() {
	build_apply_custom_settings
	build_download
	build_compile
	build_upload
}
