# Bundle Social API 集成设计文档

**日期**: 2026-05-16
**状态**: 已审批
**范围**: 用 Bundle Social API 替换 Post Bridge，实现多用户社交媒体自动发布

---

## 背景

CreatorPilot（mentoraix）目前使用 Post Bridge API 进行社交媒体内容发布。Post Bridge 使用单一 API Key 和全局账号缓存，属于单用户系统。产品需要**一对多多用户支持**：每个用户绑定自己的社交媒体账号（Instagram、TikTok 等），独立发布内容。

Bundle Social API 原生提供 **Organization > Team** 的层级结构，天然匹配此需求。

---

## 核心决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 用户与 Team 的映射 | 1:1（每个用户 = 一个 Team） | 最简单的隔离模型；每个用户的社交账号、帖子和上传内容都在各自的 Team 中 |
| OAuth 流程 | 托管流程（Hosted Flow） | 开发量最小；通过 `create-portal-link` API 支持中文和自定义品牌 |
| 集成策略 | 完全替换 Post Bridge | 干净利落；原型阶段不需要维护两套 Provider |
| 架构方案 | 在现有 `PublishService` 层内用 `BundleSocialClient` 替换 `PostBridgeClient` | 复用现有的任务存储、API 契约和编排逻辑 |

---

## 架构图

```
前端 (Next.js)
    |
    v
FastAPI 后端 (/api/*)
    |
    +-- PublishService（编排层，复用现有）
    |       |
    |       v
    |   BundleSocialClient（新增，替换 PostBridgeClient）
    |       |
    |       +-- POST /api/v1/upload/            （上传媒体）
    |       +-- POST /api/v1/post/              （创建帖子）
    |       +-- GET  /api/v1/social-account     （查看已绑定账号）
    |       +-- POST /api/v1/social-account/create-portal-link （OAuth 入口）
    |       +-- POST /api/v1/team/              （创建团队）
    |
    +-- TeamStore（新增，管理 creator_id -> teamId 映射）
            |
            v
        bundle.social API
            |
            +-- Team A（用户 A 的社交账号）
            +-- Team B（用户 B 的社交账号）
            +-- ...
```

---

## 新增组件

### BundleSocialClient

替换 `PostBridgeClient`。文件位置：`backend/app/services/bundle_social_client.py`。

**方法列表：**

| 方法 | 说明 |
|------|------|
| `__init__(api_key, base_url, https_proxy)` | 使用 Bundle Social API 凭据初始化 |
| `create_team(name) -> dict` | `POST /api/v1/team/` - 在 Bundle Social 中创建新 Team |
| `create_portal_link(team_id, redirect_url, social_account_types, **kwargs) -> str` | `POST /api/v1/social-account/create-portal-link` - 生成托管 OAuth 链接 |
| `get_social_accounts(team_id) -> list[dict]` | `GET /api/v1/social-account` 传入 `teamId` - 获取该 Team 下已绑定的社交账号列表 |
| `disconnect_social_account(team_id, social_account_type) -> dict` | 从 Team 中解绑指定社交账号 |
| `upload_media(team_id, file_path) -> str` | `POST /api/v1/upload/`（multipart）- 上传媒体文件，返回 uploadId |
| `create_post(team_id, social_account_types, data, title, post_date, status) -> dict` | `POST /api/v1/post/` - 跨指定平台创建帖子 |
| `publish(caption, file_path, platforms, team_id) -> dict` | 高层方法：上传 + 创建帖子 合并为一步 |

**平台映射表：**

```python
PLATFORM_MAP = {
    "instagram": "INSTAGRAM",
    "tiktok": "TIKTOK",
    "youtube": "YOUTUBE",
    "twitter": "TWITTER",
    "x": "TWITTER",
    "facebook": "FACEBOOK",
    "linkedin": "LINKEDIN",
    "pinterest": "PINTEREST",
    "reddit": "REDDIT",
    "threads": "THREADS",
    "mastodon": "MASTODON",
    "discord": "DISCORD",
    "slack": "SLACK",
    "bluesky": "BLUESKY",
    "google_business": "GOOGLE_BUSINESS",
}
```

### TeamStore

管理 `creator_id -> teamId` 的映射关系。文件位置：`backend/app/services/team_store.py`。

**设计方案：** JSON 文件存储，与现有 `TaskStore` 模式保持一致。

**方法列表：**

| 方法 | 说明 |
|------|------|
| `get_team(creator_id) -> str | None` | 查找某个创作者对应的 teamId |
| `save_team(creator_id, team_id) -> None` | 持久化新的映射关系 |
| `get_or_create_team(creator_id, bundle_client) -> str` | 幂等方法：已有映射直接返回，没有则通过 Bundle Social API 创建新 Team 并持久化 |

**存储格式**（`backend/data/teams.json`）：

```json
{
  "teams": {
    "creator_abc123": {
      "team_id": "team_xyz789",
      "creator_id": "creator_abc123",
      "created_at": "2026-05-16T12:00:00Z"
    }
  }
}
```

---

## 需修改的组件

### PublishService

修改 `submit()` 方法：
1. 通过 `TeamStore.get_or_create_team()` 将 `creator_id` 解析为 `teamId`
2. 将 `team_id` 传递给 `BundleSocialClient.publish()`
3. 支持单次调用发布到多个平台

### publish.py（API 路由）

修改 `POST /api/publish`：
- `platform` 参数支持逗号分隔的字符串或列表（如 `"instagram,tiktok"`）
- `creator_id` 保持作为用户标识（默认值为 `"default"`，保持向后兼容）

### publish_contract.py

更新 `PublishTask` 模型：
- 新增 `platforms: list[str]` 字段（多平台支持，默认 `["x"]`）
- 保留 `platform: str` 字段用于向后兼容，值为 `platforms[0]`
- `skill_used` 从 `"post-bridge"` 改为 `"bundle-social"`

### config.py

```python
# 移除：
# post_bridge_api_key: str = ""
# post_bridge_base_url: str = "https://api.post-bridge.com"

# 新增：
bundle_social_api_key: str = ""
bundle_social_base_url: str = "https://api.bundle.social"
bundle_social_webhook_secret: str = ""
bundle_social_portal_redirect_url: str = "http://localhost:3000/social/callback"
```

---

## 新增 API 路由

### POST /api/social/connect

为当前用户生成 Bundle Social 托管 OAuth 门户链接。

**请求体：**
```json
{
  "creator_id": "creator_abc123",
  "platforms": ["instagram", "tiktok"],
  "redirect_url": "https://app.creatorpilot.com/social/callback"
}
```

**响应体：**
```json
{
  "portal_url": "https://app.bundle.social/connect?token=...",
  "team_id": "team_xyz789"
}
```

**处理流程：**
1. `TeamStore.get_or_create_team(creator_id)` -> `team_id`
2. `BundleSocialClient.create_portal_link(team_id, redirect_url, platforms)`
3. 返回门户 URL，前端负责跳转

### GET /api/social/accounts

获取当前用户已绑定的社交账号列表。

**请求参数：** `?creator_id=creator_abc123`

**响应体：**
```json
{
  "team_id": "team_xyz789",
  "accounts": [
    {
      "id": "sa_001",
      "platform": "INSTAGRAM",
      "username": "@creator_handle",
      "connected": true
    },
    {
      "id": "sa_002",
      "platform": "TIKTOK",
      "username": "@creator_tiktok",
      "connected": true
    }
  ]
}
```

### POST /api/social/disconnect

从用户的 Team 中解绑指定社交账号。

**请求体：**
```json
{
  "creator_id": "creator_abc123",
  "social_account_id": "sa_001"
}
```

---

## 数据流

### 用户绑定社交账号

```
1. 用户在前端点击「绑定 Instagram」
2. 前端 -> POST /api/social/connect { platforms: ["instagram"] }
3. 后端 -> TeamStore.get_or_create_team(creator_id) -> team_id
4. 后端 -> BundleSocialClient.create_portal_link(team_id, callback_url, ["INSTAGRAM"])
5. 后端返回 { portal_url }
6. 前端跳转到 portal_url
7. 用户在 Bundle Social 托管页面完成 OAuth 授权（支持中文）
8. Bundle Social 回调到 callback_url，附带 ?instagram-callback 参数
9. 前端调用 GET /api/social/accounts 验证绑定成功
```

### 用户发布内容

```
1. 前端 -> POST /api/publish { file, platforms: "instagram,tiktok", caption, creator_id }
2. 后端 -> TeamStore.get_or_create_team(creator_id) -> team_id
3. 后端 -> BundleSocialClient.publish(caption, file_path, platforms, team_id)
   a. POST /api/v1/upload/ { teamId, file } -> uploadId
   b. POST /api/v1/post/ { teamId, socialAccountTypes: ["INSTAGRAM","TIKTOK"],
      data: { INSTAGRAM: {...}, TIKTOK: {...} } } -> postId
4. 后端返回 PublishResponse（复用现有模型）
```

---

## 文件变更清单

### 新建文件

| 文件 | 说明 |
|------|------|
| `backend/app/services/bundle_social_client.py` | Bundle Social API 客户端 |
| `backend/app/services/team_store.py` | creator_id -> teamId 映射存储 |
| `backend/app/api/social.py` | 社交账号管理路由 |

### 修改文件

| 文件 | 变更内容 |
|------|----------|
| `backend/app/services/publish_service.py` | 增加 teamId 路由、多平台支持 |
| `backend/app/api/publish.py` | 接收多平台参数 |
| `backend/app/models/publish_contract.py` | 更新 platform 字段、skill_used |
| `backend/app/config.py` | 替换 Post Bridge 配置为 Bundle Social 配置 |
| `backend/app/main.py` | 注册 social 路由、初始化 TeamStore |

### 删除文件

| 文件 | 原因 |
|------|------|
| `backend/app/services/post_bridge_client.py` | 已被 BundleSocialClient 替代 |

---

## 后续扩展（当前不在范围内）

- **Webhook 处理器**（`POST /api/webhooks/bundle-social`）：接收 `post.published`、`post.failed`、`social-account.connected` 等事件，用于实时状态更新
- **数据分析**：通过 Bundle Social 的 analytics 端点拉取帖子和账号维度的分析数据
- **定时发布**：支持 `status: "SCHEDULED"` 配合未来的 `postDate`，替代立即发布
- **用户认证**：用真实的用户认证系统替换硬编码的 `creator_id`（当前受限于演示级别的认证方案）

---

## 定价参考

| 套餐 | 价格 | 月发帖量 | 备注 |
|------|------|----------|------|
| Free | $0 | 有限额度 | 适合开发和测试 |
| Pro | $100/月/组织 | 更高额度 | 适合小型 SaaS |
| Business | $400+/月 | 自定义 | 适合规模化 SaaS 平台 |

所有套餐均包含无限社交账号，不按账号数量收费。月发帖上限为组织级别（所有 Team 共享）。频率限制按 Team 独立计算（每个用户有独立的配额）。

---

## 风险评估

| 风险 | 应对措施 |
|------|----------|
| Bundle Social API 宕机 | PublishService 已有 dry-run 模式；可增加重试逻辑 |
| 频率限制耗尽（按 Team） | 通过 Webhook 事件监控；提示用户剩余配额 |
| OAuth Token 过期 | Bundle Social 自动处理 Token 刷新 |
| creator_id 当前未做认证 | 临时方案：在实现真正的用户认证系统之前接受此限制 |
| 供应商锁定风险 | Client 封装在独立类中；如需更换可替换 |
