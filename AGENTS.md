# Repository Guidelines

## 项目结构与模块组织

- `.github/workflows/Build-OpenWrt-25-x86-64.yml`：GitHub Actions 手动构建工作流。
- `scripts/build/`：本地构建入口（`build.sh`、`rebuild.sh`、`set-env.sh`）。
- `scripts/include/`：公共 Shell（脚本语言）模块，如路径处理、克隆、日志与构建流程。
- `scripts/custom/`：feeds 注入、自定义设置、产物收集等业务脚本。
- `scripts/init/`：环境初始化与检查脚本。
- `target/x86-64/`：种子配置（`custom_config/*.config`）与首次启动 `uci-defaults` 脚本。
- `docs/`、`images/`：文档与图片资源。

仓库不包含 OpenWrt 源码；构建时会浅克隆上游到 `openwrt/`，产物输出到 `upload/`。

## 构建、测试与开发命令

```bash
sudo bash scripts/init/init-env.sh   # 安装编译依赖（Ubuntu 22.04/24.04 或 WSL2）
./scripts/init/check.sh              # 检查当前环境
./scripts/build/build.sh             # 从零构建，复用或创建 openwrt/
./scripts/build/rebuild.sh           # 增量构建，先 make clean 再编译
```

CI 通过 `workflow_dispatch` 手动触发，使用矩阵配置编译并生成 `sha256sums`。

## 代码风格与命名规范

- Shell 遵循 POSIX 兼容写法，入口脚本显式声明 `set -e`。
- 优先复用 `scripts/include/common.sh` 与 `logger.sh`，用 `log_info` / `log_error` 输出日志。
- 文件、变量、函数使用英文命名；注释与错误信息使用简体中文。
- 按 `.editorconfig`：默认 4 空格缩进，JSON/YAML 为 2 空格，Makefile 使用 tab；LF 换行，UTF-8，保留末尾空行。

## 测试指南

仓库当前没有自动化单元测试。提交 Shell 变更前至少运行语法检查：

```bash
sh -n scripts/build/build.sh
sh -n scripts/custom/apply_custom_settings.sh
```

涉及配置、feeds、CI 的改动需说明如何验证；无法本地完整构建时，请在 PR 中标注待 CI 验证。

## 提交与 Pull Request 规范

历史提交遵循 Conventional Commits（约定式提交）：`<类型>(<范围>): <中文描述>`，如 `ci: 更新构建工作流`、`style(x86-64): 统一脚本缩进`。主题行不超过 72 字符。

PR 需包含：变更目的与影响面、关键配置差异、关联 Issue、必要日志或截图。构建相关 PR 应说明是否已通过本地或 CI 构建。

## 安全与配置提示

不要提交 PPPoE 凭据、root 密码、令牌等敏感信息。构建参数优先通过 `scripts/build/set-env.sh` 或 CI 输入调整，避免硬编码到脚本中。

## Agent skills

### Issue tracker

议题与规格说明存放在 GitHub Issues 中，操作一律用 `gh` CLI。See `docs/agents/issue-tracker.md`.

### Triage labels

分诊标签保留默认五角色（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。See `docs/agents/triage-labels.md`.

### Domain docs

single-context 布局：整个仓库共用仓库根目录一份 `GLOSSARY.md`，架构决定放 `docs/adr/`。See `docs/agents/domain.md`.
