# CLAUDE.md — Mentoraix Workspace

## 概览

这是一个**纯编排仓库**，不含业务代码。通过 Makefile 和 shell 脚本管理 6 个独立子仓库的联调生命周期。
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

## 仓库根自动探测

`make` / `scripts/setup.sh` 自动探测子仓库位置：默认 `repos/`（标准 clone 位置）；若 `repos/` 为空且父目录存在平铺子仓（本机布局），自动改用父目录。`make root` 查看当前值；可 `REPOS_ROOT=path make ...` 显式覆盖。`status`/`pull` 按 `$(REPOS)` 列表（6 个正式仓）精确遍历；`make clean` 只清 `repos/`，不碰平铺兄弟仓。

## 服务拓扑

| 服务 | 端口 | 启动方式 |
|------|------|----------|
| mentoraixs 前端 | :3000 | `pnpm dev` |
| adapter (智能体入口) | :8003 | `agent-runtime-lab/.../scripts/stack-up.sh` |
| hermes (agent runtime) | :8002 | 同上（stack-up.sh） |
| openviking (记忆) | :1933 | 同上（stack-up.sh） |
| publish-service | :58888 | 同上（stack-up.sh） |
| mentor-recsys | :8000 | 同上（stack-up.sh） |

**ClawCore 已下线**（原 :8001），能力由 Hermes+OpenViking+Adapter 承接。5 个后端统一由 `agent-runtime-lab/hermes-clawcore-adapter/scripts/stack-up.sh` 按依赖顺序拉起（已在跑自动跳过 + 健康检查）。

## 常用命令

```bash
make setup    # 首次设置
make dev      # 启动所有服务（5 后端 + 前端）
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

合并自各仓库 .env.example，按服务分区。关键变量：
- `CLAWCORE_BASE_URL=http://localhost:8003` — mentoraixs 连智能体 Adapter 的**唯一**变量（主对话框 + legacy 路由共用）；不要再引入 `CLAWCORE_API_URL`（曾混入一份 :8090 副本连不上）
- `MENTORAIX_API_BASE_URL=http://localhost:58888`
- Adapter/OpenViking 栈变量：`HERMES_BASE_URL` / `HERMES_API_KEY` / `OPENVIKING_ENDPOINT` / `OV_ROOT_KEY` / `OV_ACCOUNT` / `ADAPTER_PORT` / `JWT_SECRET` / `DEV_MODE`（stack-up.sh 大多自动注入，见 `.env.example`）
- 各 API Key 需手动填入 .env

## 不做的事

- 不引入 Docker / Git Submodule
- 不包含 CI/CD
- 不修改子仓库的代码
