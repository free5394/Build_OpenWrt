#!/bin/sh

# 追加环境变量配置
append_env() {
	env_line="$1"

	# 已存在则跳过
	if grep -qF "$env_line" ~/.bashrc; then
		echo "[跳过] 已存在: $env_line"
		return
	fi

	sed -i "\$a $env_line" ~/.bashrc
	echo "[新增] $env_line"
}

# 安装依赖
install_dependencies() {
	echo "安装依赖..."
	sudo apt update -y
	sudo apt full-upgrade -y
	sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
		bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex gawk gettext gcc-multilib \
		g++-multilib git gnutls-dev gperf haveged help2man intltool lib32gcc-s1 libc6-dev-i386 libelf-dev \
		libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libpython3-dev \
		libreadline-dev libssl-dev libtool libyaml-dev libz-dev lld llvm lrzsz mkisofs msmtp nano \
		ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip python3-ply python3-docutils \
		python3-pyelftools qemu-utils re2c rsync scons squashfs-tools subversion swig texinfo uglifyjs \
		upx-ucl unzip vim wget xmlto xxd zlib1g-dev zstd

	# 使用ccache加速重复编译
	echo "安装设置ccache..."
	sudo apt install -y ccache
}

# 设置ccache
setup_ccache() {
	append_env "export USE_CCACHE=1"
	append_env "export CCACHE_DIR=~/ccache"
	# shellcheck source=/dev/null
	. ~/.bashrc
}

# 清理环境
clean_up() {
	# 安装后再次清理，防止后续步骤空间不足
	sudo apt clean
	sudo apt autoremove -y
	sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/*
}

# 自定义设置
custom_setup() {
	# 设置时区
	[ -n "${TZ:-}" ] && sudo timedatectl set-timezone "$TZ"
}

# 主函数
main() {
	install_dependencies
	setup_ccache
	clean_up
	custom_setup
}

# 调用主函数
main "$@"
