# mentoraix-workspace 协作规范

## 服务概述
- **类型**: 工作区服务
- **技术栈**: 待定
- **功能**: 多工作区管理、协作环境

## 分支管理策略

### 分支类型
| 分支类型 | 用途 | 命名规范 | 示例 |
|---------|------|---------|------|
| `main` | 生产稳定分支 | main | `main` |
| `dev` | 开发主分支 | dev | `dev` |
| `feature/*` | 新功能开发 | feature/<功能名> | `feature/workspace-collab` |
| `bugfix/*` | 问题修复 | bugfix/<问题描述> | `bugfix/workspace-sync` |

### 提交规范
- **禁止**: 直接向 `main` 分支提交代码
- **统一方式**: 通过 PR 合并到 `main`
- **开发流程**: 所有功能基于 `dev` 分支迭代开发

---

## 安全规范

### 敏感信息管理

**绝对禁止提交到代码仓库的内容**:

1. **环境配置文件**:
   - `.env`
   - `.env.local`
   - `.env.development`
   - `.env.production`

2. **密钥和凭证**:
   - API Keys
   - 数据库凭证
   - 服务间通信密钥

### .gitignore 规范

```gitignore
# 环境变量
.env
.env.local
.env.*.local

# 依赖
node_modules/
__pycache__/
.venv/

# 构建产物
dist/
build/
out/

# 日志
*.log
logs/

# 操作系统
.DS_Store
```

---

## 工作区开发规范

### 1. 多租户设计
- 支持多工作区隔离
- 数据访问权限控制
- 资源配额管理

### 2. 协作功能
- 实时同步
- 冲突解决
- 版本控制

### 3. 状态管理
- 工作区状态持久化
- 离线支持
- 状态恢复机制
