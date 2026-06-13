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

# 仓库列表: name = default_branch
declare -A REPO_BRANCHES=(
  [mentoraixs]=Leroy
  [ClawCore]=main
  [publish-service]=main
  [mentor-recsys]=main
  [user-post-skills-set]=main
)

REPO_NAMES=(mentoraixs ClawCore publish-service mentor-recsys user-post-skills-set)

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

  # mentoraixs (Next.js / pnpm)
  if [ -f "$REPOS_DIR/mentoraixs/package.json" ]; then
    info "mentoraixs: pnpm install"
    (cd "$REPOS_DIR/mentoraixs" && pnpm install)
    ok "mentoraixs dependencies installed"
  fi

  # ClawCore (Python/uv)
  if [ -f "$REPOS_DIR/ClawCore/pyproject.toml" ]; then
    info "ClawCore: uv sync"
    (cd "$REPOS_DIR/ClawCore" && uv sync)
    ok "ClawCore dependencies installed"
  fi

  # publish-service (Python)
  if [ -f "$REPOS_DIR/publish-service/backend/requirements.txt" ]; then
    info "publish-service: pip install"
    local venv="$REPOS_DIR/publish-service/.venv"
    if [ ! -d "$venv" ]; then
      python3 -m venv "$venv"
    fi
    (cd "$REPOS_DIR/publish-service" && source .venv/bin/activate && pip install -r backend/requirements.txt -q)
    ok "publish-service dependencies installed"
  fi

  # mentor-recsys (Python)
  if [ -f "$REPOS_DIR/mentor-recsys/requirements.txt" ]; then
    info "mentor-recsys: pip install"
    local venv="$REPOS_DIR/mentor-recsys/.venv"
    if [ ! -d "$venv" ]; then
      python3 -m venv "$venv"
    fi
    (cd "$REPOS_DIR/mentor-recsys" && source .venv/bin/activate && pip install -r requirements.txt -q)
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

  # 1. publish-service 后端 (:58888)
  if [ -f "$REPOS_DIR/publish-service/backend/run.sh" ]; then
    info "Starting publish-service backend on :58888..."
    (cd "$REPOS_DIR/publish-service" && bash backend/run.sh) > "$LOG_DIR/publish-service.log" 2>&1 &
    echo "publish-service:$!" >> "$PID_FILE"
    sleep 2
    ok "publish-service backend started (PID $!)"
  fi

  # 2. mentor-recsys (:8000)
  if [ -f "$REPOS_DIR/mentor-recsys/app/main.py" ]; then
    info "Starting mentor-recsys on :8000..."
    (cd "$REPOS_DIR/mentor-recsys" && python3 -m app.main) > "$LOG_DIR/mentor-recsys.log" 2>&1 &
    echo "mentor-recsys:$!" >> "$PID_FILE"
    sleep 1
    ok "mentor-recsys started (PID $!)"
  fi

  # 3. ClawCore (:8001 — 避免与 RecSys 冲突)
  if [ -f "$REPOS_DIR/ClawCore/pyproject.toml" ]; then
    info "Starting ClawCore on :8001..."
    (cd "$REPOS_DIR/ClawCore" && uv run uvicorn clawtok.app:create_app --factory --host 0.0.0.0 --port 8001) > "$LOG_DIR/clawcore.log" 2>&1 &
    echo "clawcore:$!" >> "$PID_FILE"
    sleep 2
    ok "ClawCore started (PID $!)"
  fi

  # 4. mentoraixs 前端 (:3000) — 最后启动
  if [ -f "$REPOS_DIR/mentoraixs/package.json" ]; then
    info "Starting mentoraixs on :3000..."
    (cd "$REPOS_DIR/mentoraixs" && pnpm dev) > "$LOG_DIR/mentoraixs.log" 2>&1 &
    echo "mentoraixs:$!" >> "$PID_FILE"
    sleep 3
    ok "mentoraixs started (PID $!)"
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
    echo "  clone   — git clone all 5 repos into repos/"
    echo "  install — install dependencies for each repo"
    echo "  start   — start all services in background"
    echo "  stop    — stop all background services"
    ;;
esac
