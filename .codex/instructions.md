# mentoraix-workspace Codex 协作规范

## 服务概述
工作区服务，提供多工作区管理、协作环境。

## 分支管理

### 核心原则
1. **main 分支**: 生产稳定分支，禁止直接提交，统一通过 PR 合并
2. **dev 分支**: 开发主分支，所有功能基于此分支迭代
3. **feature/***: 新功能开发分支
4. **bugfix/***: 问题修复分支

### 分支命名规范
```
feature/<功能名>      # 例如: feature/workspace-collab
bugfix/<问题描述>     # 例如: bugfix/workspace-sync
```

## 安全规范

### 禁止提交内容
- `.env` 系列文件
- API Keys
- 数据库凭证
- 服务间通信密钥

### .gitignore 要求
```gitignore
.env
.env.local
.env.*.local
node_modules/
__pycache__/
.venv/
venv/
dist/
build/
out/
*.log
logs/
.DS_Store
```

## 工作区开发规范

### 多租户设计
- 支持多工作区隔离
- 数据访问权限控制
- 资源配额管理

### 协作功能
- 实时同步
- 冲突解决
- 版本控制

### 状态管理
- 工作区状态持久化
- 离线支持
- 状态恢复机制
