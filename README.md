# Mentoraix Workspace

面向 CreatorPilot 团队的**纯编排仓库**（不含业务代码）。一条命令完成子仓库 clone、依赖安装、全部服务启停与健康检查。

> **当前架构**：前端 mentoraixs(:3000) + 5 个后端服务。新 agent 栈（Hermes + OpenViking + Adapter）已**正式替换**旧 ClawCore，ClawCore 已下线。

## 快速开始

```bash
# 1. 克隆本仓库
git clone git@github.com:SmartAIMentor/mentoraix-workspace.git
cd mentoraix-workspace

# 2. 一键设置（clone 6 个子仓库 + 安装依赖 + 创建 .env）
make setup

# 3. 填入 API Keys（编辑 .env，见下方「环境变量」）
vim .env

# 4. 启动所有服务（后端 + 前端）
make dev

# 5. 检查状态
make health
```

启动成功后访问：
- 前端：http://localhost:3000
- publish-service API 文档：http://localhost:58888/docs
- 后端服务日志见各服务 logs/（agent 栈日志在 `hermes-clawcore-adapter/logs/`）

## 命令速查

| 命令 | 作用 |
|------|------|
| `make setup` | 首次设置（clone + 安装依赖 + .env） |
| `make dev` | 启动所有服务（后端 + 前端） |
| `make stop` | 停止所有服务 |
| `make health` | 检查各服务是否在响应 |
| `make status` | 查看各仓库 git 状态 |
| `make pull` | 拉取所有仓库最新代码 |
| `make root` | 查看当前生效的仓库根 |
| `make clean` | 清除所有 clone 的仓库 |

## 服务拓扑（当前）

| 服务 | 端口 | 仓库 | 说明 |
|------|:----:|------|------|
| **mentoraixs** (Next.js) | :3000 | `SmartAIMentor/mentoraixs` | 前端主应用（五标签页） |
| **adapter** (FastAPI) | :8003 | `agent-runtime-lab` | **智能体入口**（ClawCore 兼容契约 `/api/chat` + `/api/sessions`） |
| **hermes** (agent runtime) | :8002 | `agent-runtime-lab` | 无状态执行器（skill 加载/执行引擎） |
| **openviking** | :1933 | `agent-runtime-lab` | 记忆/会话/人格/上下文（官方 SDK，多租户） |
| **publish-service** (FastAPI) | :58888 | `SmartAIMentor/publish-service` | 多平台发布后端（Bundle Social） |
| **mentor-recsys** (FastAPI) | :8000 | `SmartAIMentor/mentor-recsys` | Creator Hotspot 推荐服务 |

> **ClawCore 已下线**（原 :8001）。智能体能力由 Hermes + OpenViking + Adapter 承接，前端经 `CLAWCORE_BASE_URL=:8003` 连接，契约不变。

### 智能体 skill 与后端依赖

新 agent 加载 13 个官方 skill（Hermes 引擎），其中带脚本的 skill 执行时会真实调用本地后端取业务数据：

| 官方 skill | 类型 | 依赖后端 |
|-----------|:----:|---------|
| `creator-hotspot-api` | 带脚本 | mentor-recsys (:8000) |
| `publish-to-social` | 带脚本 | publish-service (:58888) |
| `instagram-creator-fetch` | 带脚本 | 外部 Gemini API（无需本地端口） |
| 其余 10 个（指令/知识型） | 指令/知识 | 仅需 Hermes 创作能力 |

> `make dev` 已覆盖全部 5 个后端，上述 skill 均可真实执行。

## 目录结构

```
mentoraix-workspace/
├── repos/                       ← 子仓库（git clone 产物）
│   ├── mentoraixs/
│   ├── publish-service/
│   ├── mentor-recsys/
│   ├── user-post-skills-set/
│   └── agent-runtime-lab/       ← 新 agent 栈（Hermes+OpenViking+Adapter 编排）
├── scripts/
│   ├── setup.sh                 ← clone/install/start/stop
│   └── health.sh                ← 服务健康检查
├── .env.example                 ← 环境变量模板
├── Makefile                     ← 命令入口
├── CLAUDE.md                    ← AI 助手指引
├── docs/                        ← 架构 / 切换 / 人设注入文档
└── README.md
```

## 仓库根布局（自动探测）

`make` 和 `scripts/setup.sh` 会自动探测子仓库位置，无需手动配置：

- **标准布局（默认）**：子仓在 `mentoraix-workspace/repos/` 下。新队友 `make setup` 会 clone 到这里。
- **平铺布局（本机）**：子仓与 `mentoraix-workspace/` 同级（平铺在父目录）。脚本检测到 `repos/` 为空、且父目录存在子仓时，自动改用父目录。

用 `make root` 查看当前生效的仓库根；也可显式覆盖：`REPOS_ROOT=/path make pull`。

> `make clean` 始终只清理标准 `repos/` 目录，不会触碰平铺布局下的兄弟仓库。

## 队友快速上手

### 前置条件

确保本机已安装：`git`、`make`、`Node.js 18+`、`pnpm`、`Python 3.12+`、`uv`（Python 包管理）

```bash
# 检查是否就绪
git --version && make --version && node -v && pnpm -v && python3 -V && uv --version
```

### 首次设置（3 分钟）

```bash
# 1. 克隆 workspace
git clone git@github.com:SmartAIMentor/mentoraix-workspace.git
cd mentoraix-workspace

# 2. 一键 clone 所有子仓库 + 安装依赖 + 生成 .env
make setup

# 3. 填写 API Keys（向 Leon 索要）
#    必填：GEMINI_API_KEY、各后端所需 key（见 .env.example 注释）
vim .env

# 4. 启动所有服务（后端 + 前端）
make dev

# 5. 确认服务正常（期望 6 个服务全部 ✓ Running）
make health
```

### 日常开发流程

```
你的子仓库（独立开发）          workspace（联调）
─────────────────────          ──────────────
git checkout -b feat/xxx       make pull      ← 拉取最新代码
编写代码、提交、推送              make stop      ← 停旧服务
git push                       make dev       ← 启新服务
                               make health    ← 确认正常
```

**关键原则：** 你在自己的子仓库里正常 `git push`，联调时在 workspace 里 `make pull` 拉取所有人的更新。

### 常见问题

**Q: `make setup` 报权限错误？**
A: 检查是否有 SmartAIMentor 组织的 GitHub 访问权限，确认 SSH key 已配置：`ssh -T git@github.com`

**Q: 某个服务起不来？**
A: 前端/业务日志：`cat logs/<服务名>.log`；agent 栈日志：`cat agent-runtime-lab/hermes-clawcore-adapter/logs/<服务名>.log`

**Q: 端口被占用？**
A: `make stop` 停服务，或 `lsof -i :<端口>` 找到占用的进程手动 kill

**Q: 只想启动某几个服务？**
A: agent 栈 5 个后端支持选择性启动：`SKIP=mentor-recsys bash agent-runtime-lab/hermes-clawcore-adapter/scripts/stack-up.sh` 或 `ONLY=adapter,hermes ...`。前端如需单独启动直接 `cd repos/mentoraixs && pnpm dev`。

## 深入了解

- **[项目全景指南](docs/PROJECT_GUIDE.md)** — 架构拓扑、各仓库职责、AI 供应商链、数据流、设计决策。5 分钟读懂整个系统。
- **[Agent 切换指南](docs/AGENT-CUTOVER.md)** — ClawCore → Hermes+OpenViking 的迁移说明与新服务接入方法。
- **[M 人设注入方案](docs/PERSONA-INJECTION.md)** — 给新 agent 注入产品人格的待实施方案。
- **[设计文档](docs/superpowers/specs/)** — 各功能的设计 spec 和实现计划

## 子仓库列表

所有仓库均在 [SmartAIMentor](https://github.com/SmartAIMentor) 组织下：

- [Mentoraixs](https://github.com/SmartAIMentor/Mentoraixs) — Next.js 前端主应用（SaaS 框架，含认证、数据库、国际化）
- [agent-runtime-lab](https://github.com/SmartAIMentor/agent-runtime-lab) — **新 agent 栈**：Hermes + OpenViking + Adapter（含编排脚本）
- [publish-service](https://github.com/SmartAIMentor/publish-service) — FastAPI 多平台发布后端（Bundle Social）
- [mentor-recsys](https://github.com/SmartAIMentor/mentor-recsys) — AI Creator Mentor 推荐系统（Creator Hotspot）
- [user-post-skills-set](https://github.com/SmartAIMentor/user-post-skills-set) — 智能体技能包（13 个官方 skill）

> ClawCore 已下线并从子仓库列表移除。其能力由 agent-runtime-lab 承接。
