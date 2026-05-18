# Workspace 元仓库设计文档

**日期**: 2026-05-17
**状态**: 已审批
**范围**: 创建轻量编排仓库 `SmartAIMentor/mentoraix-workspace`，解决团队 onboarding、服务启停和版本协调

---

## 背景

CreatorPilot 工作区包含 7 个独立 Git 仓库（mentoraix、ClawCore、SmartAIMentor、RecSys、platform_data_fetcher、popularpays-mcp-demo、user-post-skills-set），全在 GitHub SmartAIMentor 组织下。当前痛点：

- **Onboarding 繁琐**：新队友需手动 clone 7 个仓库、分别安装依赖、配 3 份不同的 .env
- **服务启停零散**：各服务端口不同、启动命令不同，没有统一入口
- **端口冲突**：ClawCore 和 RecSys 都默认 :8000
- **联调组合不透明**：哪个版本的组合能跑通，全靠记忆

---

## 核心决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 仓库类型 | 纯编排仓库（无业务代码） | 保持关注点分离，不引入额外复杂度 |
| 子仓库管理 | Shell 脚本（git clone），不用 Git Submodule | 零学习成本，日常操作就是 git pull；团队处于早期，不需要精确 SHA 锁定 |
| 编排工具 | GNU Make | 零依赖（macOS/Linux 自带），Makefile 天然适合任务编排 |
| 容器化 | 暂不引入 Docker | 避免增加主线之外的复杂度；各服务直接在本机运行 |
| 端口冲突解决 | 元仓库 .env.example 中统一映射 | ClawCore 改为 :8001，各服务通过环境变量读端口 |

---

## 仓库结构

```
SmartAIMentor/mentoraix-workspace/     ← 新建 GitHub 仓库
├── repos/                             ← 实际 clone 目录（.gitignore）
│   ├── mentoraix/                     ← git clone 产物
│   ├── ClawCore/
│   ├── SmartAIMentor/
│   ├── RecSys/
│   ├── platform_data_fetcher/
│   ├── popularpays-mcp-demo/
│   └── user-post-skills-set/
├── scripts/
│   ├── setup.sh                       ← clone + 安装依赖
│   └── health.sh                      ← 检查各服务运行状态
├── .gitignore
├── .env.example                       ← 合并后的统一环境变量模板
├── Makefile                           ← 所有编排命令
├── CLAUDE.md                          ← workspace 级 AI 助手指引
└── README.md                          ← 一页 onboarding 指南
```

---

## Makefile 目标

```makefile
.PHONY: setup clone install dev start stop status health pull clean

# 首次设置：clone + 安装依赖 + 创建 .env
setup: clone install env

# 克隆所有仓库（已存在的跳过）
clone:
	bash scripts/setup.sh clone

# 安装各仓库依赖
install:
	bash scripts/setup.sh install

# 从 .env.example 创建 .env（如不存在）
env:
	@[ -f .env ] || cp .env.example .env

# 启动所有服务（后台）
dev: start

start:
	bash scripts/setup.sh start

# 停止所有服务
stop:
	bash scripts/setup.sh stop

# 查看所有仓库 git 状态
status:
	@for dir in repos/*/; do \
		echo "=== $$(basename $$dir) ==="; \
		cd "$$dir" && git status -sb && cd ../..; \
	done

# 健康检查：各服务是否在响应
health:
	bash scripts/health.sh

# 拉取所有仓库最新代码
pull:
	@for dir in repos/*/; do \
		echo "Pulling $$(basename $$dir)..."; \
		cd "$$dir" && git pull && cd ../..; \
	done

# 清理（删除所有 clone 的仓库）
clean:
	rm -rf repos/*
```

---

## setup.sh 脚本设计

脚本接收子命令参数，分别处理 clone、install、start、stop。

### Clone 逻辑

```
REPOS 定义 7 个仓库的 org/name 和默认分支：
  mentoraix       master
  ClawCore        main
  SmartAIMentor   main
  RecSys          main
  platform_data_fetcher  main
  popularpays-mcp-demo   main
  user-post-skills-set   main

对每个仓库：
  如果 repos/<name> 不存在 → git clone git@github.com:SmartAIMentor/<name>.git repos/<name>
  如果已存在 → 跳过，打印提示
```

### Install 逻辑

```
mentoraix:   cd repos/mentoraix && npm install
ClawCore:    cd repos/ClawCore && uv sync
SmartAIMentor: cd repos/SmartAIMentor/backend && pip install -r requirements.txt
RecSys:      cd repos/RecSys && pip install -r requirements.txt
其他:        跳过（无标准依赖安装流程）
```

### Start 逻辑

后台启动各服务，将 PID 写入 `.pids` 文件：

```
SmartAIMentor:  cd repos/SmartAIMentor && bash run.sh       → :58888
RecSys:         cd repos/RecSys && python -m app.main       → :8000
ClawCore:       cd repos/ClawCore && uv run uvicorn ...     → :8001（PORT 环境变量）
mentoraix:      cd repos/mentoraix && npm run dev            → :3000（最后启动，依赖其他服务）
```

### Stop 逻辑

读取 `.pids` 文件，逐个 kill。

---

## health.sh 脚本设计

用 `curl -sf` 检查各服务端口是否有响应：

```
mentoraix:       http://localhost:3000       → 200 = OK
SmartAIMentor:   http://localhost:58888/docs → 200 = OK
RecSys:          http://localhost:8000       → 200 = OK
ClawClaw:        http://localhost:8001/health → 200 = OK
```

输出表格：

```
Service         Port    Status
mentoraix       3000    ✓ Running
SmartAIMentor   58888   ✓ Running
RecSys          8000    ✗ Down
ClawCore        8001    ✓ Running
```

---

## .env.example（合并版）

合并现有的 3 份 .env.example，按服务分区注释：

```bash
# === 通用 ===
GEMINI_API_KEY=

# === mentoraix (Next.js :3000) ===
MENTORAIX_API_BASE_URL=http://localhost:58888
CLAWCORE_BASE_URL=http://localhost:8001
CLAWCORE_API_KEY=
OPENAI_API_KEY=
DEEPSEEK_API_KEY=
ORBITAI_BASE_URL=
ORBITAI_API_KEY=

# === SmartAIMentor Backend (FastAPI :58888) ===
POST_BRIDGE_API_KEY=
POST_BRIDGE_BASE_URL=

# === RecSys (Flask :8000) ===
# (uses GEMINI_API_KEY above)

# === ClawCore (FastAPI :8001) ===
PORT=8001
ANTHROPIC_API_KEY=
MOONSHOT_API_KEY=

# === Data Fetcher ===
TIKHUB_API_KEY=
TIKHUB_API_BASE_URL=
```

---

## 端口映射

| 服务 | 原默认端口 | 元仓库端口 | 备注 |
|------|-----------|-----------|------|
| mentoraix | 3000 | 3000 | 不变 |
| SmartAIMentor | 58888 | 58888 | 不变 |
| RecSys | 8000 | 8000 | 不变 |
| ClawCore | 8000 | **8001** | 通过 PORT 环境变量覆盖 |

ClawCore 需要支持从环境变量 `PORT` 读取端口（如果不支持，需要在 ClawCore 仓库中做一个小改动）。

---

## 团队工作流

### 新队友 Onboarding

```bash
git clone git@github.com:SmartAIMentor/mentoraix-workspace.git
cd mentoraix-workspace
make setup    # clone 所有仓库 + 安装依赖 + 创建 .env
# 编辑 .env 填入 API Keys
make dev      # 启动所有服务
```

### 日常开发

```bash
# 拉取最新
make pull

# 在子仓库里正常开发
cd repos/mentoraix
git checkout -b feature/xxx
# ... 开发 ...
git push

# 回到 workspace 启停服务
cd ../..
make dev
```

### 集成者（Leon）日常

```bash
make status    # 看各仓库是否有未提交改动
make pull      # 拉取各仓库最新
make health    # 检查服务是否正常
```

---

## 未来升级路径

如果团队规模增长或需要精确的版本锁定，可以平滑迁移到 Git Submodule：

1. 删除 `repos/` 下的 clone 产物
2. 对每个仓库执行 `git submodule add -b main <url> repos/<name>`
3. `Makefile` 中的 `clone` 改为 `git submodule update --init --recursive`
4. `pull` 改为 `git submodule update --remote --merge`

脚本方案的目录结构与 submodule 方案完全兼容，迁移成本极低。

---

## 不做的事

- **不引入 Docker**：当前阶段直接本机运行，避免 Dockerfile 维护成本
- **不做 CI/CD**：元仓库不包含业务代码，不需要自动化测试
- **不做自动版本锁定**：手动在 README 或 CHANGELOG 中记录已知可用的组合
- **不改子仓库的默认分支**：mentoraix 保持 master，其他保持 main
