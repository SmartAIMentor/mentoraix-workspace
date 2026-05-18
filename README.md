# Mentoraix Workspace

面向 CreatorPilot 团队的轻量联调环境。一条命令完成 7 个子仓库的 clone、依赖安装和服务启停。

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
| mentoraix (Next.js) | 3000 | `SmartAIMentor/mentoraix` |
| SmartAIMentor 后端 (FastAPI) | 58888 | `SmartAIMentor/SmartAIMentor` |
| RecSys (Flask) | 8000 | `SmartAIMentor/RecSys` |
| ClawCore (FastAPI) | 8001 | `SmartAIMentor/ClawCore` |

> ClawCore 默认端口 8000，本 workspace 将其映射到 8001 以避免与 RecSys 冲突。

## 目录结构

```
mentoraix-workspace/
├── repos/                       ← 子仓库（git clone 产物）
│   ├── mentoraix/
│   ├── ClawCore/
│   ├── SmartAIMentor/
│   ├── RecSys/
│   ├── platform_data_fetcher/
│   ├── popularpays-mcp-demo/
│   └── user-post-skills-set/
├── scripts/
│   ├── setup.sh                 ← clone/install/start/stop
│   └── health.sh                ← 服务健康检查
├── .env.example                 ← 环境变量模板
├── Makefile                     ← 命令入口
├── CLAUDE.md                    ← AI 助手指引
└── README.md
```

## 团队工作流

### 新队友加入

```bash
make setup   # 搞定一切
make dev     # 跑起来
```

### 日常开发

在自己的子仓库里正常开发、推送。需要联调时：

```bash
make pull    # 拉取所有人最新的代码
make dev     # 重启服务
make health  # 确认一切正常
```

## 子仓库列表

所有仓库均在 [SmartAIMentor](https://github.com/SmartAIMentor) 组织下：

- [mentoraix](https://github.com/SmartAIMentor/mentoraix) — Next.js 前端主应用
- [ClawCore](https://github.com/SmartAIMentor/ClawCore) — Python 智能体核心
- [SmartAIMentor](https://github.com/SmartAIMentor/SmartAIMentor) — FastAPI 后端
- [RecSys](https://github.com/SmartAIMentor/RecSys) — Flask 推荐服务
- [platform_data_fetcher](https://github.com/SmartAIMentor/platform_data_fetcher) — 数据采集
- [popularpays-mcp-demo](https://github.com/SmartAIMentor/popularpays-mcp-demo) — MCP 爬虫
- [user-post-skills-set](https://github.com/SmartAIMentor/user-post-skills-set) — 智能体技能
