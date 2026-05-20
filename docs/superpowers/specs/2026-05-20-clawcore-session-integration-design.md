# 设计文档：ClawCore Session 对接 Mentoraix 聊天侧边栏

**日期：** 2026-05-20
**状态：** 已批准
**仓库：** ClawCore (main) + mentoraix (leroy)

## 目标

将 mentoraix 聊天侧边栏的线程数据源从本地 JSON 文件切换到 ClawCore 的 SQLite session 体系，实现对话历史的持久化和跨设备同步。

## 前置条件

- 方案 1 已完成：mentoraix 有完整的线程管理 API（`GET /api/chat/threads`、`PATCH`、`DELETE`）
- ClawCore 的 `SQLiteStateStore` 已有 `list_sessions`、`get_session`、`end_session` 方法
- mentoraix 已有 `CLAWCORE_BASE_URL` 配置和 ClawCore provider

---

## 设计

### ClawCore 新增 REST 端点

在 `clawtok/adapters/web.py` 中添加 3 个端点：

**GET /api/sessions?user_id=xxx**

返回该用户的活跃 session 列表（`ended_at IS NULL`），按 `last_active_at DESC` 排序。

响应：
```json
{
  "ok": true,
  "sessions": [
    {
      "id": "s_a1b2c3d4e5f6",
      "title": "TikTok 选品建议",
      "source": "web",
      "started_at": 1716182400.0,
      "last_active_at": 1716195600.0,
      "message_count": 6,
      "ended_at": null
    }
  ]
}
```

**PATCH /api/sessions/{session_id}?user_id=xxx**

更新 session 元数据。请求体：`{ "title": "新名称" }`

**DELETE /api/sessions/{session_id}?user_id=xxx**

结束 session。设置 `ended_at` 和 `end_reason = "user_request"`。

### Mentoraix 数据源切换

在 `server/modules/chat/chat.service.ts` 的 `listThreads` 方法中：

1. 检查 `CLAWCORE_BASE_URL` 是否有值
2. 有值 → 调用 ClawCore `GET /api/sessions`，将 session 映射为 `ThreadSummary`
3. 无值或 ClawCore 不可达 → 降级回本地 JSON 线程存储

映射关系：
- `session.id` → `threadId`
- `session.title` → `title`（如果为空则用 `session.id`）
- `session.message_count` → `messageCount`
- `session.last_active_at`（Unix timestamp）→ `updatedAt`（ISO string）

`deleteThread` 和 `renameThread` 同理：优先调 ClawCore，降级回本地。

前端代码零改动。

### Session Title 自动设置

ClawCore 当前创建 session 时 `title` 为 NULL。在 `handle.py` 的 `finish()` 方法中，当 `session.title IS NULL` 且 `message_count == 1` 时，用第一条用户消息的前 20 字符作为 title。

### 测试

- **ClawCore**：`tests/test_web_sessions.py` — 测试 GET/PATCH/DELETE /api/sessions
- **Mentoraix**：`server/modules/chat/__tests__/clawcore-session.test.ts` — mock ClawCore 响应，测试降级逻辑

## 不做的事

- 不修改前端组件代码
- 不修改 ClawCore 的 `handle_message` 核心逻辑（仅在 finish 中加 title 设置）
- 不做 session 搜索或过滤
- 不做跨用户 session 共享
