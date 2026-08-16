# 贡献指南

欢迎通过 Issue 和 Pull Request 参与本项目！

## 报告问题

提交 [Issue](https://github.com/free5394/Build_OpenWrt/issues) 时请包含：

- 复现步骤（触发方式、参数配置）
- 预期行为与实际行为
- 运行环境（CI / 本地、系统版本）
- 相关日志（构建日志位于 `openwrt/logs/` 下）

## 提交改进

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feat/your-feature`
3. 提交更改，遵循下方提交信息规范
4. 提交 Pull Request 并描述变更目的

## 提交信息规范

提交信息使用**中文**编写，遵循 `<类型>(<范围>): <描述>` 格式：

| 类型     | 说明           | 示例                             |
| -------- | -------------- | -------------------------------- |
| feat     | 新功能         | `feat(脚本): 增加 minimal 配置`  |
| fix      | 修复 bug       | `fix(工作流): 修复 Release 权限` |
| refactor | 重构（非功能） | `refactor(构建): 抽取公共函数`   |
| docs     | 文档           | `docs: 更新 README`              |
| style    | 代码格式       | `style: 统一缩进风格`            |
| test     | 测试           | `test: 添加单元测试`             |
| chore    | 构建/工具      | `chore: 升级上游分支版本`        |
| perf     | 性能优化       | `perf(编译): 启用 ccache 加速`   |
| ci       | CI/CD 配置     | `ci: 添加 macOS 构建流水线`      |
| security | 安全修复       | `security(脚本): 修复注入风险`   |

要求：

- 第一行不超过 **72** 个字符
- 类型和描述之间用冒号和空格分隔
- 描述使用中文，简洁明了
- 如需补充说明，在空行后写详细描述
- 范围（括号内）为可选项，根据实际改动决定是否添加

## 代码风格

- Shell 脚本遵循 POSIX 兼容写法（兼容 `sh` / `dash` / `ash`）
- 源码文件名、变量名、函数名使用英文
- 注释、错误提示信息使用中文
- 新增脚本建议引入 `common_scripts/common.sh` 与 `logger.sh`，使用 `log_info` / `log_error` 输出日志
- 入口脚本顶部显式声明 `set -e`，不依赖隐式继承

## 本地开发

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

# 2. 从零构建
./build/build.sh

# 3. 增量构建（复用已有 openwrt/ 目录）
./build/rebuild.sh
```

构建产物输出到 `upload/` 目录。详细说明请参考 [README.md](./README.md)。
