#!/bin/sh
#==================================================
# build.sh 与 rebuild.sh 的公共函数模块
# 依赖：logger.sh（log_info/log_error）、set-env.sh（环境变量）
# 使用方法： . ./build_common.sh
#==================================================

# 耗时统计包装器
# 耗时统计包装器
time_it() {
	# 1. 记录起始时间
	start_time=$(date +%s.%N)

	# 2. 执行传入的函数及参数
	"$@"

	# 3. 记录结束时间
	end_time=$(date +%s.%N)

	# 4. 计算总耗时（秒，取整）
	elapsed_sec=$(awk "BEGIN {print int($end_time - $start_time)}")

	# 5. 计算时、分、秒
	hours=$((elapsed_sec / 3600))
	mins=$(((elapsed_sec % 3600) / 60))
	secs=$((elapsed_sec % 60))

	# 6. 按阶梯格式化耗时字符串
	if [ "$hours" -gt 0 ]; then
		# 超过 1 小时：1h 30m 12s
		formatted_time="${hours}h ${mins}m ${secs}s"
	elif [ "$mins" -gt 0 ]; then
		# 不满 1 小时但超过 1 分钟：45m 13s
		formatted_time="${mins}m ${secs}s"
	else
		# 不满 1 分钟：15s
		formatted_time="${secs}s"
	fi

	# 7. 使用 printf 代替 echo 输出
	printf "[TIME] '%s' 执行耗时: %s\n" "$*" "$formatted_time"
	return 0
}

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
build_make_config() {
	config_enable="$1"
	if [ "$config_enable" -eq "0" ]; then
		log_info "生成配置文件..."
		rm -rf .config
		make menuconfig
		./scripts/diffconfig.sh >"$CUSTOM_CONFIG"
	else
		log_info "补全配置文件..."
		cp -f "custom_config/$CUSTOM_CONFIG" .config
		make defconfig V=s
	fi
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

_build_process() {
	build_mkdir_dl_share
	build_set_permissions_files
	build_apply_feeds_and_settings
	# 生成配置文件
	build_make_config "$1"
	build_apply_custom_settings
	build_download
	time_it build_compile
	build_upload

	log_info "全部完成"
	return 0
}

build_make_new_config() {
	_build_process "0" || {
		log_error "生成配置文件构建失败"
		return 1
	}
	return 0
}

build_make_custom_config() {
	_build_process "1" || {
		log_error "补全配置文件构建失败"
		return 1
	}
	return 0
}
