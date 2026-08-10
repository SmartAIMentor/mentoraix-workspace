#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# mentoraix-workspace setup script
# Usage: ./scripts/setup.sh <clone|install|start|stop>
# ============================================================

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# 仓库根自动探测（与 Makefile 同策略）：默认 $REPO_DIR/repos；若 repos/ 为空且父目录存在
# 平铺子仓（mentoraixs/.git），自动改用父目录。可用环境变量 REPOS_ROOT 显式覆盖。
detect_repos_root() {
  if [ -d "$REPO_DIR/repos/mentoraixs/.git" ]; then
    printf '%s' "$REPO_DIR/repos"
  elif [ -d "$REPO_DIR/../mentoraixs/.git" ]; then
    (cd "$REPO_DIR/.." && pwd)
  else
    printf '%s' "$REPO_DIR/repos"
  fi
}
REPOS_ROOT="${REPOS_ROOT:-$(detect_repos_root)}"
PID_FILE="$REPO_DIR/.pids"
LOG_DIR="$REPO_DIR/logs"

ORG="SmartAIMentor"

# 仓库列表: name = default_branch
# agent-runtime-lab = 新 agent 栈编排仓（Hermes+OpenViking+Adapter），独立 git 仓库
declare -A REPO_BRANCHES=(
  [mentoraixs]=master
  [publish-service]=main
  [mentor-recsys]=main
  [user-post-skills-set]=main
  [agent-runtime-lab]=main
)

REPO_NAMES=(mentoraixs publish-service mentor-recsys user-post-skills-set agent-runtime-lab)

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# --- clone ---
cmd_clone() {
  info "Cloning repositories into $REPOS_ROOT/"
  mkdir -p "$REPOS_ROOT"

  for name in "${REPO_NAMES[@]}"; do
    local target="$REPOS_ROOT/$name"
    if [ -d "$target/.git" ]; then
      ok "$name already exists, skipping"
    else
      info "Cloning $name..."
      git clone "git@github.com:$ORG/$name.git" "$target"
      local branch="${REPO_BRANCHES[$name]:-main}"
      git -C "$target" checkout "$branch" 2>/dev/null || true
      ok "$name cloned (branch: $branch)"
    fi
  done
}

# --- install ---
cmd_install() {
  info "Installing dependencies..."

  # mentoraixs (Next.js / pnpm)
  if [ -f "$REPOS_ROOT/mentoraixs/package.json" ]; then
    info "mentoraixs: pnpm install"
    (cd "$REPOS_ROOT/mentoraixs" && pnpm install)
    ok "mentoraixs dependencies installed"
  fi

  # ClawCore removed — decommissioned; replaced by adapter(:8003)+OpenViking.

  # publish-service (Python)
  if [ -f "$REPOS_ROOT/publish-service/backend/requirements.txt" ]; then
    info "publish-service: pip install"
    local venv="$REPOS_ROOT/publish-service/.venv"
    if [ ! -d "$venv" ]; then
      python3 -m venv "$venv"
    fi
    (cd "$REPOS_ROOT/publish-service" && source .venv/bin/activate && pip install -r backend/requirements.txt -q)
    ok "publish-service dependencies installed"
  fi

  # mentor-recsys (Python)
  if [ -f "$REPOS_ROOT/mentor-recsys/requirements.txt" ]; then
    info "mentor-recsys: pip install"
    local venv="$REPOS_ROOT/mentor-recsys/.venv"
    if [ ! -d "$venv" ]; then
      python3 -m venv "$venv"
    fi
    (cd "$REPOS_ROOT/mentor-recsys" && source .venv/bin/activate && pip install -r requirements.txt -q)
    ok "mentor-recsys dependencies installed"
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

  # ── 新 agent 栈后端（Hermes/OpenViking/Adapter + publish-service + mentor-recsys）──
  # 统一委托给 agent-runtime-lab/hermes-clawcore-adapter/scripts/stack-up.sh
  # 该脚本按依赖顺序拉起 5 个后端（openviking:1933 / hermes:8002 / adapter:8003 /
  # publish-service:58888 / mentor-recsys:8000），已在跑的服务自动跳过，并做健康检查。
  if [ -f "$REPOS_ROOT/agent-runtime-lab/hermes-clawcore-adapter/scripts/stack-up.sh" ]; then
    info "Starting agent stack backends via stack-up.sh (5 services)..."
    bash "$REPOS_ROOT/agent-runtime-lab/hermes-clawcore-adapter/scripts/stack-up.sh"
    ok "agent stack backends started (see hermes-clawcore-adapter/logs/)"
  else
    warn "agent-runtime-lab not found at $REPOS_ROOT/agent-runtime-lab — 新 agent 栈后端未启动（前端的对话/会话将不可用）"
  fi

  # ── mentoraixs 前端 (:3000) — 最后启动 ──
  if [ -f "$REPOS_ROOT/mentoraixs/package.json" ]; then
    info "Starting mentoraixs on :3000..."
    (cd "$REPOS_ROOT/mentoraixs" && pnpm dev) > "$LOG_DIR/mentoraixs.log" 2>&1 &
    echo "mentoraixs:$!" >> "$PID_FILE"
    sleep 3
    ok "mentoraixs started (PID $!)"
  fi

  ok "All services started. PIDs saved to .pids"
  info "Logs: $LOG_DIR/ (agent stack logs 在 hermes-clawcore-adapter/logs/)"
}

# --- stop ---
cmd_stop() {
  # 1. 停 agent 栈后端（委托 agent-runtime-lab stop.sh，覆盖 5 服务端口）
  if [ -f "$REPOS_ROOT/agent-runtime-lab/hermes-clawcore-adapter/stop.sh" ]; then
    info "Stopping agent stack backends (agent-runtime-lab/stop.sh)..."
    bash "$REPOS_ROOT/agent-runtime-lab/hermes-clawcore-adapter/stop.sh" || true
  fi

  # 2. 停本地前台服务（mentoraixs 等）
  if [ ! -f "$PID_FILE" ]; then
    ok "No local services to stop (agent stack already handled above)."
    return
  fi

  info "Stopping local services..."
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
    echo "  clone   — git clone all 6 repos into repos/"
    echo "  install — install dependencies for each repo"
    echo "  start   — start all backend services (agent stack + frontend)"
    echo "  stop    — stop all services"
    ;;
esac
