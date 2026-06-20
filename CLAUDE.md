# CLAUDE.md — Mentoraix Workspace

## 概览

这是一个**纯编排仓库**，不含业务代码。通过 Makefile 和 shell 脚本管理 5 个独立子仓库的联调生命周期。
**开始工作前，先读 [docs/PROJECT_GUIDE.md](docs/PROJECT_GUIDE.md)** — 5 分钟了解架构拓扑、各仓库职责、AI 供应商链、数据流和设计决策。

## 仓库结构

```
mentoraix-workspace/
├── repos/            ← git clone 的子仓库（.gitignore 不追踪）
├── scripts/          ← 编排脚本
├── .env              ← 本地环境变量（不提交）
├── .env.example      ← 环境变量模板
├── Makefile          ← 统一命令入口
└── logs/             ← 服务日志（不提交）
```

## 服务拓扑

| 服务 | 端口 | 启动方式 |
|------|------|----------|
| publish-service | :58888 | `bash backend/run.sh` |
| mentor-recsys | :8000 | `python -m app.main` |
| ClawCore | :8001 | `uv run uvicorn ... --port 8001` |
| mentoraixs 前端 | :3000 | `pnpm dev` |

**端口冲突**：ClawCore 默认 :8000 与 mentor-recsys 冲突，本 workspace 将 ClawCore 映射到 :8001。

## 常用命令

```bash
make setup    # 首次设置
make dev      # 启动所有服务
make stop     # 停止所有服务
make health   # 健康检查
make status   # 查看各仓库 git 状态
make pull     # 拉取最新代码
```

## 子仓库独立开发

队友在各自的仓库独立开发，不直接操作本仓库。集成者（workspace 维护者）负责：
- `make pull` 拉取各仓库最新
- `make health` 确认联调通过
- 更新本仓库的文档和配置（如有变化）

## 环境变量

合并自 3 份 .env.example，按服务分区。关键变量：
- `CLAWCORE_BASE_URL=http://localhost:8001`（不是默认的 8000）— mentoraixs 连 ClawCore 的**唯一**变量（主对话框 + legacy 路由共用）；不要再引入 `CLAWCORE_API_URL`（曾混入一份 :8090 副本连不上）
- `MENTORAIX_API_BASE_URL=http://localhost:58888`
- 各 API Key 需手动填入 .env

## 不做的事

- 不引入 Docker / Git Submodule
- 不包含 CI/CD
- 不修改子仓库的代码
