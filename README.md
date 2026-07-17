# Mentoraix Workspace

面向 CreatorPilot 团队的轻量联调环境。一条命令完成 5 个子仓库的 clone、依赖安装和服务启停。

## 快速开始

```bash
# 1. 克隆本仓库
git clone git@github.com:SmartAIMentor/mentoraix-workspace.git
cd mentoraix-workspace

# 2. 一键设置（clone 子仓库 + 安装依赖 + 创建 .env）
make setup

# 3. 填入 API Keys
# 编辑 .env，填入 GEMINI_API_KEY、CLAWCORE_API_KEY 等

# 4. 启动所有服务
make dev

# 5. 检查状态
make health
```

## 命令速查

| 命令 | 作用 |
|------|------|
| `make setup` | 首次设置（clone + 安装依赖 + .env） |
| `make dev` | 启动所有服务 |
| `make stop` | 停止所有服务 |
| `make health` | 检查各服务是否在响应 |
| `make status` | 查看各仓库 git 状态 |
| `make pull` | 拉取所有仓库最新代码 |
| `make clean` | 清除所有 clone 的仓库 |

## 服务端口

| 服务 | 端口 | 仓库 |
|------|------|------|
| mentoraixs (Next.js) | 3000 | `SmartAIMentor/Mentoraixs` |
| publish-service (FastAPI) | 58888 | `SmartAIMentor/publish-service` |
| mentor-recsys (FastAPI) | 8000 | `SmartAIMentor/mentor-recsys` |
| ClawCore (FastAPI) | 8001 | `SmartAIMentor/ClawCore` |

> ClawCore 默认端口 8000，本 workspace 将其映射到 8001 以避免与 mentor-recsys 冲突。

## 目录结构

```
mentoraix-workspace/
├── repos/                       ← 子仓库（git clone 产物）
│   ├── mentoraixs/
│   ├── ClawCore/
│   ├── publish-service/
│   ├── mentor-recsys/
│   └── user-post-skills-set/
├── scripts/
│   ├── setup.sh                 ← clone/install/start/stop
│   └── health.sh                ← 服务健康检查
├── .env.example                 ← 环境变量模板
├── Makefile                     ← 命令入口
├── CLAUDE.md                    ← AI 助手指引
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
git --version && make --version && node -v && pnpm -v && python3 -v && uv --version
```

### 首次设置（3 分钟）

```bash
# 1. 克隆 workspace
git clone git@github.com:SmartAIMentor/mentoraix-workspace.git
cd mentoraix-workspace

# 2. 一键 clone 所有子仓库 + 安装依赖 + 生成 .env
make setup

# 3. 填写 API Keys（向 Leon 索要）
#    必填项：GEMINI_API_KEY、ANTHROPIC_API_KEY
#    按需填写：CLAWCORE_API_KEY、DEEPSEEK_API_KEY 等
vim .env

# 4. 启动所有服务
make dev

# 5. 确认服务正常
make health
# 期望输出：4 个服务全部 ✓ Running
```

启动成功后访问：
- 前端：http://localhost:3000
- 后端 API 文档：http://localhost:58888/docs

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
A: 查看日志：`cat logs/<服务名>.log`（如 `logs/mentoraixs.log`）

**Q: 端口被占用？**
A: `make stop` 停服务，或 `lsof -i :3000` 找到占用的进程手动 kill

**Q: 只想启动某几个服务？**
A: 目前 `make dev` 启动全部。如需单独启动，直接 cd 进 repos/ 对应目录手动运行即可

## 深入了解

- **[项目全景指南](docs/PROJECT_GUIDE.md)** — 架构拓扑、各仓库职责、AI 供应商链、数据流、设计决策。5 分钟读懂整个系统。
- **[设计文档](docs/superpowers/specs/)** — 各功能的设计 spec 和实现计划

## 子仓库列表

所有仓库均在 [SmartAIMentor](https://github.com/SmartAIMentor) 组织下：

- [Mentoraixs](https://github.com/SmartAIMentor/Mentoraixs) — Next.js 前端主应用（SaaS 框架，含认证、数据库、国际化）
- [ClawCore](https://github.com/SmartAIMentor/ClawCore) — Python 智能体核心
- [publish-service](https://github.com/SmartAIMentor/publish-service) — FastAPI 多平台发布后端（Bundle Social）
- [mentor-recsys](https://github.com/SmartAIMentor/mentor-recsys) — AI Creator Mentor 推荐系统
- [user-post-skills-set](https://github.com/SmartAIMentor/user-post-skills-set) — 智能体技能
