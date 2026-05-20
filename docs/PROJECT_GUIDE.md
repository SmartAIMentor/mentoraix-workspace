# Project Guide — CreatorPilot / Mentoraix

面向独立创作者（TikTok/Instagram/YouTube）的 AI 导师平台。一个叫 **"M"** 的 AI 导师帮助创作者完成内容分析、创意生成、发布和多平台增长。

> 本文档是项目全景速查手册，供队友和 AI 助手快速了解整个系统。操作指南见 [README.md](../README.md)。

---

## 架构拓扑

```
用户浏览器 (mobile-first 440px)
  └─ mentoraix (Next.js :3000) ── 五标签页前端
       │
       ├── SmartAIMentor (FastAPI :58888) ── 黑客松后端
       │    ├── 聊天（Gemini 意图分类 → 发布 or 回复）
       │    ├── 发布工作流（Post Bridge → 社媒平台）
       │    ├── 任务管理（JSON 文件存储）
       │    └── /api/v1/* 数据契约（当前为硬编码种子数据）
       │
       ├── RecSys (Flask :8000) ── 推荐服务
       │    ├── 人设构建（从创作者数据提取关键词/内容支柱）
       │    ├── 趋势推荐（关键词 + 时效性 + 相关性打分）
       │    ├── 帖子推荐（多博主内容按人设匹配打分）
       │    └── 每日热点卡片（holding-today 聚合）
       │
       ├── ClawCore (FastAPI :8001) ── 智能体核心（最高优先级）
       │    ├── ReAct 工具调用循环
       │    ├── 多 LLM 网关（Claude / Kimi / GPT，按用户路由）
       │    ├── 持久记忆（SQLite + FTS5 全文检索）
       │    ├── 事实抽取 + 偏好检测（后台进化任务）
       │    ├── 技能系统（SKILL.md 运行时发现）
       │    └── 飞书机器人适配器
       │
       ├── platform_data_fetcher ── 数据采集管线
       │    ├── TikHub SDK 采集 Instagram 用户资料/帖子
       │    └── Gemini 多模态媒体分析（视频/图片内容理解）
       │
       └── AI 供应商降级链（在 mentoraix provider.ts 中）
            ClawCore → OrbitAI → DeepSeek → Mock
```

---

## 仓库详解

### mentoraix — 主前端应用

**技术栈：** Next.js 16 · React 19 · TypeScript 5 · Tailwind CSS 4

**五标签页：**

| 标签 | 路由 | 数据来源 | 说明 |
|------|------|----------|------|
| Chat | `/chat` | ClawCore/OrbitAI/DeepSeek | AI 对话，支持流式回复 |
| Insights | `/insights` | SmartAIMentor + RecSys + TikHub | 趋势、热点、每日卡片 |
| Create | `/create` | 客户端 | 封面生成、脚本创作 |
| Grow | `/grow` | 客户端 | 增长策略 |
| Me | `/me` | 客户端 | 个人设置 |

**关键文件：**
- `server/core/ai/provider.ts` — AI 供应商抽象层，实现降级链
- `server/core/ai/system-prompts.ts` — 19 个 prompt key，定义 "M" 人设
- `server/modules/chat/` — 聊天服务，文件持久化到 `data/chat-history/`
- `server/modules/insights/hot-tags.service.ts` — TikHub 热榜缓存
- `app/api/` — API 路由代理层，转发到各后端

**当前状态：** UI 基本完成，Chat/Insights 有真实数据流，Create/Grow/Me 主要是客户端组件。认证为硬编码 demo 用户，数据库为 stub。

---

### ClawCore — 智能体核心

**技术栈：** Python 3.12+ · FastAPI · aiosqlite · Anthropic/OpenAI SDK

这是整个系统架构最完善的组件（282 个测试用例）。

**请求处理管线：**

```
请求进入
  → 幂等检查（五状态机）
  → UserSession.load（加载人设文档 + 近 50 条消息 + 已启用技能）
  → PromptBuilder.build（稳定段优先排列，优化 prompt caching）
  → Memory prefetch（FTS5 检索相关事实，注入 <memory-context>）
  → ReActLoop（最多 30 轮迭代：LLM 调用 → 工具执行 → 循环）
  → Session.finish（持久化消息，入队后台进化任务）
```

**9 个内置工具：**

| 工具 | 功能 |
|------|------|
| `terminal` | 执行 shell 命令（有破坏性操作检测） |
| `read_file` / `write_file` | 文件读写 |
| `web_search` / `web_fetch` | DuckDuckGo 搜索 + HTTP 抓取 |
| `create_reminder` | 定时提醒（cron/一次性） |
| `search_facts` | FTS5 事实检索 |
| `recall_history` | FTS5 对话历史检索 |
| `skill_view` | 渐进式技能内容披露 |

**后台进化系统（4 个任务循环）：**
- **A Loop** — 事实抽取（从对话中提取结构化事实）
- **B Loop** — 轨迹写入（快照对话状态）
- **C Loop** — 偏好修正（检测用户纠正并更新偏好文档）
- **D Loop** — 策略更新（预留）

**SSE 事件协议：**
`turn.start` → `message.delta`(流式) → `message.complete` → `turn.end`
工具调用额外发出 `tool.start` / `tool.progress` / `tool.complete`

**关键设计：**
- 多用户隔离（所有操作带 user_id）
- Fernet 加密用户密钥
- Prompt 段稳定排列（利于 Anthropic prompt caching）
- 上下文压缩（80% 时触发：head + tail 保留，中间摘要）
- 安全层：破坏性命令检测、JSON 修复、注入清洗

---

### SmartAIMentor — 黑客松后端

**技术栈：** Python 3.13 · FastAPI · Gemini 2.5 Flash · Post Bridge API

**核心工作流：** 用户发聊天 → Gemini 分类意图 → 如果是发布意图 → 上传媒体到 Post Bridge → 发布到社媒平台。

**API 路由：**

| 路由 | 用途 |
|------|------|
| `POST /api/chat` | 聊天 + 发布意图检测 |
| `POST /api/publish` | 直接发布到社媒 |
| `GET /api/tasks` | 发布任务列表 |
| `GET /api/v1/mentor/header-card` | 导师卡片信息 |
| `GET /api/v1/holding-today/{id}` | 每日优先事项 |
| `GET /api/v1/persona/{id}` | 创作者人设 |
| `POST /api/v1/trends/recommend` | 趋势推荐 |
| `POST /api/v1/posts/recommend` | 帖子推荐 |

**当前状态：** `/api/v1/*` 端点返回**硬编码种子数据**（硬编码在前端契约服务中）。发布功能走 Post Bridge，正在迁移到 Bundle Social。任务存储为 JSON 文件。

---

### RecSys — 推荐服务

**技术栈：** Python · Flask 3.1 · Pydantic 2

**核心服务：**
- **人设服务** — 从创作者数据提取 hashtag、关键词、内容支柱（城市探索、中国旅行、美食发现等）、受众画像
- **趋势服务** — MockTrendAdapter 读取本地 JSON，设计为可替换真实数据源
- **推荐服务** — 混合打分：关键词重叠 + 内容支柱匹配 + 地域相关性 + 热度（log 缩放）

**当前状态：** 推荐逻辑已实现，但使用 mock 趋势数据。人设构建支持从 JSON 文件导入。内存存储（重启后从磁盘加载）。

---

### platform_data_fetcher — 数据采集管线

**技术栈：** Python · TikHub SDK · Google Gemini

**流程：** TikHub 采集 Instagram 用户资料和帖子 → Gemini 多模态分析图片/视频内容 → 输出结构化 JSON + CSV。

`GeminiMediaAnalyzer` 设计为可复用组件，未来可扩展到 TikTok、抖音、小红书。

---

### user-post-skills-set — 智能体技能包

两个 Codex/Claude 技能定义：

| 技能 | 调用目标 |
|------|----------|
| `creator-hotspot-api` | RecSys 的推荐和市场信息接口 |
| `instagram-creator-fetch` | Instagram 数据采集 + Gemini 分析 |

---

### popularpays-mcp-demo — MCP 爬虫演示

使用 Playwright MCP SDK 爬取 PopularPays 品牌合作数据。演示级项目。

---

### mentoraix-promo — 宣传视频

20 秒产品宣传片，用 GSAP 动画制作，包含分镜脚本、旁白、字幕和实际应用截图。

---

### creatop-skills — 内容创作技能链（位于 SmartAIMentor 内）

6 个 TikTok 内容创作 SKILL.md，形成完整工作流：

```
视频分析 → Hook 生成 → 脚本创作 → 标签策略 → 封面设计 → 合规检查
```

这些是 prompt 级技能（给 Claude Code / Cowork 用的），不是 API 端点。

---

## 关键设计决策

### 1. AI 供应商降级链

`mentoraix/server/core/ai/provider.ts` 实现：

```
ClawCore（如果 CLAWCORE_BASE_URL 可达）
  → OrbitAI（如果 ORBITAI_API_KEY 有值）
    → DeepSeek（如果 DEEPSEEK_API_KEY 有值）
      → Mock（脚本化兜底回复）
```

ClawCore 可用时走完整管线（记忆 prefetch → prompt 组装 → ReAct → 事实抽取），其他供应商只做简单对话。

### 2. 文件持久化（非数据库）

- mentoraix：聊天历史 → `data/chat-history/{userId}.json`
- SmartAIMentor：发布任务 → `data/tasks.json`
- ClawCore：加密 SQLite（唯一使用数据库的组件）
- RecSys：内存 + 磁盘 JSON

### 3. 前端数据仍是种子数据

SmartAIMentor 的 `/api/v1/*` 返回硬编码 mock。RecSys 有真实推荐逻辑但未完全与前端打通。

### 4. 发布后端迁移中

从 Post Bridge → Bundle Social（支持 14 个平台），有设计文档但实现未完成。

### 5. 无 Docker、无 Git Submodule

Shell clone + Makefile 编排，设计文档中预留了未来迁移到 Git Submodule 的路径。

---

## 跨服务数据流

### 聊天流程
```
用户 → mentoraix /api/chat → provider.ts
  → ClawCore 可用? → SSE 流式（带记忆）
  → 否则 → OrbitAI/DeepSeek（OpenAI 兼容接口）
```

### 发布流程
```
用户 → mentoraix /api/publish → SmartAIMentor /api/publish
  → Post Bridge API → TikTok / Instagram / X
```

### 推荐流程
```
mentoraix Insights 页 → SmartAIMentor /api/v1/*
  → 部分 → RecSys（趋势、帖子推荐）
  → 部分 → 硬编码种子数据
```

### 数据采集流程
```
platform_data_fetcher → TikHub API → Instagram 数据
  → Gemini 多模态分析 → 结构化 JSON
  → RecSys 消费 → 人设构建 + 推荐
```

---

## 环境变量速查

完整列表见 `.env.example`，以下是跨项目关键变量：

| 变量 | 用途 | 使用方 |
|------|------|--------|
| `MENTORAIX_API_BASE_URL` | mentoraix → SmartAIMentor（默认 :58888） | mentoraix |
| `CLAWCORE_BASE_URL` | mentoraix → ClawCore 智能体 | mentoraix |
| `GEMINI_API_KEY` | Gemini API | RecSys, SmartAIMentor, mentoraix, platform_data_fetcher |
| `ANTHROPIC_API_KEY` | Claude API | ClawCore |
| `MOONSHOT_API_KEY` | Kimi/Moonshot API | ClawCore |
| `OPENAI_API_KEY` | OpenAI API | ClawCore, mentoraix |
| `DEEPSEEK_API_KEY` | DeepSeek API | mentoraix |
| `ORBITAI_API_KEY` | OrbitAI API | mentoraix |
| `TIKHUB_API_KEY` | TikHub 数据采集 | mentoraix, platform_data_fetcher |
| `POST_BRIDGE_API_KEY` | 社媒发布（正迁移至 Bundle Social） | SmartAIMentor |

---

## 系统人设：M 导师

mentoraix 的 `system-prompts.ts` 定义了 "M" 人设：
- 服务对象：Kris，中美跨界创作者（TikTok 47K 粉丝，4.2% TikTok Shop CTR，Q1 GMV $48K）
- 风格：双语、诚实、具体、不浮夸
- 标志性 hook："美国买不到 / 美国贵 5x"
