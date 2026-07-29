# Build_OpenWrt

[![License](https://img.shields.io/github/license/walk6834/Build_OpenWrt?style=flat-square)](./LICENSE)
[![ImmortalWrt](https://img.shields.io/badge/ImmortalWrt-25.12-orange?style=flat-square&logo=openwrt)](https://github.com/immortalwrt/immortalwrt)
[![Build](https://img.shields.io/badge/build-Manual%20workflow-lightgrey?style=flat-square&logo=github-actions)](./.github/workflows/build-25.12-x86-64.yml)
[![Latest Release](https://img.shields.io/github/v/release/walk6834/Build_OpenWrt?style=flat-square)](https://github.com/walk6834/Build_OpenWrt/releases)
![Stars](https://img.shields.io/github/stars/walk6834/Build_OpenWrt?style=flat-square)

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-25.12` 分支的 x86-64 软路由固件自定义构建仓库。

仓库本身**不包含 OpenWrt 源码**,只保存默认配置、自定义 feed、首次启动脚本与主题资源;构建时浅克隆上游源码,将 `x86-64/` 内容注入后再编译。生产构建运行在 GitHub Actions 的 `ubuntu-latest` runner 上,本地可在 Ubuntu / WSL 中复现。

---

## 快速开始(GitHub Actions)

1. 进入仓库 **Actions** → 选择 **Build OpenWrt 25.12** → **Run workflow**
2. 按需调整 9 个输入参数:

| 名称              | 类型    | 必填 | 默认值                    | 说明                                   |
| ----------------- | ------- | ---- | ------------------------- | -------------------------------------- |
| `repo_name`       | choice  | ✅   | `immortalwrt/immortalwrt` | 上游源码仓库(当前只提供该选项)         |
| `repo_branch`     | string  | ✅   | `v25.12.1`                | 上游源码分支                           |
| `part_size`       | number  |      | 1024                      | rootfs 分区大小(MB)                    |
| `ip_address`      | string  |      | `192.168.10.1`            | 默认 LAN 口 IP                         |
| `root_password`   | string  |      | `password`                | 默认 root 密码(注入到 `ROOT_PASSWORD`) |
| `pppoe_username`  | string  |      | ``                        | PPPoE 用户名(同时填写密码才生效)       |
| `pppoe_password`  | string  |      | ``                        | PPPoE 密码                             |
| `upload_artifact` | boolean |      | `true`                    | 是否上传 GitHub Actions Artifact       |
| `upload_release`  | boolean |      | `true`                    | 是否发布 GitHub Release                |

> **矩阵说明**:工作流 `strategy.matrix.config_name` 当前只启用 `standard`(`minimal` 与 `full` 已在 `.github/workflows/build-25.12-x86-64.yml` 中注释)。扩展配置请编辑工作流并对应在 `build/x86-64/custom_config/` 增加同名 `.config` 文件,产物会自动以 config 名为 `NAME_SUFFIX` 后缀(详见「产物获取」)。

3. 等待 30–60 分钟,产物可通过以下两种方式获取:
   - **Artifact**:文件名 `<repo_branch>-<YYYYMMDD>`,例如 `v25.12.1-20260717`;Artifact 名 = `${{env.OPENWRT_BRANCH}}-${{env.COMPILE_DATE}}`
   - **Release**:Tag 同名(`make_latest: true`),Release 描述自动写入源码仓库、分支、内核版本、默认 IP、默认密码(`KERNEL_VERSION` / `IP_ADDRESS` / `PASSWORD`,其中 `PASSWORD` 默认取自工作流变量 `ROOT_PASSWORD`)

---

## 默认固件参数

| 项          | 默认值                                             |
| ----------- | -------------------------------------------------- |
| 目标平台    | x86-64 generic                                     |
| 上游源码    | `immortalwrt/immortalwrt` @ `v25.12.1`             |
| Rootfs 分区 | 1024 MB(`PART_SIZE`,可通过工作流 `part_size` 覆盖) |
| LAN IP      | `192.168.10.1`(`IP_ADDRESS`)                       |
| Root 密码   | `password`(`ROOT_PASSWORD`,首次登录必须改)         |
| 时区        | `Asia/Shanghai` (`CST-8`)                          |
| LuCI 主题   | Argon(自定义背景图 `images/bg1.jpg`)               |
| ttyd        | root 免登录(`/bin/login -f root`)                  |

`build/x86-64/custom_config/standard.config` 是工作流矩阵实际加载的种子配置(含 PassWall / MoMo / nikki 等代理组件);`build/x86-64/default.config` 只在本地 `./build/build.sh` 走 `make menuconfig` 后由 `scripts/diffconfig.sh` 生成,CI 流程中不产生该文件。

---

## ⚠️ 安全提醒

- 默认 **root 密码** `password` 是公开配置,**首次登录后必须立即修改**
- **ttyd** 默认配置为 root 免登录,**禁止在不可信网络或公网中暴露 ttyd 服务**
- 部署到生产环境前,请审计 [`build/x86-64/files/etc/uci-defaults/99-custom-settings.sh`](./build/x86-64/files/etc/uci-defaults/99-custom-settings.sh) 中的所有占位项

---

## 本地构建(Ubuntu / WSL)

> 需要 `sudo` 权限、可访问 GitHub、≥ 30 GB 可用磁盘空间。

```bash
# 1. 安装编译依赖(Ubuntu)
sudo apt update
sudo bash scripts/init-env.sh

# 2. 从零构建(首次会浅克隆上游源码,并交互式 make menuconfig)
./build/build.sh

# 3. 增量构建(复用已有 openwrt/ 目录,先 make clean 再走 menuconfig)
./build/rebuild.sh
```

构建产物输出到 `uploads/` 目录(由 `build.sh` 中 `export UPLOAD_DIR=uploads` 决定),包含 `.config` 与所有 `*wrt*.img.gz` 固件镜像。

> **与 CI 的差异**
>
> - CI 通过 `cp -f build/x86-64/custom_config/<name>.config .config && make defconfig` 直接注入配置;本地 `./build/build.sh` 与 `./build/rebuild.sh` 则走交互式 `make menuconfig`(无 TTY 环境下会失败)。
> - CI 上传目录为 `upload/`(`workflows` 中 `env.UPLOAD_DIR: upload`,无 `s`),本地脚本使用 `uploads/`。
> - `rebuild.sh` 只 `make clean`(保留工具链),不做 `dirclean`/`distclean`,如需完全重建请手动调整。
> - 本地脚本会执行 `custom_scripts/collect_upload.sh`,产物文件名末尾会附加 `NAME_SUFFIX=walk6834`(CI 矩阵下后缀等于 `config_name`)。

---

## License

本项目采用 [Apache License 2.0](./LICENSE)。
