# Bundle Social SKILL.md 重构设计

**日期**: 2026-05-17
**状态**: 已审批（经 Codex 对抗性评审 + OpenAPI spec 验证后修订）
**范围**: 重构 `bundle-social-manager` SKILL.md，从单文件 969 行拆分为核心 + references/ 结构

---

## API 验证状态

所有端点路径和字段名已通过 Bundle Social 官方 OpenAPI spec（`https://api.bundle.social/swagger-json`）验证确认。本 spec 中的 API 细节为已验证的事实，不再是假设。

验证结果：集成设计文档（Document A）在所有点上都正确；当前 SKILL.md（Document B）在端点路径、OAuth 端点名、帖子创建字段、Disconnect 方式上均有错误。

---

## 背景

当前 `SmartAIMentor/.claude/skills/bundle-social-manager/SKILL.md` 有 969 行，包含 14 个平台的完整字段 schema、三种上传模式、webhook 配置、错误码等所有内容。问题：

1. 核心工作流被大量参考细节淹没，加载和使用效率低
2. 端点路径使用复数形式（`/posts/`、`/uploads/`），与设计文档的单数形式不一致
3. OAuth 流程使用 `connect-url` 端点，实际应为 `create-portal-link`
4. 缺少 Create Team 端点（`POST /api/v1/team/`）
5. 定位为通用 Agent Skill，实际应服务于 SmartAIMentor 后端实现

---

## 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 文件结构 | 核心 SKILL.md + 4 个 references 文件 | 方案 A：核心可独立使用，references 按需加载 |
| 端点路径 | 统一单数形式 | 已通过 OpenAPI spec 验证确认 |
| OAuth 端点 | `create-portal-link` | 已通过 OpenAPI spec 验证确认；`connect-url` 不存在 |
| 代码架构 | 独立 BundleSocialClient 类 | 按集成设计文档，职责分离 |
| SKILL 定位 | SmartAIMentor 后端实现参考 | 不是通用 Agent Skill |
| version | 1.1.0 | 从 1.0.0 升级，反映结构变更 |

---

## 文件结构

```
SmartAIMentor/.claude/skills/bundle-social-manager/
├── SKILL.md                              (~290 行，核心)
└── references/
    ├── platform-details.md               (~270 行，14 平台 schema)
    ├── upload-guide.md                   (~80 行，三种上传模式)
    ├── analytics-and-webhooks.md         (~110 行，Analytics + Webhooks)
    └── error-codes.md                    (~50 行，错误码 + 恢复策略)
```

---

## SKILL.md 核心文件

### Frontmatter

```yaml
name: bundle-social-manager
version: 1.1.0
title: Social Media Manager (via Bundle Social)
description: >
  Manage social media posting for CreatorPilot via the Bundle Social API.
  Handles team-based multi-user isolation, OAuth account connection (hosted portal),
  media upload, cross-platform posting/scheduling, and post status tracking.
  Use when the task involves publishing to TikTok, Instagram, YouTube, Twitter/X,
  or any of the 14 supported platforms.
license: MIT
author: CreatorPilot
homepage: https://bundle.social
repository: https://info.bundle.social
keywords:
  - social-media
  - automation
  - bundle-social
  - tiktok
  - instagram
  - youtube
  - twitter
  - linkedin
  - posting
  - scheduling
metadata:
  openclaw:
    requires:
      env:
        - BUNDLE_SOCIAL_API_KEY
    primaryEnv: BUNDLE_SOCIAL_API_KEY
```

### 章节结构

| # | 章节 | 行数 | 变更说明 |
|---|------|------|----------|
| 1 | Supported Platforms | ~18 | 保留当前 14 平台总览表 |
| 2 | Setup | ~12 | 保留当前 5 步骤 |
| 3 | Authentication | ~10 | 保留 x-api-key 说明 |
| 4 | Org & Team Hierarchy | ~35 | **新增** Create Team 端点 |
| 5 | Rate Limits | ~18 | 保留当前表格 |
| 6 | Core Workflow | ~120 | **修改**：端点改为单数；步骤 2 改为 create-portal-link；每步精简，细节指向 references |
| 7 | Post Statuses | ~12 | 保留当前状态表 |
| 8 | Recommended Workflow | ~35 | 保留当前 4 场景 |
| 9 | References Index | ~15 | **新增**：何时加载哪个 reference 的指引表 |
| 10 | Tips | ~15 | 保留精选 8-10 条 |

### Core Workflow 修改细节

**步骤 2（Connect Social Accounts）**：

替换前：
```
POST /api/v1/social-accounts/connect-url
```

替换后：
```
POST /api/v1/social-account/create-portal-link
Content-Type: application/json

{
  "teamId": "team_abc123",
  "redirectUrl": "https://app.creatorpilot.com/social/callback",
  "socialAccountTypes": ["TIKTOK", "INSTAGRAM"]
}
```

说明：使用 Bundle Social 托管门户完成 OAuth 授权。前端跳转到返回的 portal URL，用户在托管页面完成授权后自动回调到 redirectUrl。

**步骤 3（List Connected Social Accounts）**：

端点改为单数：
```
GET /api/v1/social-account?teamId=team_abc123
```

**步骤 4（Disconnect）**：

按平台类型断开（不是按账号 ID）：
```
DELETE /api/v1/social-account/disconnect
Content-Type: application/json

{
  "type": "TIKTOK",
  "teamId": "team_abc123"
}
```

可额外使用 `GET /api/v1/social-account/by-type?type=TIKTOK&teamId=team_abc123` 按平台类型查询单个账号。

**步骤 5（Upload Media）**：

端点改为单数，保留直接上传的核心示例：
```
POST /api/v1/upload
Content-Type: multipart/form-data

teamId: team_abc123
file: <binary>
```

OpenAPI spec 中确认的上传子端点：
- `POST /api/v1/upload` — 直接上传（multipart）
- `POST /api/v1/upload/from-url` — URL 方式上传
- `POST /api/v1/upload/init` — 分块上传初始化
- `POST /api/v1/upload/finalize` — 分块上传完成

详细的三种上传模式见 `references/upload-guide.md`。

**步骤 6（Create a Post）**：

端点改为单数，使用 `socialAccountTypes`（平台枚举，不是账号 ID）：
```
POST /api/v1/post
Content-Type: application/json

{
  "teamId": "team_abc123",
  "socialAccountTypes": ["TIKTOK", "INSTAGRAM"],
  "postNow": true,
  "platforms": {
    "TIKTOK": {
      "text": "Check out this! #tiktokmademebuyit",
      "uploadIds": ["media_abc123"],
      "type": "VIDEO"
    },
    "INSTAGRAM": {
      "text": "New drop alert! #reels",
      "uploadIds": ["media_abc123"],
      "type": "POST"
    }
  }
}
```

注意：字段是 `socialAccountTypes`（平台枚举数组如 `["TIKTOK","INSTAGRAM"]`），不是 `socialAccountIds`（账号实例 ID）。API 中不存在 `socialAccountIds` 字段。

**步骤 7-9（Status / Update / Delete）**：

端点改为单数：
```
GET /api/v1/post/{postId}?teamId=team_abc123
PATCH /api/v1/post/{postId}
DELETE /api/v1/post/{postId}?teamId=team_abc123
```

### Org & Team Hierarchy 新增内容

新增 Create Team 端点：

```
POST /api/v1/team/
Content-Type: application/json

{
  "name": "creator_abc123"
}
```

Response:

```json
{
  "id": "team_xyz789",
  "name": "creator_abc123",
  "organizationId": "org_abc123",
  "createdAt": "2026-05-17T12:00:00Z"
}
```

### References Index

| 文件 | 何时加载 |
|------|----------|
| `references/platform-details.md` | 需要查看某个平台的完整字段 schema、约束和注意事项时 |
| `references/upload-guide.md` | 需要使用 URL-Based Upload 或 Chunked Upload 时（Direct Upload 在核心中已有） |
| `references/analytics-and-webhooks.md` | 需要读取分析数据、配置 webhook、或处理 webhook 事件时 |
| `references/error-codes.md` | 遇到错误需要排查时 |

---

## references/ 文件

### references/platform-details.md

**来源**：当前 SKILL.md 444-716 行
**内容**：14 个平台的完整 JSON schema、字段说明和约束
**变更**：无内容变更，仅从核心文件提取

### references/upload-guide.md

**来源**：当前 SKILL.md 231-312 行
**内容**：
- Direct Upload（≤90MB）— multipart/form-data
- URL-Based Upload — 提供公开 URL
- Chunked Upload（>90MB）— init → upload chunks → finalize

**变更**：端点路径改为单数形式

### references/analytics-and-webhooks.md

**来源**：当前 SKILL.md 719-858 行
**Phase 2**：Analytics 和 Webhooks 不在当前实现范围内（见集成设计文档"后续扩展"章节），但作为参考内容保留。
**内容**：
- Get Analytics 端点（参数、响应格式）
- Sync Analytics 端点
- Register/List/Delete Webhooks
- Webhook 事件类型表
- Payload 格式
- 签名验证代码（Python）

**变更**：端点路径改为单数形式

### references/error-codes.md

**来源**：当前 SKILL.md 862-914 行
**内容**：
- 错误响应格式
- 平台前缀表
- 常见错误码表（HTTP status + code + meaning）
- 恢复策略（per HTTP status category）

**变更**：无内容变更，仅从核心文件提取

---

## 与集成设计文档的关系

本重构是 [Bundle Social API 集成设计文档](./2026-05-16-bundle-social-integration-design.md) 的配套工作。设计文档定义了后端实现（BundleSocialClient、TeamStore、路由），本重构确保 SKILL.md 作为开发参考与设计文档保持一致。

关键对齐点：
- 端点路径单数形式（设计文档第 41-45 行）
- `create-portal-link` 作为 OAuth 入口（设计文档第 71 行）
- Create Team 端点（设计文档第 70 行）
- `socialAccountTypes` 用于帖子创建（设计文档第 76 行）
