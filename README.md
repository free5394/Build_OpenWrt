# Build_OpenWrt

[![License](https://img.shields.io/github/license/walk6834/Build_OpenWrt?style=flat-square)](./LICENSE)
[![ImmortalWrt](https://img.shields.io/badge/ImmortalWrt-25.12-orange?style=flat-square&logo=openwrt)](https://github.com/immortalwrt/immortalwrt)
[![Build](https://img.shields.io/badge/build-Manual%20workflow-lightgrey?style=flat-square&logo=github-actions)](.github/workflows/Build-OpenWrt-25-x86-64.yml)
[![Latest Release](https://img.shields.io/github/v/release/walk6834/Build_OpenWrt?style=flat-square)](https://github.com/walk6834/Build_OpenWrt/releases)
![Stars](https://img.shields.io/github/stars/walk6834/Build_OpenWrt?style=flat-square)

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `v25.12.1` 的 x86-64 软路由固件自定义构建仓库。

仓库本身**不包含 OpenWrt 源码**，只保存默认配置、自定义 feeds、首次启动脚本与主题资源；构建时浅克隆上游源码，将 `target/x86-64/` 内容注入后再编译。生产构建运行在 GitHub Actions 的 `ubuntu-latest` runner 上，本地可在 Ubuntu / WSL 中复现。

## 项目架构

```text
构建编排层（入口）        公共模块层（include）               业务脚本层（custom）
┌──────────────┐        ┌──────────────────────┐          ┌─────────────────────────┐
│  build.sh    │──┐     │  logger.sh   日志     │          │ apply_custom_feeds.sh   │ 注入 kenzo/small feeds
│  rebuild.sh  │──┼────▶│  common.sh   路径/克隆 │◀────────▶│ apply_custom_settings.sh│ 改 IP/主题/ttyd/核心
│  set-env.sh  │──┘     │  build-common.sh 流程 │          │ set_variable_values.sh  │ 提取内核版本（CI）
└──────────────┘        │  yh.config   参考配置 │          │ collect_upload.sh       │ 收集产物+sha256
                        └──────────────────────┘          └─────────────────────────┘
                              │                                    │
                              │ source 引入                        │
                              ▼                                    ▼
                      ┌─────────────────┐                 ┌─────────────────────────┐
                      │ GitHub Actions  │                 │ uci-defaults            │
                      │ workflow.yml    │                 │ 99-custom-settings.sh   │ 首次启动自动化
                      └─────────────────┘                 └─────────────────────────┘
```

构建脚本采用 POSIX 兼容 Shell 编写，模块间通过 `source` 引入公共函数，遵循"严格模式 + 显式错误处理"风格。

## 核心功能

- **一键构建**：通过 GitHub Actions 手动触发（`workflow_dispatch`），无需本地环境
- **参数可配置**：构建时自定义 LAN IP、rootfs 分区大小等
- **三套种子配置**：`minimal` / `standard` / `full` 独立维护，覆盖从精简到全功能的不同场景
- **预置代理组件**：集成 PassWall / PassWall2、OpenClash、SingBox、Xray、Shadowsocks、Hysteria、NaiveProxy、Shadow-TLS、chinadns-ng 等（按配置启停）
- **网络与媒体服务**：内置 AdGuard Home、SmartDNS、MosDNS、UPnP、SQM、ttyd、timewol、qBittorrent、Syncthing、MiniDLNA 等 LuCI 应用
- **容器与虚拟化**：`full` 配置可选启用 Docker、containerd、runc、HomeProxy 等
- **主题美化**：默认 Argon 主题，自定义背景图
- **首次启动自动化**：通过 `uci-defaults` 脚本自动完成时区设置、仓库源切换、IPv6 配置、PPPoE 拨号、root 密码修改
- **双分发渠道**：构建产物同时上传到 GitHub Actions Artifact 与 GitHub Release，并生成 `sha256sums` 校验文件
- **本地可复现**：提供 `build.sh` / `rebuild.sh` 在 Ubuntu / WSL 中构建，支持 ccache 加速与 feeds 备份恢复

## 目录结构

```text
Build_OpenWrt/
├── .github/workflows/
│   └── Build-OpenWrt-25-x86-64.yml  # CI 工作流定义
├── scripts/
│   ├── build/                       # 构建入口脚本
│   │   ├── build.sh                 # 本地从零构建入口
│   │   ├── rebuild.sh               # 本地增量构建入口
│   │   └── set-env.sh               # 本地构建环境变量
│   ├── include/                     # 公共 Shell 模块（被 source 引入）
│   │   ├── common.sh                # 路径规范化、仓库克隆、通用下载
│   │   ├── logger.sh                # 分级日志（DEBUG/INFO/WARN/ERROR）
│   │   ├── build-common.sh          # 构建流程公共函数
│   │   └── yh.config                 # 参考配置片段（内核调试关闭/zram/体积优化，未被脚本引用）
│   ├── custom/                      # 构建辅助脚本（业务逻辑）
│   │   ├── apply_custom_feeds.sh     # 注入 kenzo / small feeds，更新 golang
│   │   ├── apply_custom_settings.sh  # 修改 IP / 主题 / ttyd / OpenClash 核心
│   │   ├── set_variable_values.sh    # 提取内核版本等元信息（CI 用）
│   │   └── collect_upload.sh         # 收集产物到上传目录，生成 sha256sums
│   └── init/                        # 环境初始化
│       ├── check.sh                 # 运行环境信息检查（CPU/内存/磁盘）
│       └── init-env.sh              # 编译依赖安装 + ccache 配置
├── target/
│   └── x86-64/                      # 注入到 OpenWrt 源码树的自定义内容
│       ├── custom_config/           # 种子配置文件
│       │   ├── minimal.config       # 精简配置（CI 当前启用）
│       │   ├── standard.config      # 标准配置（minimal + bash/OpenClash/AdGuard Home/ruby）
│       │   └── full.config          # 完整配置（含 Docker/qBittorrent/Syncthing/MosDNS 等）
│       └── files/etc/uci-defaults/
│           └── 99-custom-settings.sh # 首次启动脚本
├── test/                            # 模块化加载机制测试脚本（不参与构建）
├── images/
│   └── bg1.jpg                      # Argon 主题背景图
├── CONTRIBUTING.md                  # 贡献指南
├── LICENSE                          # Apache License 2.0
└── README.md
```

## 快速开始（GitHub Actions）

### 1. 触发工作流

进入仓库 **Actions** → 选择 **Build-OpenWrt-25-x86-64** → **Run workflow**，按需调整以下输入参数：

| 名称                | 类型      | 必填  | 默认值                       | 说明                           |
| ----------------- | ------- | --- | ------------------------- | ---------------------------- |
| `repo_name`       | string  | ✅   | `immortalwrt/immortalwrt` | 上游源码仓库                       |
| `repo_branch`     | string  | ✅   | `v25.12.1`                | 上游源码分支                       |
| `part_size`       | number  | ✅   | `1024`                    | rootfs 分区大小（MB）              |
| `ip_address`      | string  | ✅   | `192.168.10.1`            | 默认 LAN 口 IP                  |
| `upload_artifact` | boolean |     | `true`                    | 是否上传 GitHub Actions Artifact |
| `upload_release`  | boolean |     | `true`                    | 是否发布 GitHub Release          |

### 2. 矩阵配置

工作流 `strategy.matrix.config_name` 当前启用 **`minimal`**（`standard` 与 `full` 已在 [.github/workflows/Build-OpenWrt-25-x86-64.yml](.github/workflows/Build-OpenWrt-25-x86-64.yml) 中注释，可按需启用）。

| 配置         | 说明                                                                                                                                                                         |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `minimal`  | 精简配置：PassWall（含 SingBox/Xray/Shadowsocks/SSR/Simple-Obfs/V2ray-Plugin/Haproxy/Geoview）、nikki、momo、bandix-plus、SQM、ttyd、timewol、chinadns-ng、Argon 主题                        |
| `standard` | 在 `minimal` 基础上增加 bash、AdGuard Home、OpenClash、eqos、ruby（含 YJIT）等                                                                                                           |
| `full`     | 全功能配置：在 `standard` 基础上扩展 Docker/containerd/runc、qBittorrent、Syncthing、MiniDLNA、SmartDNS、MosDNS、HomeProxy、PassWall2、SSR-Plus、Lucky、rclone、rustdesk-server、nginx/uwsgi、磁盘工具等 |

> **三套配置独立维护**：并非严格增量关系，各 `.config` 文件均完整声明所需选项，可单独切换。`make defconfig` 会自动补全依赖项。
> 
> **扩展配置**：如需启用其他配置，在工作流中取消对应行注释，并在 [target/x86-64/custom_config/](./target/x86-64/custom_config/) 下创建同名 `.config` 文件。产物文件名会自动以 config 名作为后缀。

### 3. 获取产物

等待约 30–60 分钟构建完成后，可通过以下两种方式获取：

- **Artifact**：文件名 `<repo_branch>-<YYYYMMDDHHMM>`，例如 `v25.12.1-202608041944`
- **Release**：Tag 同名（`make_latest: true`），Release 描述自动写入固件源码、分支、内核版本、默认 IP、默认密码

上传目录包含以下文件：

| 文件                      | 说明                  |
| ----------------------- | ------------------- |
| `*wrt*-<config>.img.gz` | 固件镜像（以 config 名为后缀） |
| `<config>.config`       | 实际生效的 `.config` 配置  |
| `logs-<config>.tar.gz`  | 构建日志压缩包             |
| `sha256sums`            | 全部文件的 SHA-256 校验值   |

工作流末尾还会自动清理旧的 workflow 运行记录（保留最近 2 次，7 天前的全部清理）。

## 默认固件参数（CI 默认）

| 项         | 默认值                                              |
| --------- | ------------------------------------------------ |
| 目标平台      | x86-64 generic                                   |
| 上游源码      | `immortalwrt/immortalwrt` @ `v25.12.1`           |
| Rootfs 分区 | 1024 MB（`PART_SIZE`，可通过工作流 `part_size` 覆盖）       |
| LAN IP    | `192.168.10.1`（`IP_ADDRESS`）                     |
| Root 密码   | 无（`root_password` 默认为空，跳过修改；使用上游默认密码）            |
| 时区        | `Asia/Shanghai` (`CST-8`)                        |
| LuCI 主题   | Argon（自定义背景图 [images/bg1.jpg](./images/bg1.jpg)） |
| IPv6      | 启用独立 wan6 接口（DHCPv6，`ipv6_type=2`）               |
| ttyd      | 默认不启用免登录（`TTYD_AUTOLOGIN=1` 可开启）                 |

> [target/x86-64/custom_config/minimal.config](./target/x86-64/custom_config/minimal.config) 是工作流矩阵实际加载的种子配置；本地构建默认使用 `full.config`，可按需切换。

## 首次启动脚本

[target/x86-64/files/etc/uci-defaults/99-custom-settings.sh](./target/x86-64/files/etc/uci-defaults/99-custom-settings.sh) 会在固件首次启动时自动执行（日志写入 `/tmp/99-custom-settings.log`）：

1. **修改时区**：设置为 `Asia/Shanghai` (`CST-8`)
2. **修补仓库源**：将 apk distfeeds 镜像源替换为 `mirrors.tuna.tsinghua.edu.cn`（清华源），替换失败自动回滚
3. **配置网络**：修改 LAN 口 IP（带 IPv4 格式校验）；若 PPPoE 凭据非空则将 WAN 口切换为 PPPoE 拨号
4. **配置 IPv6**：`ipv6_type=2` 时启用独立 wan6 接口（DHCPv6）并加入 wan 防火墙区域；`ipv6_type=1` 时在 wan 接口启用 IPv6 委派；`ipv6_type=0` 时禁用
5. **修改 LuCI 主题**：设置默认主题为 Argon 并清理缓存（`default_theme` 为空则跳过）
6. **修改 root 密码**：`root_password` 非空时写入加密哈希（默认为空，跳过修改）

> 脚本采用"错误不中断"策略：每个模块独立执行，单个模块失败仅记录日志，不影响后续模块。

## 技术选型说明

| 领域       | 选型                              | 说明                                                               |
| -------- | ------------------------------- | ---------------------------------------------------------------- |
| 上游源码     | ImmortalWrt `v25.12.1`          | 国内友好的 OpenWrt 分支，预置较多本土化软件包                                      |
| Shell 规范 | POSIX `/bin/sh`                 | 兼容 `sh` / `dash` / `ash`，可在 CI 与 OpenWrt 目标机一致运行                 |
| 日志系统     | 自研 `logger.sh`                  | 分级日志（DEBUG/INFO/WARN/ERROR）+ 可选重定向到文件                            |
| CI 平台    | GitHub Actions                  | `ubuntu-latest`，180 分钟超时，ccache 缓存加速                             |
| 缓存策略     | ccache + feeds 备份               | CI 用 actions/cache 缓存 ccache；本地用 `BAK_ENABLED` 备份 feeds/源码       |
| 配置注入     | 种子 `.config` + `make defconfig` | 不走交互式 menuconfig，保证可复现                                           |
| 产物校验     | `sha256sums`                    | 自动为上传目录所有文件生成 SHA-256 校验                                         |
| 错误处理     | 严格模式 + trap 清理                  | `set -e` + `pipefail`（如支持）；`collect_upload.sh` 用 EXIT trap 清理半成品 |

## 本地构建（Ubuntu / WSL）

### 前置条件

- Ubuntu 22.04 / 24.04 或 WSL2，需要 `sudo` 权限
- 可访问 GitHub
- ≥ 30 GB 可用磁盘空间
- 安装 `git`、`bash` 等

### 构建步骤

```bash
# 1. 安装编译依赖（一次性，含 ccache 配置）
sudo apt update
sudo bash scripts/init/init-env.sh

# 2. 从零构建（首次会浅克隆上游源码到 openwrt/ 并编译）
./scripts/build/build.sh

# 3. 增量构建（复用已有 openwrt/ 目录，先 make clean 再编译）
./scripts/build/rebuild.sh
```

构建产物输出到 `upload/` 目录，包含固件镜像、`.config`、日志压缩包与 `sha256sums` 校验文件。

### 本地默认值

本地构建的默认值定义在 [scripts/build/set-env.sh](./scripts/build/set-env.sh) 中：

| 项        | 本地默认（set-env.sh）                     | CI 默认（工作流）                           |
| -------- | ------------------------------------ | ------------------------------------ |
| LAN IP   | `192.168.10.1`                       | `192.168.10.1`                       |
| 种子配置     | `custom_config/full.config`          | `custom_config/<config_name>.config` |
| 上游分支     | `v25.12.1`                           | `v25.12.1`                           |
| feeds 备份 | 启用（`BAK_ENABLED=1`，目录 `custom_bak/`） | 未启用                                  |
| ccache   | 启用（`USE_CCACHE=1`，`$HOME/ccache`）    | 启用（`/home/runner/.ccache`）           |
| 日志重定向    | 关闭（`LOG_REDIRECTION_ENABLE=0`）       | 关闭（工作流中注释，默认 0）                      |

如需切换配置，编辑 [scripts/build/set-env.sh](./scripts/build/set-env.sh) 中的 `CUSTOM_CONFIG` 变量（如改为 `custom_config/minimal.config` 或 `custom_config/standard.config`）。其他环境变量（IP、分区大小、PPPoE 凭据等）也可直接在该文件调整。

### feeds 备份与恢复

本地构建默认启用 `BAK_ENABLED=1`：首次克隆的 OpenWrt 源码、feeds、golang 目录会备份到 `custom_bak/`，下次构建时自动恢复，避免重复下载。如需禁用，设置 `BAK_ENABLED=0`。

### 与 CI 的差异

- **配置注入方式相同**：本地与 CI 均通过 `cp -f custom_config/<name>.config .config && make defconfig` 注入配置，不走交互式 `make menuconfig`
- **CI 提取元信息**：CI 额外执行 `set_variable_values.sh` 提取内核版本等写入 `GITHUB_ENV`，用于 Release 描述；本地执行时该脚本检测到 `GITHUB_ENV` 未设置会自动跳过写入
- **`rebuild.sh` 仅 `make clean`**：保留工具链，不做 `dirclean` / `distclean`；如需完全重建，请手动删除 `openwrt/` 目录后重新执行 `build.sh`
- **日志重定向**：`logger.sh` 通过 `LOG_REDIRECTION_ENABLE=1` 将日志重定向到 `logs/<script>.log`；本地默认直接输出到终端，CI 工作流也默认输出到终端并通过 `tee` 追加到日志文件

## 模块化脚本设计

公共模块遵循"防重复加载 + 显式 source"原则：

| 模块                | 路径                                                                   | 职责                                                                          |
| ----------------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `logger.sh`       | [scripts/include/logger.sh](./scripts/include/logger.sh)             | 分级日志、颜色输出、脚本路径解析、日志重定向                                                      |
| `common.sh`       | [scripts/include/common.sh](./scripts/include/common.sh)             | 路径规范化（`norm_path`）、仓库克隆（`clone_repo`）、通用下载（`download_file`）、耗时统计（`time_it`） |
| `build-common.sh` | [scripts/include/build-common.sh](./scripts/include/build-common.sh) | 构建流程编排（下载/编译/清理/上传）、`pre_build_process` / `post_build_process` 流程钩子         |

每个模块顶部通过 `case "$0"` 防止直接执行，并通过 `_SCRIPT_*_LOADED` 标志位防止重复 source。入口脚本（`build.sh` / `rebuild.sh` / `apply_custom_*.sh`）显式 `set -e` 并在子 shell 中探测 `pipefail` 支持。

## 贡献指南

欢迎通过 Issue 和 Pull Request 参与本项目。详细的贡献规范、提交信息格式与代码风格请参阅 [CONTRIBUTING.md](./CONTRIBUTING.md)。

要点：

- 提交信息使用中文，遵循 `<类型>(<范围>): <描述>` 格式（如 `feat(脚本): 增加 minimal 配置`）
- Shell 脚本遵循 POSIX 兼容写法，新增脚本建议引入 `include/common.sh` 与 `logger.sh`
- 入口脚本顶部显式声明 `set -e`，不依赖隐式继承

## 常见问题

**Q1：构建失败提示磁盘空间不足？**
CI runner 默认磁盘空间有限，工作流已通过 `jlumbroso/free-disk-space` 清理 Android、Docker、.NET 等无用组件。本地构建请确保 ≥ 30 GB 可用空间，并可启用 ccache 减少重复编译。

**Q2：如何修改默认 LAN IP？**

- CI 构建：在触发工作流时填写 `ip_address` 参数
- 本地构建：修改 [scripts/build/set-env.sh](./scripts/build/set-env.sh) 中的 `IP_ADDRESS`
- 该 IP 实际由 `apply_custom_settings.sh` 写入 `99-custom-settings.sh` 的 `lan_ip_addr` 变量，在固件首次启动时生效

**Q3：如何启用 PPPoE 拨号？**
编辑 [target/x86-64/files/etc/uci-defaults/99-custom-settings.sh](./target/x86-64/files/etc/uci-defaults/99-custom-settings.sh) 中的 `pppoe_username` 与 `pppoe_password`（两者均非空时才配置 PPPoE）。

**Q4：如何切换 LuCI 主题？**
编辑 `99-custom-settings.sh` 中的 `default_theme` 变量（如 `bootstrap`、`argon`），留空则跳过主题修改。`apply_custom_settings.sh` 默认将主题设为 `argon`。

**Q5：`rebuild.sh` 报错"OpenWrt 目录不存在"？**
`rebuild.sh` 复用已有的 `openwrt/` 目录，需先执行过 `build.sh`。如需完全重建，删除 `openwrt/` 后重新执行 `build.sh`。

**Q6：如何验证下载的固件完整性？**
下载目录中的 `sha256sums` 包含所有文件的 SHA-256 校验值，在固件所在目录执行 `sha256sum -c sha256sums` 即可验证。

**Q7：OpenClash 核心从哪里下载？**
`apply_custom_settings.sh` 检测到 `.config` 中选中 `luci-app-openclash` 后，会从 [OpenClash](https://github.com/vernesong/OpenClash) 仓库下载 `clash_meta` 核心（默认 `v2` 版本，可通过 `OPENCLASH_CORE_VERSION` 环境变量覆盖），并从 [v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) 下载 GeoIP / GeoSite 数据，预置到固件中。

**Q8：如何切换 CI 启用的种子配置？**
编辑 [.github/workflows/Build-OpenWrt-25-x86-64.yml](.github/workflows/Build-OpenWrt-25-x86-64.yml) 中 `strategy.matrix.config_name`，取消目标配置行的注释（同时注释掉其他配置）。当前仅 `minimal` 未被注释。

**Q9：`scripts/include/yh.config` 是什么？**
一份参考配置片段，演示了关闭内核调试项、启用 zram 内存压缩、切换为体积优化模式、精简 Ruby 等常用优化。**当前未被任何脚本自动引用**，可手动合并到 `custom_config/*.config` 中使用。

## 安全提醒

- 默认 **root 密码沿用上游 ImmortalWrt 默认值**（`root_password` 为空，跳过修改），**首次登录后应立即修改**
- 如需在构建时写入 root 密码哈希，编辑 `99-custom-settings.sh` 中的 `root_password`（推荐使用 `openssl passwd -6` 生成哈希）
- **ttyd** 默认不启用免登录；如需启用免登录，在构建前设置环境变量 `TTYD_AUTOLOGIN=1`（**禁止在不可信网络或公网中暴露免登录 ttyd 服务**）
- 部署到生产环境前，请审计 [99-custom-settings.sh](./target/x86-64/files/etc/uci-defaults/99-custom-settings.sh) 中的所有占位项（root 密码哈希、PPPoE 凭据等）

## 许可证

本项目（构建脚本、配置、自定义文件）采用 [Apache License 2.0](./LICENSE)。

编译产物中的 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) / OpenWrt 源码遵循其原始许可证（GPL-2.0 等），第三方 LuCI 应用与软件包遵循各自许可证。
