# Memory Service 设计文档

> 日期：2026-05-05
> 状态：待审阅
> 范围：CreatorPilot/Mentorly 产品 — AI Mentor 的记忆能力

---

## 1. 背景与动机

### 1.1 当前问题

分工表中标记 Memory Service + pgvector 为 P0/v0 必上，状态"服务通，未与对话主链路联调"。

调研发现：

| 仓库                | 记忆能力                                                                   | 现状               |
| ------------------- | -------------------------------------------------------------------------- | ------------------ |
| **ClawCore**  | 有完整记忆系统（SQLite + FTS5 事实提取、偏好追踪、上下文注入）             | 独立运行，无人调用 |
| **mentoraix** | `server/modules/memory/` 为空壳，DB client 为 stub，聊天记录存 JSON 文件 | 零记忆能力         |
| **RecSys**    | 无记忆                                                                     | —                 |
| **其他仓库**  | 无记忆                                                                     | —                 |

三个 AI 系统完全独立，互不调用：

- mentoraix Chat → DeepSeek / OrbitAI（直连）
- ClawCore → Anthropic / Kimi / OpenAI（直连）
- SmartAIMentor Backend → Google Gemini（直连）

### 1.2 目标

让 mentoraix 的 Chat M（AI Mentor 聊天）具备记忆能力：

1. **短期记忆**：session 内上下文（mentoraix 已有，直接用）
2. **长期记忆**：跨 session 记住用户的偏好、习惯、创作风格，语义检索召回
3. **事实提取**：每轮对话后异步提取结构化 fact
4. **上下文注入**：召回的记忆压缩后注入 system prompt，带 token 预算控制

### 1.3 设计原则

- Memory Service 是**独立可调用的工具模块**，不改动现有 LLM 调用流程
- 对 mentoraix 的改动**最小化**：只在 Chat 服务前后各加一次 HTTP 调用
- API 接口**Phase 1/2 保持一致**，内部实现透明替换

---

## 2. 架构

### 2.1 整体架构

```
mentoraix (Next.js)
  │
  │  ① POST /v1/memory/recall  (消息发送前)
  │  ④ POST /v1/memory/ingest  (AI 回复后，异步)
  │
  └──→ Memory Service (独立仓库: SmartAIMentor/memory-service)
            │
            │ Phase 1: SQLite + FTS5 (快速交付)
            │ Phase 2: Supabase PostgreSQL + pgvector (生产级)
            │
            └──→ Embedding API (Phase 2: Gemini Embedding)
```

### 2.2 调用时序

```
用户发消息
  │
  ▼
mentoraix Chat API (chat.service.ts)
  │
  ├─① Memory Service: POST /v1/memory/recall
  │     body: { user_id, query: 用户消息, top_k: 5 }
  │     response: { facts: [...], preferences: [...] }
  │
  ├─② 将记忆注入 system prompt（新增 prompt 拼接逻辑）
  │
  ├─③ 调用 DeepSeek / OrbitAI（完全不变）
  │
  ├─④ 异步 Memory Service: POST /v1/memory/ingest
  │     body: { user_id, messages: [本轮对话], session_id }
  │     (不阻塞响应)
  │
  └─⑤ 返回 AI 回复给用户
```

### 2.3 对 mentoraix 的改动范围

仅修改 `server/modules/chat/chat.service.ts`：

- 在 LLM 调用前：加一次 recall HTTP 调用 + prompt 拼接
- 在 LLM 响应后：异步发一次 ingest HTTP 调用（fire-and-forget）
- 新增环境变量 `MEMORY_SERVICE_URL`（默认 `http://localhost:8101`）

---

## 3. API 设计

Memory Service 暴露以下 REST API，Phase 1 和 Phase 2 接口一致。

### 3.1 记忆召回

```
POST /v1/memory/recall
```

**Request:**

```json
{
  "user_id": "string",
  "query": "string (用户当前消息)",
  "top_k": 5,
  "session_id": "string (可选，排除当前 session 已知内容)"
}
```

**Response:**

```json
{
  "facts": [
    {
      "id": "string",
      "topic": "string",
      "content": "string",
      "confidence": 0.9,
      "created_at": "ISO 8601"
    }
  ],
  "preferences": [
    {
      "category": "string",
      "value": "string"
    }
  ]
}
```

### 3.2 记忆写入

```
POST /v1/memory/ingest
```

**Request:**

```json
{
  "user_id": "string",
  "session_id": "string",
  "messages": [
    { "role": "user", "content": "..." },
    { "role": "assistant", "content": "..." }
  ]
}
```

**Response:**

```json
{
  "extracted_facts": 3,
  "updated_preferences": 1,
  "status": "ok"
}
```

内部行为：

1. 调用 LLM 从对话中提取结构化 facts
2. 对 facts 去重/合并（与已有 facts 比对）
3. 存入数据库
4. 更新用户偏好

### 3.3 用户记忆画像

```
GET /v1/memory/profile/{user_id}
```

**Response:**

```json
{
  "user_id": "string",
  "facts_count": 42,
  "preferences_count": 8,
  "topics": ["内容策略", "发布习惯", "品牌合作", ...],
  "recent_facts": [...],
  "all_preferences": [...]
}
```

### 3.4 手动事实提取

```
POST /v1/memory/extract
```

**Request:**

```json
{
  "user_id": "string",
  "text": "string (任意文本)",
  "source": "string (来源标识)"
}
```

**Response:**

```json
{
  "facts": [
    { "topic": "string", "content": "string", "confidence": 0.85 }
  ]
}
```

---

## 4. 数据库设计

### 4.1 Phase 1：SQLite + FTS5

参考 ClawCore 已有 schema，使用 SQLite 快速启动。

```sql
CREATE TABLE user_facts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  topic TEXT,
  content TEXT NOT NULL,
  confidence REAL DEFAULT 0.8,
  source_session_id TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  superseded_by TEXT
);

CREATE VIRTUAL TABLE user_facts_fts USING fts5(
  content, topic,
  content=user_facts, content_rowid=rowid
);

CREATE TABLE user_preferences (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  category TEXT NOT NULL,
  preference_value TEXT NOT NULL,
  source_session_id TEXT,
  updated_at TEXT DEFAULT (datetime('now')),
  UNIQUE(user_id, category)
);

CREATE TABLE conversation_summaries (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  summary TEXT,
  key_topics TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
```

### 4.2 Phase 2：Supabase PostgreSQL + pgvector

```sql
CREATE TABLE user_facts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  topic TEXT,
  content TEXT NOT NULL,
  embedding vector(768),
  confidence REAL DEFAULT 0.8,
  source_session_id TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  superseded_by UUID REFERENCES user_facts(id)
);

CREATE INDEX idx_user_facts_user_id ON user_facts(user_id);
CREATE INDEX idx_user_facts_embedding ON user_facts
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

CREATE TABLE user_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  category TEXT NOT NULL,
  preference_value TEXT NOT NULL,
  source_session_id TEXT,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, category)
);

CREATE TABLE conversation_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  summary TEXT,
  embedding vector(768),
  key_topics TEXT[],
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_conv_summaries_embedding ON conversation_summaries
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

Phase 2 使用 Gemini Embedding（`text-embedding-004`，768 维）生成向量。

---

## 5. 事实提取策略

### 5.1 提取流程

每轮对话结束后（`/v1/memory/ingest` 被调用时）：

1. **LLM 提取**：将对话文本发送给轻量 LLM（复用 mentoraix 已配置的 DeepSeek），用结构化 prompt 提取 facts
2. **去重合并**：与已有 facts 比对（Phase 1 用 FTS5 相似度，Phase 2 用向量余弦相似度）
   - 如果新 fact 与已有 fact 冲突 → 更新旧 fact，标记 `superseded_by`
   - 如果新 fact 是已有 fact 的补充 → 合并增强
   - 如果新 fact 完全独立 → 直接插入
3. **偏好检测**：识别用户表达明确喜好的内容，更新 `user_preferences` 表

### 5.2 提取 Prompt 模板

```
你是一个信息提取助手。从以下对话中提取关于用户的事实和偏好。

规则：
- 只提取明确提及的事实，不要推测
- 每个 fact 包含 topic（分类）和 content（具体内容）
- confidence: 0-1，表示确定程度
- 标记用户明确表达的偏好（喜欢/不喜欢/习惯/风格）

输出 JSON 格式：
{
  "facts": [{"topic": "...", "content": "...", "confidence": 0.9}],
  "preferences": [{"category": "...", "value": "..."}]
}

对话内容：
{messages}
```

---

## 6. 上下文注入策略

### 6.1 Token 预算控制

- 记忆注入总量不超过 **800 tokens**（约 400 字中文）
- 分配：facts 最多 500 tokens，preferences 最多 300 tokens
- 超出时按 confidence 排序，截断低置信度的

### 6.2 注入格式

注入到 system prompt 末尾：

```
## 关于这位创作者的记忆
- [内容策略] 用户偏好短视频形式，通常在晚上 9-11 点发布
- [品牌合作] 之前与 Nike 合作过一次商单，反馈良好
- [发布习惯] 主要在 TikTok 和 Instagram 上活跃

## 用户偏好
- 沟通风格：简洁直接，不喜欢过多解释
- 内容类型：生活方式 + 科技测评
```

---

## 7. 技术栈

| 组件                | Phase 1                             | Phase 2                        |
| ------------------- | ----------------------------------- | ------------------------------ |
| **语言/框架** | Python + FastAPI                    | Python + FastAPI（不变）       |
| **数据库**    | SQLite + FTS5（本地文件）           | Supabase PostgreSQL + pgvector |
| **向量生成**  | 无（纯文本搜索）                    | Gemini text-embedding-004      |
| **LLM**       | DeepSeek API（复用 mentoraix 配置） | DeepSeek API（不变）           |
| **部署**      | 本地运行，port 8100                 | 本地开发 / 云部署              |

---

## 8. 两阶段计划

### Phase 1：快速联调（1-2 天）

| 步骤 | 内容                                                     | 产出            |
| ---- | -------------------------------------------------------- | --------------- |
| 1.1  | 新建 `SmartAIMentor/memory-service` 仓库               | 仓库初始化      |
| 1.2  | 实现 FastAPI 骨架 + SQLite schema                        | 基础项目结构    |
| 1.3  | 实现 `/v1/memory/recall`（FTS5 文本搜索）              | 记忆召回 API    |
| 1.4  | 实现 `/v1/memory/ingest`（LLM 事实提取 + SQLite 存储） | 记忆写入 API    |
| 1.5  | 实现 `/v1/memory/profile/{user_id}`                    | 用户画像 API    |
| 1.6  | mentoraix `chat.service.ts` 集成（前后各一次调用）     | Chat M 具备记忆 |
| 1.7  | 端到端测试：对话 → 记忆存储 → 下次对话召回             | 可演示          |

### Phase 2：生产级替换（3-5 天）

| 步骤 | 内容                                          | 产出         |
| ---- | --------------------------------------------- | ------------ |
| 2.1  | 创建 Supabase 项目，建表 + pgvector 扩展      | 云数据库就绪 |
| 2.2  | 实现 embedding 生成层（Gemini Embedding API） | 向量生成能力 |
| 2.3  | 实现 pgvector 语义检索 recall                 | 向量召回 API |
| 2.4  | 实现 ingest 的向量存储 + 去重合并             | 向量存储能力 |
| 2.5  | 从 SQLite 迁移到 Supabase（API 接口不变）     | 无感切换     |
| 2.6  | 性能调优 + 错误处理 + 测试                    | 生产就绪     |

---

## 9. 风险与约束

| 风险                     | 影响                   | 缓解措施                             |
| ------------------------ | ---------------------- | ------------------------------------ |
| DeepSeek API 不稳定      | 事实提取失败           | 降级为不提取，不影响正常聊天         |
| 事实提取质量不高         | 无用记忆注入浪费 token | 设置 confidence 阈值，低置信度不注入 |
| Phase 2 向量维度选择不当 | 检索质量差             | 使用 Gemini 标准维度 768，业界成熟   |
| 记忆注入过多占用 token   | LLM 回复质量下降       | 硬性 800 token 上限，按置信度截断    |

---

## 10. 仓库结构

```
SmartAIMentor/memory-service
├── README.md
├── requirements.txt
├── .env.example
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI 入口
│   ├── config.py               # 环境变量配置
│   ├── api/
│   │   ├── __init__.py
│   │   └── v1/
│   │       ├── __init__.py
│   │       ├── recall.py       # POST /v1/memory/recall
│   │       ├── ingest.py       # POST /v1/memory/ingest
│   │       ├── profile.py      # GET /v1/memory/profile/{user_id}
│   │       └── extract.py      # POST /v1/memory/extract
│   ├── services/
│   │   ├── __init__.py
│   │   ├── memory_service.py   # 核心业务逻辑
│   │   ├── fact_extractor.py   # LLM 事实提取
│   │   └── embedding.py        # Phase 2: 向量生成
│   ├── db/
│   │   ├── __init__.py
│   │   ├── sqlite_store.py     # Phase 1: SQLite 实现
│   │   ├── supabase_store.py   # Phase 2: Supabase 实现
│   │   └── base.py             # 存储接口抽象
│   └── models/
│       ├── __init__.py
│       └── schemas.py          # Pydantic 模型
├── tests/
│   ├── test_recall.py
│   ├── test_ingest.py
│   └── test_extract.py
└── scripts/
    └── seed_test_data.py       # 测试数据种子
```
