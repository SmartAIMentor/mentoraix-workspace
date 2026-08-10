# Project Guide — CreatorPilot / Mentoraix

面向独立创作者（TikTok/Instagram/YouTube）的 AI 导师平台。一个叫 **"M"** 的 AI 导师帮助创作者完成内容分析、创意生成、发布和多平台增长。

> 本文档是项目全景速查手册，供队友和 AI 助手快速了解整个系统。操作指南见 [README.md](../README.md)。

---

## 架构拓扑

```
用户浏览器 (mobile-first 440px)
  └─ mentoraix (Next.js :3000) ── 五标签页前端
       │
       ├── publish-service (FastAPI :58888) ── 多平台发布后端
       │    ├── Bundle Social API 集成（支持 14 个社媒平台）
       │    ├── 社媒账号绑定 / 解绑
       │    ├── 视频 / 图文发布工作流
       │    └── 团队配置管理（teams.json）
       │
       ├── mentor-recsys (FastAPI :8000) ── Creator Hotspot 推荐服务
       │    ├── 人设构建（从创作者数据提取关键词/内容支柱）
       │    ├── 趋势推荐（关键词 + 时效性 + 相关性打分）
       │    ├── 帖子推荐（多博主内容按人设匹配打分）
       │    └── 每日热点卡片（holding-today 聚合）
       │
       ├── Adapter (:8003) ── 智能体入口（ClawCore 已下线，由 Hermes+OpenViking 承接）
       │    ├── Hermes (:8002) 无状态执行器（skill 加载/执行引擎）
       │    ├── OpenViking (:1933) 会话/记忆/人格/上下文（官方 SDK）
       │    ├── /api/chat + /api/sessions（ClawCore 兼容契约）
       │    ├── 多租户隔离（JWT + per-user OV session）
       │    └── 13 个官方 skill（带脚本的调 publish-service / mentor-recsys）
       │
       └── AI 供应商降级链（在 mentoraix provider.ts 中）
            Adapter(智能体) → OrbitAI → DeepSeek → Mock
```

---

## 仓库详解

### mentoraixs — 主前端应用

**技术栈：** Next.js 16 · React 19 · TypeScript 5 · Tailwind CSS 4

**五标签页：**

| 标签 | 路由 | 数据来源 | 说明 |
|------|------|----------|------|
| Chat | `/chat` | Adapter/Hermes 智能体、OrbitAI/DeepSeek | AI 对话，支持流式回复 |
| Insights | `/insights` | mentor-recsys + TikHub | 趋势、热点、每日卡片 |
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

### ClawCore — 智能体核心（已下线）

**技术栈：** Python · FastAPI · aiosqlite · Anthropic/OpenAI SDK

> **ClawCore 已 decommissioned（下线）**，能力由 `agent-runtime-lab` 的新智能体栈（Hermes :8002 + OpenViking :1933 + Adapter :8003）承接。前端契约 `/api/chat` + `/api/sessions` 保持不变，由 Adapter 在 :8003 提供 ClawCore 兼容协议，因此前端无需改动。
>
> **历史架构（供回滚/追溯参考）**：原 ClawCore 是单体智能体——幂等检查 → UserSession.load（人设 + 近 50 条消息 + 已启用技能）→ PromptBuilder.build → Memory prefetch（FTS5）→ ReActLoop（最多 30 轮：LLM 调用 → 工具执行 → 循环）→ Session.finish（持久化 + 后台进化）。内置 9 个工具（terminal / read_file / write_file / web_search / web_fetch / create_reminder / search_facts / recall_history / skill_view），4 个后台进化 loop（事实抽取 / 轨迹写入 / 偏好修正 / 策略更新）。这些能力现由 OpenViking（多租户记忆）+ Hermes（无状态执行 + skill 引擎）以更可扩展的方式替代。

**迁移对照：**

| 原 ClawCore 能力 | 现由谁承接 |
|---|---|
| FTS5 单库记忆 | OpenViking 多租户记忆（官方 SDK） |
| 内置业务工具 | 各服务 MCP 接入（Hermes skill / MCP servers） |
| ReAct LLM 循环 | Hermes 无状态执行器 |
| 人格 system prompt | 待实施（见 `PERSONA-INJECTION.md`） |

---

### publish-service — 多平台发布后端

**技术栈：** Python 3.12+ · FastAPI · Pydantic 2 · Bundle Social API

**核心工作流：** 创作者绑定社媒账号 → 上传内容 → 通过 Bundle Social API 发布到 TikTok / Instagram / YouTube 等多平台。

**主要功能：**

| 功能 | 说明 |
|------|------|
| 社媒账号绑定 | OAuth 连接 TikTok、Instagram、YouTube 等平台 |
| 视频 / 图文发布 | 上传媒体文件，通过 Bundle Social 分发到多平台 |
| 团队配置 | teams.json 管理创作者团队和 API Key 映射 |
| 发布工作流 | 状态机管理发布流程（上传 → 审核 → 发布） |

**当前状态：** 重构自旧 SmartAIMentor 黑客松后端，专注于发布功能。聊天能力由智能体栈（Adapter/Hermes）承接，推荐由 mentor-recsys 承担。

---

### mentor-recsys — Creator Hotspot 推荐服务

**技术栈：** Python 3.12+ · FastAPI · Pydantic 2 · SQLite + LanceDB

**核心服务：**
- **人设服务** — 从创作者数据提取 hashtag、关键词、内容支柱（城市探索、中国旅行、美食发现等）、受众画像
- **趋势服务** — 从 TikHub 同步热点（TikTok/Instagram/X），本地聚合
- **推荐服务** — 混合打分：关键词重叠 + 内容支柱匹配 + 地域相关性 + 热度（log 缩放）；含个性化推荐引擎 + 新手兜底策略
- **Creator Hotspot API** — `POST /api/v1/posts/recommend` + `GET /api/v1/market-info`（供 `creator-hotspot-api` skill 消费）

**当前状态：** FastAPI 服务，SQLite（关系型）+ LanceDB（向量）双库，含 APScheduler 定时同步（每日热点同步 + 推送生成）。消费方：Insights 页 + `creator-hotspot-api` skill。

---

### 数据采集（由 mentor-recsys 承担）

**技术栈：** Python · TikHub SDK · Google Gemini（Qwen 多模态）

**流程：** TikHub 采集 TikTok/Instagram/X 热点与创作者数据 → Gemini/Qwen 多模态分析图片/视频内容 → 落库（SQLite + LanceDB）→ 供推荐与人设构建。

**流程：** TikHub 采集 Instagram 用户资料和帖子 → Gemini 多模态分析图片/视频内容 → 输出结构化 JSON + CSV。

`GeminiMediaAnalyzer` 设计为可复用组件，未来可扩展到 TikTok、抖音、小红书。

---

### user-post-skills-set — 智能体技能包

Hermes 智能体加载的 **13 个官方 skill**（Claude Skills 协议，SKILL.md frontmatter），同步到 OpenViking 账户共享层（`viking://agent/skills`，所有用户可见）。

| 类别 | skill | 说明 |
|------|-------|------|
| 带脚本 | `creator-hotspot-api` | 调 mentor-recsys 推荐/市场信息（:8000） |
| 带脚本 | `publish-to-social` | 社交发布（publish-service :58888） |
| 带脚本 | `instagram-creator-fetch` | Instagram 采集 + Gemini 分析 |
| 指令/知识型 | 其余 10 个 | 脚本/钩子/标签/封面/合规/视频拆解等，靠 Hermes 创作能力 |

---

### (已废弃) — MCP 爬虫演示

使用 Playwright MCP SDK 爬取 PopularPays 品牌合作数据。演示级项目。

---

### mentoraix-promo — 宣传视频

20 秒产品宣传片，用 GSAP 动画制作，包含分镜脚本、旁白、字幕和实际应用截图。

---

### creatop-skills — 内容创作技能链（历史，位于旧 SmartAIMentor 内）

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
Adapter 智能体（如果 CLAWCORE_BASE_URL=:8003 可达）
  → OrbitAI（如果 ORBITAI_API_KEY 有值）
    → DeepSeek（如果 DEEPSEEK_API_KEY 有值）
      → Mock（脚本化兜底回复）
```

智能体可用时走完整管线（Hermes 执行 + OpenViking 记忆 + skill），其他供应商只做简单对话。

### 2. 文件持久化（非数据库）

- mentoraixs：聊天历史 → `data/chat-history/{userId}.json`
- publish-service：团队配置 → `backend/data/teams.json`，上传文件 → `backend/data/uploads/`
- adapter：会话映射 SQLite（`(user_id, client_sid) → hermes_sid`，重启不丢）
- mentor-recsys：SQLite（关系型）+ LanceDB（向量）双库
- OpenViking：多租户记忆持久化（会话/记忆/人格）

### 3. 前端数据仍是种子数据

publish-service 已取代旧后端。mentor-recsys 有真实推荐逻辑但未完全与前端打通。

### 4. 发布后端已重构

旧 SmartAIMentor（黑客松版，含聊天 + 发布 + 任务）已拆分为专注的 publish-service，使用 Bundle Social API 支持多平台发布。聊天功能由智能体栈（Adapter/Hermes）承担。

### 5. 无 Docker、无 Git Submodule

Shell clone + Makefile 编排，设计文档中预留了未来迁移到 Git Submodule 的路径。

---

## 跨服务数据流

### 聊天流程
```
用户 → mentoraixs /api/chat → provider.ts
  → Adapter(:8003) 可用? → SSE 流式（Hermes 执行 + OpenViking 记忆 + skill）
  → 否则 → OrbitAI/DeepSeek（OpenAI 兼容接口）
```

### 发布流程
```
用户 → mentoraixs → publish-service :58888
  → Bundle Social API → TikTok / Instagram / YouTube 等多平台
```

### 推荐流程
```
mentoraixs Insights 页 → mentor-recsys
  → 趋势推荐、帖子推荐、人设构建
```

### 智能体 skill 流程
```
用户对话 → Adapter(:8003) → Hermes(:8002) 加载官方 skill
  → 带脚本 skill 调后端取业务数据
    ├── creator-hotspot-api → mentor-recsys (:8000)
    └── publish-to-social   → publish-service (:58888)
```

### 数据采集流程
```
TikHub API → TikTok/Instagram/X 数据 → Gemini/Qwen 多模态分析
  → mentor-recsys 落库（SQLite+LanceDB） → 人设构建 + 推荐
```

---

## 环境变量速查

完整列表见 `.env.example`，以下是跨项目关键变量：

| 变量 | 用途 | 使用方 |
|------|------|--------|
| `MENTORAIX_API_BASE_URL` | mentoraixs → publish-service（默认 :58888） | mentoraixs |
| `CLAWCORE_BASE_URL` | mentoraix → Adapter(:8003, ClawCore 兼容契约) | mentoraix |
| `HERMES_BASE_URL` | adapter → Hermes（:8002） | adapter |
| `HERMES_API_KEY` | Hermes API key | adapter |
| `OPENVIKING_ENDPOINT` | adapter → OpenViking（:1933） | adapter |
| `OV_ROOT_KEY` | OpenViking root key | adapter |
| `OV_ACCOUNT` | OpenViking 账户（默认 mentoraix） | adapter |
| `GEMINI_API_KEY` | Gemini API | mentor-recsys, mentoraixs |
| `OPENAI_API_KEY` | OpenAI API | mentoraix, Hermes |
| `DEEPSEEK_API_KEY` | DeepSeek API | mentoraix |
| `ORBITAI_API_KEY` | OrbitAI API | mentoraix |
| `TIKHUB_API_KEY` | TikHub 数据采集 | mentor-recsys |
| `BUNDLE_SOCIAL_API_KEY` | 社媒发布（Bundle Social） | publish-service |

> `ANTHROPIC_API_KEY` / `MOONSHOT_API_KEY` 原属 ClawCore，随其下线已不再使用（保留仅为向后兼容）。

---

## 系统人设：M 导师

mentoraix 的 `system-prompts.ts` 定义了 "M" 人设：
- 服务对象：Kris，中美跨界创作者（TikTok 47K 粉丝，4.2% TikTok Shop CTR，Q1 GMV $48K）
- 风格：双语、诚实、具体、不浮夸
- 标志性 hook："美国买不到 / 美国贵 5x"
