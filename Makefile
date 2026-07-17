.PHONY: setup clone install env dev start stop status health pull clean root help

REPO_DIR := $(shell pwd)
REPOS    := mentoraixs ClawCore publish-service mentor-recsys user-post-skills-set

# 仓库根自动探测（零配置，向后兼容）：
#   - 默认 $(REPO_DIR)/repos —— 队友 `make setup` clone 的标准位置
#   - 若 repos/ 为空、且父目录存在平铺子仓（mentoraixs/.git），自动改用父目录（本机平铺布局）
#   - 可显式覆盖：REPOS_ROOT=/path make ...
# 用 `make root` 查看当前生效的仓库根。
ifeq ($(wildcard $(REPO_DIR)/repos/mentoraixs/.git),)
  ifneq ($(wildcard $(REPO_DIR)/../mentoraixs/.git),)
    _DETECTED_ROOT := $(abspath $(REPO_DIR)/..)
  else
    _DETECTED_ROOT := $(REPO_DIR)/repos
  endif
else
  _DETECTED_ROOT := $(REPO_DIR)/repos
endif
REPOS_ROOT ?= $(_DETECTED_ROOT)

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

# === 显示当前生效的仓库根（调试布局探测） ===
root:
	@echo "REPOS_ROOT = $(REPOS_ROOT)"

# === 查看所有仓库 git 状态 ===
status:
	@for name in $(REPOS); do \
		dir="$(REPOS_ROOT)/$$name"; \
		if [ -d "$$dir/.git" ]; then \
			echo "=== $$name ==="; \
			cd "$$dir" && git status -sb && cd "$(REPO_DIR)"; \
			echo ""; \
		else \
			echo "=== $$name === (missing: $$dir)"; \
		fi; \
	done

# === 健康检查 ===
health:
	@bash scripts/health.sh

# === 拉取所有仓库最新代码 ===
pull:
	@for name in $(REPOS); do \
		dir="$(REPOS_ROOT)/$$name"; \
		if [ -d "$$dir/.git" ]; then \
			echo "Pulling $$name..."; \
			cd "$$dir" && git pull --ff-only && cd "$(REPO_DIR)"; \
		else \
			echo "Skip $$name (missing: $$dir)"; \
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
