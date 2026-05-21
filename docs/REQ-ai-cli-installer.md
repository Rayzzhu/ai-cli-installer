# AI CLI 一键安装配置脚本 — 需求澄清

| 项目 | 内容 |
|------|------|
| 文档版本 | v1.0 |
| 日期 | 2026-05-21 |

---

## 1. 需求背景

### 1.1 背景

OpenCode 与 Qwen Code 均为终端 AI 编程助手，各自有官方安装方式与用户级配置目录。手动安装、找配置路径、填 API Key 对非技术用户成本高，且 Linux / macOS / Windows 路径与包管理器差异大。

公司内网访问境外地址（如 `opencode.ai`、`registry.npmjs.org`、`github.com`）较慢，安装脚本需优先使用国内镜像或企业内网源，并在失败时回退备选安装方式。

### 1.2 目标

提供单一入口脚本，通过交互式问答完成：

1. 选择安装 OpenCode 或 Qwen Code
2. 在当前操作系统上完成安装与基本校验（优先国内/内网镜像）
3. 将模板配置文件写入该工具规定的配置目录
4. 交互式收集 API Key，写入配置或环境变量
5. 输出安装结果与后续使用提示

---

## 2. 术语

| 术语 | 含义 |
|------|------|
| OpenCode | https://opencode.ai 开源 AI 编码 CLI |
| Qwen Code | https://github.com/QwenLM/qwen-code AI 编码 CLI |
| 用户级配置 | 仅影响当前用户、全局生效的配置（非仓库内） |
| Key | API Key、Coding Plan Key 等鉴权凭证，用于 CLI 调用模型接口 |
| 镜像源 | 替代境外下载地址的国内 CDN、npm 镜像或企业内网制品地址 |

---

## 3. 需求详情

```
启动脚本
  → 检测 OS（linux / darwin / win32）与架构
  → 检测依赖（curl、bash/powershell、node 等，按安装路径）
  → 交互：网络环境 [1] 国内镜像（默认） [2] 官方源 [3] 企业内网地址
  → 交互：请选择要安装的工具
        [1] OpenCode
        [2] Qwen Code
  → 若已安装：询问 [覆盖重装 / 跳过安装仅配置 / 退出]
  → 按网络选择执行安装（见下表），失败则尝试备选源
  → 验证命令可用（which opencode / qwen --version）
  → 创建配置目录
  → 从脚本内置或同目录 templates/ 加载模板，合并/写入用户配置
  → 交互：请输入 API Key（掩码输入）
  → 写回配置文件或 ~/.qwen/.env 等
  → 打印摘要：配置路径、实际安装源、验证命令、文档链接
```

**安装源约定：**

| 工具 | 国内镜像（优先） | 备选 |
|------|------------------|------|
| Qwen Code | 阿里云 OSS：`qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen.sh`（Windows 用同域 bat） | `npm install -g @qwen-code/qwen-code` + `registry.npmmirror.com`（需 Node ≥ 22） |
| OpenCode | `npm install -g opencode-ai` + `registry.npmmirror.com` | `curl opencode.ai/install` 或官方 `registry.npmjs.org` |

企业内网可通过环境变量 `AI_CLI_NPM_REGISTRY`、`AI_CLI_QWEN_INSTALL_URL` 覆盖上述地址；支持 `HTTP_PROXY` / `HTTPS_PROXY`。

**配置目录约定：**

| 工具 | 用户级配置路径 |
|------|----------------|
| OpenCode | `~/.config/opencode/opencode.json` |
| Qwen Code | `~/.qwen/settings.json`、`~/.qwen/.env`（Key 推荐写 `.env`） |

---

## 4. 需求平台

| OS | 标识 | 脚本载体 |
|----|------|----------|
| Linux | linux | install.sh（bash） |
| macOS | darwin | install.sh（bash） |
| Windows | win32 | install.ps1（PowerShell 5.1+） |

---

## 5. 功能需求清单

| ID | 需求 |
|----|------|
| 01 | 启动时识别 OS/架构并选择安装分支 |
| 02 | 交互选择 OpenCode / Qwen Code |
| 03 | 按网络环境调用镜像或官方方式完成安装，支持失败回退 |
| 04 | 安装后 PATH/命令可用性校验 |
| 05 | 自动创建用户配置目录 |
| 06 | 加载模板并写入用户级配置文件 |
| 07 | 交互输入 Key 并持久化 |
| 08 | 已安装检测与重装/仅配置分支 |
| 09 | 配置备份 |
| 10 | 安装/配置摘要与下一步命令提示 |
| 11 | 交互选择国内镜像 / 官方源 / 企业内网地址 |
| 12 | 支持环境变量与代理覆盖下载地址 |

---

## 6. 非功能需求

| 类别 | 要求 |
|------|------|
| 可维护性 | 安装 URL、默认模型、模板与脚本版本同 tag |
| 兼容性 | 主流 bash 4+、PowerShell 5.1+；Windows Terminal |
| 弱网/内网 | 默认走国内镜像；单源超时 30s；每源最多重试 2 次 |
| 离线 | 无外网时仅支持配置写入（模板本地）；安装需网络或企业预置包 |
| 测试 | 至少在 GitHub Actions matrix: ubuntu / macos / windows 做 smoke（mock 安装可选） |

---

## 7. 验收标准

1. 在 Ubuntu 22.04+、macOS 13+、Windows 11 上，新用户可按提示完成任选一种工具的安装。
2. 选择「国内镜像」时，Qwen 安装可不依赖 `github.com`；OpenCode 可不依赖 `opencode.ai` 安装脚本。
3. 安装后 5 分钟内，用户执行 `opencode` 或 `qwen` 能进入可用状态（已配置 Key）。
4. 配置文件存在于约定路径，且 Key 不出现在终端明文输出。
5. 主安装源失败时自动尝试备选源，或给出明确错误与下一步提示。
6. 安装失败时退出码非 0。

---

## 8. 风险与依赖

| 风险 | 影响 | 缓解 |
|------|------|------|
| 官方安装脚本变更 | 安装失败 | 版本 pin + 定期回归；备选 npm 路径 |
| Node 版本不满足 Qwen | 安装失败 | 预检 `node -v`，提示升级或走 OSS 安装脚本 |
| npm 镜像缺少平台包（OpenCode） | 安装失败 | 回退官方 registry 或提示企业离线包 |
| 企业未提供内网源 | 内外网均慢/失败 | 文档说明 IT 需同步 OSS 脚本或 npm 私服 |
| 明文 Key 落盘 | 安全风险 | 默认 `.env` + 权限收紧 + 安全提示 |

---

## 9. 参考链接

- OpenCode 配置：https://dev.opencode.ai/docs/config/
- OpenCode CLI：https://dev.opencode.ai/docs/cli/
- Qwen Code 配置：https://qwenlm.github.io/qwen-code-docs/en/users/configuration/settings/
- Qwen Code 认证：https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/
- Qwen 安装（仓库）：https://github.com/QwenLM/qwen-code
- Qwen 国内安装脚本：https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen.sh
- npmmirror：https://registry.npmmirror.com
