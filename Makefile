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
