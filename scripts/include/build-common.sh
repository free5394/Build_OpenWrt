#!/bin/sh
#==================================================
# build.sh 与 rebuild.sh 的公共函数模块
# 依赖：logger.sh（log_info/log_error）、set-env.sh（环境变量）
# 使用方法： . ./build-common.sh
#==================================================

# 防止直接执行此脚本，确保它是被 source 的
case "$0" in
*/build-common.sh)
	echo "This is a library, do not run directly." >&2
	exit 1
	;;
esac

# 如果已经加载过，直接返回，不再重复解析
[ -n "$_SCRIPT_BUILD_COMMON_LOADED" ] && return 0
_SCRIPT_BUILD_COMMON_LOADED=1

build_env_info() {
	log_info "环境变量信息："
	log_info "GITHUB_WORKSPACE: %s" "$GITHUB_WORKSPACE"
	log_info "OPENWRT_DIR: %s" "$OPENWRT_DIR"
	log_info "UPLOAD_DIR: %s" "$UPLOAD_DIR"
	log_info "CUSTOM_CONFIG: %s" "$CUSTOM_CONFIG"

	log_info "OPENWRT_REPO: %s" "$OPENWRT_REPO"
	log_info "OPENWRT_BRANCH: %s" "$OPENWRT_BRANCH"

	log_info "BAK_ENABLED: %s" "$BAK_ENABLED"
	log_info "CUSTOM_BAK: %s" "$CUSTOM_BAK"
}

# 切换到工作空间目录
build_enter_workspace() {
	log_info "切换到工作目录..."
	cd "$GITHUB_WORKSPACE" || {
		log_error "无法切换到工作目录 %s" "$GITHUB_WORKSPACE"
		return 1
	}
	return 0
}

# 切换到 OpenWrt 目录
build_enter_openwrt_dir() {
	log_info "切换到OpenWrt目录..."
	cd "$OPENWRT_DIR" || {
		log_error "无法切换到 OpenWrt 目录 %s" "$OPENWRT_DIR"
		return 1
	}
	return 0
}

# 建立公共 dl 目录
build_mkdir_dl_share() {
	log_info "建立公共 dl 目录..."
	mkdir -p $HOME/immortalwrt_dl_share
	ln -s $HOME/immortalwrt_dl_share "$OPENWRT_DIR/dl"
	return 0
}

# 清理 dl 目录
clean_dl_share() {
	log_info "清理 dl 目录..."
	rm -rf "$OPENWRT_DIR/dl"
	return 0
}

# 设置文件权限
build_set_permissions_files() {
	log_info "设置文件权限..."
	chmod +x "$OPENWRT_DIR"/files/etc/uci-defaults/*.sh
	chmod +x scripts/custom/*.sh
	return 0
}

# 更新 feeds
build_apply_feeds_and_settings() {
	log_info "更新feeds并安装..."
	./scripts/custom/apply_custom_feeds.sh
	return 0
}

# 处理任务函数
process_task() {
	log_info "开始任务 %s..." "$*"
	build_enter_openwrt_dir
	"$@" || {
		log_error "任务 %s 执行执行失败" "$*"
		build_enter_workspace
		return 1
	}
	build_enter_workspace
	log_info "任务 %s 执行完成" "$*"
}

# 生成或补全配置文件
_custom_config() {
	log_info "补全配置文件..."
	cp -f "$CUSTOM_CONFIG" .config
	make defconfig V=s
	# 生成补丁文件，便于上传
	./scripts/diffconfig.sh >"$(basename "$CUSTOM_CONFIG")"
	return 0
}

# 生成或补全配置文件
build_custom_config() {
	process_task _custom_config
	return 0
}

# 生成新配置文件
_new_config() {
	log_info "生成配置文件..."
	rm -rf .config
	make menuconfig
	./scripts/diffconfig.sh >"$CUSTOM_CONFIG"
	return 0
}

# 生成新配置文件
build_new_config() {
	process_task _new_config
	return 0
}

# 补全配置文件
_custom_config_patch() {
	log_info "补全配置文件..."
	cp -f "$CUSTOM_CONFIG" .config
	make defconfig V=s
	log_info "调整配置文件..."
	make menuconfig
	./scripts/diffconfig.sh >"$CUSTOM_CONFIG"
	return 0
}

# 补全配置文件
build_custom_config_patch() {
	process_task _custom_config_patch
	return 0
}

# 设置环境变量
build_set_variable_values() {
	log_info "设置环境变量..."
	./scripts/custom/set_variable_values.sh
	return 0
}

# 应用自定义设置
build_apply_custom_settings() {
	log_info "应用自定义设置..."
	./scripts/custom/apply_custom_settings.sh
	return 0
}

# 下载依赖（首次并行重试，失败后单线程）
_download() {
	log_info "开始下载依赖..."
	make download -j $(($(nproc) + 1)) V=s || make download -j1 V=s
	return 0
}

# 下载依赖
build_download() {
	process_task _download
	return 0
}

# 编译 OpenWrt（默认 V=sc 减小日志体积，失败重试 V=s；记录时间戳到 build.txt）
_compile() {
	log_info "开始编译OpenWrt..."
	make -j $(($(nproc) + 1)) V=sc || make -j1 V=s
	return 0
}

# 编译 OpenWrt
build_compile() {
	process_task _compile
	return 0
}

# 清理旧构建
_make_clean() {
	log_info "清理旧构建..."
	make clean # 清理编译产物
	# make dirclean                 # 清理更彻底（包括工具链）
	# make distclean
}

# 清理旧构建
build_make_clean() {
	process_task _make_clean
	return 0
}

# 上传产物
build_upload() {
	log_info "开始上传..."
	./scripts/custom/collect_upload.sh
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
	build_set_variable_values
	build_apply_custom_settings
	build_download
	build_compile
	build_upload
}
