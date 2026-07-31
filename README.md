# Build_OpenWrt

[![License](https://img.shields.io/github/license/walk6834/Build_OpenWrt?style=flat-square)](./LICENSE)
[![ImmortalWrt](https://img.shields.io/badge/ImmortalWrt-25.12-orange?style=flat-square&logo=openwrt)](https://github.com/immortalwrt/immortalwrt)
[![Build](https://img.shields.io/badge/build-Manual%20workflow-lightgrey?style=flat-square&logo=github-actions)](.github/workflows/Build-OpenWrt-25-x86-64.yml)
[![Latest Release](https://img.shields.io/github/v/release/walk6834/Build_OpenWrt?style=flat-square)](https://github.com/walk6834/Build_OpenWrt/releases)
![Stars](https://img.shields.io/github/stars/walk6834/Build_OpenWrt?style=flat-square)

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `v25.12.1` 的 x86-64 软路由固件自定义构建仓库。

仓库本身**不包含 OpenWrt 源码**，只保存默认配置、自定义 feeds、首次启动脚本与主题资源；构建时浅克隆上游源码，将 `build/x86-64/` 内容注入后再编译。生产构建运行在 GitHub Actions 的 `ubuntu-latest` runner 上，本地可在 Ubuntu / WSL 中复现。

## 核心功能

- **一键构建**：通过 GitHub Actions 手动触发（`workflow_dispatch`），无需本地环境
- **参数可配置**：构建时自定义 LAN IP、root 密码、PPPoE 凭据、rootfs 分区大小等
- **预置代理组件**：集成 PassWall、MoMo、nikki、SingBox、Xray、Shadowsocks 等（`full` 配置额外含 OpenClash 及预置核心）
- **网络助手**：内置 AdGuard Home、UPnP、SQM、ttyd 等 LuCI 应用
- **主题美化**：默认 Argon 主题，自定义背景图
- **首次启动自动化**：通过 `uci-defaults` 脚本自动完成时区设置、仓库源切换、IPv6 配置、PPPoE 拨号、root 密码修改
- **双分发渠道**：构建产物同时上传到 GitHub Actions Artifact 与 GitHub Release
- **本地可复现**：提供 `build.sh` / `rebuild.sh` 在 Ubuntu / WSL 中构建

## 目录结构

```text
Build_OpenWrt/
├── .github/workflows/
│   └── build-25.12-x86-64.yml      # CI 工作流定义
├── build/
│   ├── build.sh                     # 本地从零构建入口
│   ├── rebuild.sh                   # 本地增量构建入口
│   ├── set-env.sh                   # 本地构建环境变量
│   └── x86-64/
│       ├── common_scripts/          # 公共 Shell 模块（路径解析、日志）
│       │   ├── common.sh
│       │   └── logger.sh
│       ├── custom_config/           # 种子配置文件
│       │   ├── standard.config      # 标准配置
│       │   └── full.config          # 完整配置（standard + OpenClash）
│       ├── custom_scripts/          # 构建辅助脚本
│       │   ├── apply_custom_feeds.sh     # 注入 kenzo / small feeds
│       │   ├── apply_custom_settings.sh  # 修改 IP / 主题 / ttyd / OpenClash 核心
│       │   ├── patch_custom_settings.sh  # 写入 root 密码 / PPPoE
│       │   ├── set_variable_values.sh   # 提取内核版本等元信息（CI 用）
│       │   └── collect_upload.sh         # 收集产物到上传目录
│       └── files/etc/uci-defaults/
│           └── 99-custom-settings.sh # 首次启动脚本
├── images/
│   └── bg1.jpg                      # Argon 主题背景图
├── scripts/
│   ├── init-env.sh                  # 编译依赖安装
│   └── check.sh                     # 运行环境信息检查
├── LICENSE                          # Apache License 2.0
└── README.md
```

## 快速开始（GitHub Actions）

### 1. 触发工作流

进入仓库 **Actions** → 选择 **Build OpenWrt 25.12** → **Run workflow**，按需调整以下输入参数：

| 名称              | 类型    | 必填 | 默认值                    | 说明                                     |
| ----------------- | ------- | ---- | ------------------------- | ---------------------------------------- |
| `repo_name`       | choice  | ✅   | `immortalwrt/immortalwrt` | 上游源码仓库（当前只提供该选项）         |
| `repo_branch`     | string  | ✅   | `v25.12.1`                | 上游源码分支                             |
| `part_size`       | number  |      | 1024                      | rootfs 分区大小（MB）                    |
| `ip_address`      | string  |      | `192.168.10.1`            | 默认 LAN 口 IP                           |
| `root_password`   | string  |      | `password`                | 默认 root 密码（注入到 `ROOT_PASSWORD`） |
| `pppoe_username`  | string  |      | _空_                      | PPPoE 用户名（同时填写密码才生效）       |
| `pppoe_password`  | string  |      | _空_                      | PPPoE 密码                               |
| `upload_artifact` | boolean |      | `true`                    | 是否上传 GitHub Actions Artifact         |
| `upload_release`  | boolean |      | `true`                    | 是否发布 GitHub Release                  |

### 2. 矩阵配置

工作流 `strategy.matrix.config_name` 当前启用 **`full`**（`minimal` 与 `standard` 已在 [.github/workflows/build-25.12-x86-64.yml](.github/workflows/Build-OpenWrt-25-x86-64.yml) 中注释）。

| 配置       | 说明                                                                                      |
| ---------- | ----------------------------------------------------------------------------------------- |
| `standard` | 基础配置，含 PassWall / MoMo / nikki / AdGuard Home / UPnP / SQM 等                       |
| `full`     | 在 `standard` 基础上增加 OpenClash（构建时预置 `clash_meta` 核心及 GeoIP / GeoSite 数据） |
| `minimal`  | 预留配置，当前未提供 `.config` 文件                                                       |

> **扩展配置**：如需启用其他配置，在工作流中取消对应行注释，并在 [`build/x86-64/custom_config/`](./build/x86-64/custom_config/) 下创建同名 `.config` 文件（如 `minimal.config`）。产物文件名会自动以 config 名作为 `NAME_SUFFIX` 后缀。

### 3. 获取产物

等待约 30–60 分钟构建完成后，可通过以下两种方式获取：

- **Artifact**：文件名 `<repo_branch>-<YYYYMMDD>`，例如 `v25.12.1-20260731`
- **Release**：Tag 同名（`make_latest: true`），Release 描述自动写入固件源码、分支、内核版本、默认 IP、默认密码

工作流末尾还会自动清理旧的 workflow 运行记录（保留最近 2 次）。

## 默认固件参数（CI 默认）

| 项          | 默认值                                                   |
| ----------- | -------------------------------------------------------- |
| 目标平台    | x86-64 generic                                           |
| 上游源码    | `immortalwrt/immortalwrt` @ `v25.12.1`                   |
| Rootfs 分区 | 1024 MB（`PART_SIZE`，可通过工作流 `part_size` 覆盖）    |
| LAN IP      | `192.168.10.1`（`IP_ADDRESS`）                           |
| Root 密码   | `password`（`ROOT_PASSWORD`，首次登录后必须修改）        |
| 时区        | `Asia/Shanghai` (`CST-8`)                                |
| LuCI 主题   | Argon（自定义背景图 [images/bg1.jpg](./images/bg1.jpg)） |
| ttyd        | root 免登录（`/bin/login -f root`）                      |

> [build/x86-64/custom_config/full.config](./build/x86-64/custom_config/full.config) 是工作流矩阵实际加载的种子配置；[standard.config](./build/x86-64/custom_config/standard.config) 为基础配置，可按需切换。

## 首次启动脚本

[build/x86-64/files/etc/uci-defaults/99-custom-settings.sh](./build/x86-64/files/etc/uci-defaults/99-custom-settings.sh) 会在固件首次启动时自动执行：

1. **修改时区**：设置为 `Asia/Shanghai` (`CST-8`)
2. **修补仓库源**：清理 apk distfeeds 中的 kenzo / small 源，将镜像源替换为 `mirrors.pku.edu.cn`
3. **配置 PPPoE**：若构建时提供了 PPPoE 凭据，将 WAN 口切换为 PPPoE 拨号
4. **禁用 WAN IPv6**：关闭 WAN 口 IPv6 委派与源过滤，并配置 wan6 口（DHCPv6）
5. **修改 root 密码**：写入构建时指定的 `ROOT_PASSWORD`

## 安全提醒

- 默认 **root 密码** `password` 是公开配置，**首次登录后必须立即修改**
- **ttyd** 默认配置为 root 免登录，**禁止在不可信网络或公网中暴露 ttyd 服务**；如需关闭，在构建前设置环境变量 `TTYD_AUTOLOGIN=0`
- 部署到生产环境前，请审计 [99-custom-settings.sh](./build/x86-64/files/etc/uci-defaults/99-custom-settings.sh) 中的所有占位项

## 本地构建（Ubuntu / WSL）

### 前置条件

- Ubuntu 22.04 / 24.04 或 WSL2，需要 `sudo` 权限
- 可访问 GitHub
- ≥ 30 GB 可用磁盘空间
- 安装 `git`、`bash` 等

### 构建步骤

```bash
# 1. 安装编译依赖（一次性）
sudo apt update
sudo bash scripts/init-env.sh

# 2. 从零构建（首次会浅克隆上游源码到 openwrt/ 并编译）
./build/build.sh

# 3. 增量构建（复用已有 openwrt/ 目录，先 make clean 再编译）
./build/rebuild.sh
```

构建产物输出到 `upload/` 目录，包含 `.config` 与所有 `*wrt*.img.gz` 固件镜像（文件名以 `NAME_SUFFIX` 为后缀）。

### 本地默认值

本地构建的默认值定义在 [build/set-env.sh](./build/set-env.sh) 中，与 CI 工作流默认值存在差异：

| 项            | 本地默认（set-env.sh） | CI 默认（工作流） |
| ------------- | ---------------------- | ----------------- |
| LAN IP        | `192.168.100.1`        | `192.168.10.1`    |
| PPPoE 用户名  | `a123`                 | _空_（不启用）    |
| PPPoE 密码    | `p456`                 | _空_（不启用）    |
| 种子配置      | `standard.config`      | `full.config`     |
| `NAME_SUFFIX` | `full`                 | matrix 配置名     |
| 上传目录      | `upload/`              | `upload/`         |

如需修改，直接编辑 [build/set-env.sh](./build/set-env.sh) 中对应的环境变量即可。

### 与 CI 的差异

- **配置注入方式相同**：本地与 CI 均通过 `cp -f custom_config/<name>.config .config && make defconfig` 注入配置，不走交互式 `make menuconfig`
- **CI 提取元信息**：CI 额外执行 `set_variable_values.sh` 提取内核版本等写入 `GITHUB_ENV`，用于 Release 描述；本地构建不执行此步骤
- **`rebuild.sh` 仅 `make clean`**：保留工具链，不做 `dirclean` / `distclean`；如需完全重建，请手动删除 `openwrt/` 目录后重新执行 `build.sh`
- **产物后缀**：本地固定使用 `NAME_SUFFIX=full`（来自 `set-env.sh`），CI 后缀等于 matrix 的 `config_name`

## 贡献指南

欢迎通过 Issue 和 Pull Request 参与本项目。

### 报告问题

提交 [Issue](https://github.com/walk6834/Build_OpenWrt/issues) 时请包含：

- 复现步骤（触发方式、参数配置）
- 预期行为与实际行为
- 运行环境（CI / 本地、系统版本）
- 相关日志（构建日志位于 `openwrt/logs/` 下）

### 提交改进

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feat/your-feature`
3. 提交更改，遵循下方提交信息规范
4. 提交 Pull Request 并描述变更目的

### 提交信息规范

提交信息使用**中文**编写，遵循 `<类型>(<范围>): <描述>` 格式：

| 类型     | 说明           | 示例                             |
| -------- | -------------- | -------------------------------- |
| feat     | 新功能         | `feat(脚本): 增加 minimal 配置`  |
| fix      | 修复 bug       | `fix(工作流): 修复 Release 权限` |
| refactor | 重构（非功能） | `refactor(构建): 抽取公共函数`   |
| docs     | 文档           | `docs: 更新 README`              |
| chore    | 构建/工具      | `chore: 升级上游分支版本`        |

要求：

- 第一行不超过 72 个字符
- 描述简洁明了，如需补充说明在空行后写详细描述

### 代码风格

- Shell 脚本遵循 POSIX 兼容写法（兼容 `sh` / `dash` / `ash`）
- 源码文件名、变量名、函数名使用英文
- 注释、错误提示信息使用中文
- 新增脚本建议引入 `common_scripts/common.sh` 与 `logger.sh`，使用 `log_info` / `log_error` 输出日志

## 许可证

本项目（构建脚本、配置、自定义文件）采用 [Apache License 2.0](./LICENSE)。

编译产物中的 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) / OpenWrt 源码遵循其原始许可证（GPL-2.0 等），第三方 LuCI 应用与软件包遵循各自许可证。
