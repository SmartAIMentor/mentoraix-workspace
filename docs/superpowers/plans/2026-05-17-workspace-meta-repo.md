# Mentoraix Workspace 元仓库实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建 `SmartAIMentor/mentoraix-workspace` 轻量编排仓库，一条命令完成 7 个子仓库的 clone、依赖安装和服务启停。

**Architecture:** 纯编排仓库，不含业务代码。Makefile 作为统一入口调用 shell 脚本，`repos/` 目录存放 git clone 的子仓库（.gitignore）。无 Docker、无 Submodule。

**Tech Stack:** Bash, GNU Make, Git, GitHub CLI (gh)

---

## 文件清单

| 文件 | 职责 |
|------|------|
| `.gitignore` | 忽略 repos/*、.env、.pids、日志 |
| `.env.example` | 合并 3 份现有 .env 的统一模板 |
| `Makefile` | 编排命令入口（setup/clone/install/dev/stop/status/health/pull/clean） |
| `scripts/setup.sh` | 子命令：clone、install、start、stop |
| `scripts/health.sh` | 检查各服务端口是否响应 |
| `CLAUDE.md` | workspace 级 AI 助手指引 |
| `README.md` | 一页 onboarding 指南 |

---

### Task 1: 创建 GitHub 仓库并克隆到本地

**Files:**
- Create: 本地 `~/Developer/CodeProject/mentoraix-workspace/` 目录

- [ ] **Step 1: 在 GitHub 上创建仓库**

```bash
gh repo create SmartAIMentor/mentoraix-workspace \
  --public \
  --description "Lightweight orchestration workspace for CreatorPilot/Mentoraix dev environment" \
  --clone
```

Expected: 仓库创建成功，本地已 clone 到当前目录的 `mentoraix-workspace/`

- [ ] **Step 2: 创建目录结构**

```bash
cd mentoraix-workspace
mkdir -p repos scripts
```

- [ ] **Step 3: 提交初始结构**

```bash
git add .
git commit -m "chore: initialize workspace repo with directory structure"
git push
```

---

### Task 2: 编写 .gitignore

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: 创建 .gitignore**

```gitignore
# Cloned sub-repos
repos/*

# Local environment
.env
.env.local

# Runtime state
.pids
logs/

# OS
.DS_Store
Thumbs.db

# IDE
.idea/
.vscode/
*.swp
*.swo
```

- [ ] **Step 2: 保留 repos/ 目录本身（但不追踪内容）**

创建一个空 keeper 文件：
```bash
touch repos/.gitkeep
```

- [ ] **Step 3: 提交**

```bash
git add .gitignore repos/.gitkeep
git commit -m "chore: add gitignore for workspace"
```

---

### Task 3: 编写 .env.example

**Files:**
- Create: `.env.example`

合并现有的 3 份 .env.example（根目录、mentoraix、SmartAIMentor），按服务分区。

- [ ] **Step 1: 创建 .env.example**

```bash
# ============================================================
# Mentoraix Workspace 统一环境变量
# 复制为 .env 后填入实际值：cp .env.example .env
# ============================================================

# === 通用 API Keys ===
GEMINI_API_KEY=
ANTHROPIC_API_KEY=
OPENAI_API_KEY=

# === mentoraix (Next.js :3000) ===
# 前端 → SmartAIMentor 后端
MENTORAIX_API_BASE_URL=http://localhost:58888
MENTORAIX_PUBLISH_API_BASE_URL=http://localhost:58889
MENTORAIX_CREATOR_ID=kris
MENTORAIX_CANDIDATE_CREATOR_ID=kris
APP_NAME=mentoraix

# AI Providers（mentoraix AI 路由使用）
DEEPSEEK_API_KEY=
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-chat
ORBITAI_API_KEY=
ORBITAI_BASE_URL=https://aiapi.orbitai.global/v1
ORBITAI_MODEL=gpt-5.4

# mentoraix → ClawCore 智能体
CLAWCORE_BASE_URL=http://localhost:8001
CLAWCORE_API_KEY=

# 发布相关
PUBLISH_DRY_RUN=true
POST_BRIDGE_API_KEY=
POST_BRIDGE_BASE_URL=https://api.post-bridge.com
POST_BRIDGE_VIDEO_COVER_TIMESTAMP_MS=3000
POST_BRIDGE_TIKTOK_DRAFT=false
POST_BRIDGE_TIKTOK_IS_AIGC=false
POST_BRIDGE_INSTAGRAM_IS_TRIAL_REEL=false

# === SmartAIMentor Backend (FastAPI :58888) ===
APP_ENV=development
BACKEND_HOST=0.0.0.0
DATA_DIR=backend/data
UPLOAD_DIR=backend/data/uploads
TASKS_FILE=backend/data/tasks.json

# === RecSys (Flask :8000) ===
# 使用上方的 GEMINI_API_KEY

# === ClawCore (FastAPI :8001) ===
# 端口由启动脚本传入 uvicorn --port，无需在此配置
MOONSHOT_API_KEY=

# === 数据采集 ===
TIKHUB_API_KEY=
TIKHUB_API_BASE_URL=

# === 可选代理 ===
HTTPS_PROXY=
HTTP_PROXY=
ALL_PROXY=
```

- [ ] **Step 2: 提交**

```bash
git add .env.example
git commit -m "chore: add unified env template merged from 3 sources"
```

---

### Task 4: 编写 scripts/setup.sh

**Files:**
- Create: `scripts/setup.sh`

这是核心脚本，处理 clone、install、start、stop 四个子命令。

- [ ] **Step 1: 创建 scripts/setup.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# mentoraix-workspace setup script
# Usage: ./scripts/setup.sh <clone|install|start|stop>
# ============================================================

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPOS_DIR="$REPO_DIR/repos"
PID_FILE="$REPO_DIR/.pids"
LOG_DIR="$REPO_DIR/logs"

ORG="SmartAIMentor"

# 仓库列表: name <tab> default_branch
declare -A REPO_BRANCHES=(
  [mentoraix]=master
  [ClawCore]=main
  [SmartAIMentor]=main
  [RecSys]=main
  [platform_data_fetcher]=main
  [popularpays-mcp-demo]=main
  [user-post-skills-set]=main
)

REPO_NAMES=(mentoraix ClawCore SmartAIMentor RecSys platform_data_fetcher popularpays-mcp-demo user-post-skills-set)

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# --- clone ---
cmd_clone() {
  info "Cloning repositories into $REPOS_DIR/"
  mkdir -p "$REPOS_DIR"

  for name in "${REPO_NAMES[@]}"; do
    local target="$REPOS_DIR/$name"
    if [ -d "$target/.git" ]; then
      ok "$name already exists, skipping"
    else
      info "Cloning $name..."
      git clone "git@github.com:$ORG/$name.git" "$target"
      ok "$name cloned"
    fi
  done
}

# --- install ---
cmd_install() {
  info "Installing dependencies..."

  # mentoraix (Next.js)
  if [ -f "$REPOS_DIR/mentoraix/package.json" ]; then
    info "mentoraix: npm install"
    (cd "$REPOS_DIR/mentoraix" && npm install)
    ok "mentoraix dependencies installed"
  fi

  # ClawCore (Python/uv)
  if [ -f "$REPOS_DIR/ClawCore/pyproject.toml" ]; then
    info "ClawCore: uv sync"
    (cd "$REPOS_DIR/ClawCore" && uv sync)
    ok "ClawCore dependencies installed"
  fi

  # SmartAIMentor (Python)
  if [ -f "$REPOS_DIR/SmartAIMentor/backend/requirements.txt" ]; then
    info "SmartAIMentor: pip install"
    local venv="$REPOS_DIR/SmartAIMentor/.venv"
    if [ ! -d "$venv" ]; then
      python3 -m venv "$venv"
    fi
    (cd "$REPOS_DIR/SmartAIMentor" && source .venv/bin/activate && pip install -r backend/requirements.txt -q)
    ok "SmartAIMentor dependencies installed"
  fi

  # RecSys (Python)
  if [ -f "$REPOS_DIR/RecSys/requirements.txt" ]; then
    info "RecSys: pip install"
    local venv="$REPOS_DIR/RecSys/.venv"
    if [ ! -d "$venv" ]; then
      python3 -m venv "$venv"
    fi
    (cd "$REPOS_DIR/RecSys" && source .venv/bin/activate && pip install -r requirements.txt -q)
    ok "RecSys dependencies installed"
  fi

  # platform_data_fetcher
  if [ -f "$REPOS_DIR/platform_data_fetcher/requirements.txt" ]; then
    info "platform_data_fetcher: pip install"
    local venv="$REPOS_DIR/platform_data_fetcher/.venv"
    if [ ! -d "$venv" ]; then
      python3 -m venv "$venv"
    fi
    (cd "$REPOS_DIR/platform_data_fetcher" && source .venv/bin/activate && pip install -r requirements.txt -q)
    ok "platform_data_fetcher dependencies installed"
  fi

  # popularpays-mcp-demo (Node.js)
  if [ -f "$REPOS_DIR/popularpays-mcp-demo/package.json" ]; then
    info "popularpays-mcp-demo: npm install"
    (cd "$REPOS_DIR/popularpays-mcp-demo" && npm install)
    ok "popularpays-mcp-demo dependencies installed"
  fi

  ok "All dependencies installed"
}

# --- start ---
cmd_start() {
  mkdir -p "$LOG_DIR"
  # 清空旧的 PID 文件
  : > "$PID_FILE"

  # 加载 .env（如果存在）
  local env_file="$REPO_DIR/.env"
  if [ -f "$env_file" ]; then
    set -a
    source "$env_file"
    set +a
  fi

  # 1. SmartAIMentor 后端 (:58888)
  if [ -f "$REPOS_DIR/SmartAIMentor/backend/run.sh" ]; then
    info "Starting SmartAIMentor backend on :58888..."
    (cd "$REPOS_DIR/SmartAIMentor" && bash backend/run.sh) > "$LOG_DIR/smartaimentor.log" 2>&1 &
    echo "smartaimentor:$!" >> "$PID_FILE"
    sleep 2
    ok "SmartAIMentor backend started (PID $!)"
  fi

  # 2. RecSys (:8000)
  if [ -f "$REPOS_DIR/RecSys/app/main.py" ]; then
    info "Starting RecSys on :8000..."
    (cd "$REPOS_DIR/RecSys" && python3 -m app.main) > "$LOG_DIR/recsys.log" 2>&1 &
    echo "recsys:$!" >> "$PID_FILE"
    sleep 1
    ok "RecSys started (PID $!)"
  fi

  # 3. ClawCore (:8001 — 避免与 RecSys 冲突)
  if [ -f "$REPOS_DIR/ClawCore/pyproject.toml" ]; then
    info "Starting ClawCore on :8001..."
    (cd "$REPOS_DIR/ClawCore" && uv run uvicorn clawtok.app:create_app --factory --host 0.0.0.0 --port 8001) > "$LOG_DIR/clawcore.log" 2>&1 &
    echo "clawcore:$!" >> "$PID_FILE"
    sleep 2
    ok "ClawCore started (PID $!)"
  fi

  # 4. mentoraix 前端 (:3000) — 最后启动
  if [ -f "$REPOS_DIR/mentoraix/package.json" ]; then
    info "Starting mentoraix on :3000..."
    (cd "$REPOS_DIR/mentoraix" && npm run dev) > "$LOG_DIR/mentoraix.log" 2>&1 &
    echo "mentoraix:$!" >> "$PID_FILE"
    sleep 3
    ok "mentoraix started (PID $!)"
  fi

  ok "All services started. PIDs saved to .pids"
  info "Logs: $LOG_DIR/"
}

# --- stop ---
cmd_stop() {
  if [ ! -f "$PID_FILE" ]; then
    warn "No .pids file found. Nothing to stop."
    return
  fi

  info "Stopping services..."
  while IFS=: read -r name pid; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      ok "$name (PID $pid) stopped"
    else
      warn "$name (PID $pid) already gone"
    fi
  done < "$PID_FILE"

  rm -f "$PID_FILE"
  ok "All services stopped"
}

# --- main ---
case "${1:-help}" in
  clone)   cmd_clone ;;
  install) cmd_install ;;
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  help|*)
    echo "Usage: $0 <clone|install|start|stop>"
    echo "  clone   — git clone all 7 repos into repos/"
    echo "  install — install dependencies for each repo"
    echo "  start   — start all services in background"
    echo "  stop    — stop all background services"
    ;;
esac
```

- [ ] **Step 2: 设置可执行权限**

```bash
chmod +x scripts/setup.sh
```

- [ ] **Step 3: 提交**

```bash
git add scripts/setup.sh
git commit -m "feat: add setup script with clone/install/start/stop commands"
```

---

### Task 5: 编写 scripts/health.sh

**Files:**
- Create: `scripts/health.sh`

- [ ] **Step 1: 创建 scripts/health.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# mentoraix-workspace health check
# Checks each service port for a responsive HTTP status
# ============================================================

check_port() {
  local name="$1" port="$2" url="$3"
  if curl -sf -o /dev/null -m 3 "$url" 2>/dev/null; then
    printf "%-20s %-8s \033[1;32m✓ Running\033[0m\n" "$name" "$port"
  else
    printf "%-20s %-8s \033[1;31m✗ Down\033[0m\n" "$name" "$port"
  fi
}

echo "========================================="
echo " Service Health Check"
echo "========================================="
echo ""

check_port "SmartAIMentor" "58888" "http://localhost:58888/docs"
check_port "RecSys"        "8000"  "http://localhost:8000"
check_port "ClawCore"      "8001"  "http://localhost:8001/health"
check_port "mentoraix"     "3000"  "http://localhost:3000"

echo ""
echo "========================================="
```

- [ ] **Step 2: 设置可执行权限**

```bash
chmod +x scripts/health.sh
```

- [ ] **Step 3: 提交**

```bash
git add scripts/health.sh
git commit -m "feat: add health check script for all services"
```

---

### Task 6: 编写 Makefile

**Files:**
- Create: `Makefile`

- [ ] **Step 1: 创建 Makefile**

```makefile
.PHONY: setup clone install env dev start stop status health pull clean help

REPO_DIR := $(shell pwd)
REPOS    := mentoraix ClawCore SmartAIMentor RecSys platform_data_fetcher popularpays-mcp-demo user-post-skills-set

# === 首次设置（clone + 依赖 + .env） ===
setup: clone install env
	@echo ""
	@echo "✓ Setup complete! Next steps:"
	@echo "  1. Edit .env with your API keys"
	@echo "  2. Run 'make dev' to start all services"

# === 克隆所有仓库 ===
clone:
	@bash scripts/setup.sh clone

# === 安装各仓库依赖 ===
install:
	@bash scripts/setup.sh install

# === 从 .env.example 创建 .env ===
env:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created .env from .env.example — edit it with your API keys"; \
	else \
		echo ".env already exists, skipping"; \
	fi

# === 启动所有服务（后台） ===
dev: start

start:
	@bash scripts/setup.sh start

# === 停止所有服务 ===
stop:
	@bash scripts/setup.sh stop

# === 查看所有仓库 git 状态 ===
status:
	@for dir in repos/*/; do \
		if [ -d "$$dir/.git" ]; then \
			echo "=== $$(basename $$dir) ==="; \
			cd "$$dir" && git status -sb && cd "$(REPO_DIR)"; \
			echo ""; \
		fi; \
	done

# === 健康检查 ===
health:
	@bash scripts/health.sh

# === 拉取所有仓库最新代码 ===
pull:
	@for dir in repos/*/; do \
		if [ -d "$$dir/.git" ]; then \
			echo "Pulling $$(basename $$dir)..."; \
			cd "$$dir" && git pull && cd "$(REPO_DIR)"; \
		fi; \
	done
	@echo "✓ All repos pulled"

# === 清理所有 clone 的仓库 ===
clean:
	@bash scripts/setup.sh stop 2>/dev/null || true
	@rm -rf repos/*
	@touch repos/.gitkeep
	@echo "✓ Cleaned repos/ directory"

# === 帮助 ===
help:
	@echo "Mentoraix Workspace Commands"
	@echo ""
	@echo "  make setup    First-time setup (clone + install + .env)"
	@echo "  make dev      Start all services"
	@echo "  make stop     Stop all services"
	@echo "  make status   Git status of all repos"
	@echo "  make health   Check if services are responding"
	@echo "  make pull     git pull all repos"
	@echo "  make clean    Remove all cloned repos"
	@echo ""
```

- [ ] **Step 2: 提交**

```bash
git add Makefile
git commit -m "feat: add Makefile with all orchestration targets"
```

---

### Task 7: 编写 CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: 创建 CLAUDE.md**

```markdown
# CLAUDE.md — Mentoraix Workspace

## 概览

这是一个**纯编排仓库**，不含业务代码。通过 Makefile 和 shell 脚本管理 7 个独立子仓库的联调生命周期。

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
| SmartAIMentor 后端 | :58888 | `bash backend/run.sh` |
| RecSys | :8000 | `python -m app.main` |
| ClawCore | :8001 | `uv run uvicorn ... --port 8001` |
| mentoraix 前端 | :3000 | `npm run dev` |

**端口冲突**：ClawCore 默认 :8000 与 RecSys 冲突，本 workspace 将 ClawCore 映射到 :8001。

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
- `CLAWCORE_BASE_URL=http://localhost:8001`（不是默认的 8000）
- `MENTORAIX_API_BASE_URL=http://localhost:58888`
- 各 API Key 需手动填入 .env

## 不做的事

- 不引入 Docker / Git Submodule
- 不包含 CI/CD
- 不修改子仓库的代码
```

- [ ] **Step 2: 提交**

```bash
git add CLAUDE.md
git commit -m "docs: add workspace-level CLAUDE.md"
```

---

### Task 8: 编写 README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: 创建 README.md**

```markdown
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
```

- [ ] **Step 2: 提交**

```bash
git add README.md
git commit -m "docs: add onboarding README"
```

---

### Task 9: 最终验证

- [ ] **Step 1: 确认文件结构完整**

```bash
find . -not -path './.git/*' -not -path './repos/*' | sort
```

Expected:
```
.
./.env.example
./.gitignore
./CLAUDE.md
./Makefile
./README.md
./repos
./repos/.gitkeep
./scripts
./scripts/health.sh
./scripts/setup.sh
```

- [ ] **Step 2: 验证脚本语法**

```bash
bash -n scripts/setup.sh && echo "setup.sh: OK"
bash -n scripts/health.sh && echo "health.sh: OK"
```

Expected: 两个脚本都输出 OK

- [ ] **Step 3: 验证 Makefile 语法**

```bash
make help
```

Expected: 显示所有命令列表

- [ ] **Step 4: 推送到 GitHub**

```bash
git push
```

Expected: 所有文件推送到 `SmartAIMentor/mentoraix-workspace` 仓库
