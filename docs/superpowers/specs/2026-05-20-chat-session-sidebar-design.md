# 设计文档：聊天会话历史侧边栏

**日期：** 2026-05-20
**状态：** 已批准
**仓库：** mentoraix（leroy 分支）

## 背景

当前聊天页面（chat-lp）的线程列表完全存储在 localStorage，与服务端 JSON 线程数据断裂。换设备/浏览器会丢失历史，无法跨设备同步。

## 目标

为聊天页面添加 ChatGPT 风格的会话历史侧边栏，从服务端加载线程列表，支持新建、切换、重命名、删除会话。暂不对接 ClawCore session（后续迁移）。

## 设计决策

### 决策 1：聊天页独立 Shell

聊天页脱离 LpShell，使用独立布局。原因：LpShell 的 220px 左侧导航 + 聊天侧边栏 260px 导致桌面端主内容区过窄。独立布局类似 ChatGPT 的简洁全屏体验。

### 决策 2：移动端抽屉式覆盖

移动端侧边栏隐藏，通过汉堡按钮触发全屏/半屏覆盖层。类似 ChatGPT iOS 端行为。

### 决策 3：线程 title 取前 20 字符

新线程用第一条用户消息的前 20 字符作为默认 title。暂不做 AI 生成 title（YAGNI）。

---

## 服务端 API

### 新增端点

**GET /api/chat/threads**

返回当前用户所有线程摘要（不含消息体）。

响应：
```json
{
  "ok": true,
  "data": {
    "threads": [
      { "threadId": "thread_xxx", "title": "TikTok 选品建议", "messageCount": 6, "updatedAt": "2026-05-20T12:00:00Z" }
    ]
  }
}
```

**PATCH /api/chat/threads/[threadId]**

重命名线程。请求体：`{ "title": "新名称" }`

**DELETE /api/chat/threads/[threadId]**

删除线程及其所有消息。

### Repository 扩展

在 `chat.repository.ts` 中新增：
- `listThreads(userId)` — 返回线程摘要列表，按 updatedAt 降序
- `deleteThread(userId, threadId)` — 删除指定线程
- `renameThread(userId, threadId, title)` — 更新线程标题

ChatThread 类型需要新增 `title` 字段。

### 已有端点（不变）

- `GET /api/chat?threadId=xxx` — 获取单个线程完整消息
- `POST /api/chat` — 发消息（自动创建或追加线程）

---

## 前端架构

### 路由结构

```
app/(shell)/
  ├── layout.tsx          ← LpShell（Insights/Create/Grow/Me 使用）
  ├── chat/
  │   ├── layout.tsx      ← 新建：独立聊天布局
  │   └── page.tsx        ← 渲染 <ChatHome />
  ├── insights/page.tsx
  ├── create/page.tsx
  ├── grow/page.tsx
  └── me/page.tsx
```

聊天页的 `layout.tsx` 不包裹 LpShell，而是提供独立的侧边栏 + 主内容区布局。

### 组件拆分

**`ChatHome`**（重构）
- 顶层状态：线程列表、活跃线程 ID、侧边栏开关
- 桌面端：侧边栏 + 聊天区并排
- 移动端：全屏聊天区，侧边栏通过抽屉覆盖

**`ChatSidebar`**（新建）
- 线程列表，按日期分组（今天/昨天/更早）
- 当前线程高亮
- 悬停显示操作菜单（重命名、删除）
- 「+ 新对话」按钮
- 底部「返回主页」导航

**`ChatDrawer`**（新建，移动端）
- 触发：顶部汉堡按钮
- 行为：从左侧滑出的覆盖层，内容复用 ChatSidebar
- 点击线程或遮罩关闭

### 桌面端布局

```
┌──────────┬──────────────────────────┐
│ Sidebar  │  Chat Header             │
│ (240px)  ├──────────────────────────┤
│          │                          │
│ M logo   │  Messages                │
│ + 新对话  │                          │
│          │                          │
│ 今天     │                          │
│  线程1 ▸ │                          │
│  线程2   │                          │
│ 昨天     │                          │
│  线程3   │                          │
│          ├──────────────────────────┤
│ ← 返回   │  Input                   │
└──────────┴──────────────────────────┘
```

### 移动端布局

```
┌──────────────────────┐
│ ☰  M logo    + 新对话 │
├──────────────────────┤
│                      │
│  Messages            │
│                      │
├──────────────────────┤
│  Input               │
└──────────────────────┘

点击 ☰ →
┌──────────────────────┐
│ Sidebar (覆盖层)      │
│ 线程列表...           │
│ 点击线程或遮罩关闭     │
└──────────────────────┘
```

---

## 数据流

```
页面加载 → GET /api/chat/threads → 渲染侧边栏 → 默认选中最新线程 → GET /api/chat?threadId=xxx → 渲染消息

用户点击线程 → GET /api/chat?threadId=xxx → 渲染消息 → 侧边栏高亮更新

用户发消息 → POST /api/chat { threadId } → 流式回复 → 完成后刷新侧边栏排序

新建对话 → POST /api/chat { 无 threadId } → 新线程创建 → 侧边栏插入顶部

重命名 → PATCH /api/chat/threads/xxx { title } → 侧边栏原地更新

删除 → DELETE /api/chat/threads/xxx → 侧边栏移除 → 切换到最近线程或空状态
```

## 不做的事

- 不做 AI 自动生成线程 title
- 不做线程搜索
- 不做线程置顶
- 不做对接 ClawCore session（后续方案 2）
- 不引入额外状态管理库
- 不修改 LpShell 代码

## 后续迁移路径

完成方案 1 后，迁移到 ClawCore session 的步骤：
1. ClawCore 新增 `GET /api/sessions` 等 REST 端点
2. mentoraix 新增 ClawCore session 客户端
3. ChatSidebar 数据源从 `/api/chat/threads` 切换到 ClawCore `/api/sessions`
4. 前端 threadId 映射到 ClawCore session_id
