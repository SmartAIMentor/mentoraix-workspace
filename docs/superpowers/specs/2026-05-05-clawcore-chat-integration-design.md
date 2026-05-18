# mentoraix Chat 与 ClawCore 联调设计文档

> 日期：2026-05-05
> 状态：待审阅
> 前置：替代先前独立 Memory Service 方案（已冻结）
> 范围：mentoraix Chat M → ClawCore AgentCore 的端到端联调

---

## 1. 背景与动机

### 1.1 为什么转向路径 A

先前设计了独立 Memory Service（Phase 1 SQLite → Phase 2 Supabase+pgvector）。调研发现 ClawCore 已有完整的记忆模块：

| 能力 | ClawCore 现状 |
|------|--------------|
| 事实提取（LLM 从对话中提取结构化 facts） | 已完成，中英文支持 |
| FTS5 全文检索召回 | 已完成 |
| 偏好检测（自动识别用户纠正） | 已完成 |
| 记忆注入 system prompt（`<memory-context>` 标签） | 已完成 |
| LLM 可主动调用 search_facts / recall_history | 已完成 |
| 事实去重 / 覆盖 / 合并 | 已完成 |
| 多用户隔离 | 已完成 |
| Evolution Worker 异步处理 | 已完成 |

重复造轮子没有意义。正确方向是：**让 mentoraix 的 Chat 直接走 ClawCore 的完整链路**，一次性获得记忆 + ReAct 工具调用 + 会话管理等全部能力。

### 1.2 目标

1. mentoraix 的 Chat M 路由到 ClawCore 的 `POST /api/chat`
2. 用户对话经过 ClawCore 的记忆 prefetch → LLM → 事实提取 → 偏好检测 全链路
3. 流式响应正常工作，前端无需改动
4. mentoraix 本地聊天记录仍然保存（用于前端展示）

### 1.3 不做的事情

- 不修改 ClawCore 代码（先联调，升级是下一步）
- 不修改前端代码（前端期望的响应格式不变）
- 不改动 mentoraix 的聊天记录存储逻辑

---

## 2. 架构

### 2.1 联调前后对比

**联调前（当前）：**
```
Frontend → POST /api/chat → chat.service.ts → provider.ts → DeepSeek/OrbitAI
                                                    ↓
                                              无记忆，无工具调用
```

**联调后（目标）：**
```
Frontend → POST /api/chat → chat.service.ts → provider.ts → ClawCore POST /api/chat
                                                    ↓
                                              ClawCore 完整链路:
                                              ├─ 记忆 prefetch (FTS5)
                                              ├─ Prompt 组装 (persona + memory)
                                              ├─ ReAct Loop (LLM + 工具)
                                              ├─ 流式 SSE 返回
                                              ├─ 事实提取 (Evolution Worker)
                                              └─ 偏好检测
```

### 2.2 数据流时序

```
Frontend                          mentoraix                         ClawCore
  │                                  │                                 │
  │ POST /api/chat                   │                                 │
  │ {message, threadId, stream:true} │                                 │
  │─────────────────────────────────→│                                 │
  │                                  │                                 │
  │                                  │ 1. 认证，保存用户消息             │
  │                                  │ 2. 加载历史消息作为 context       │
  │                                  │                                 │
  │                                  │ POST /api/chat                  │
  │                                  │ {user_id, text, session_id}     │
  │                                  │────────────────────────────────→│
  │                                  │                                 │
  │                                  │                      3. 记忆 prefetch
  │                                  │                      4. Prompt 组装
  │                                  │                      5. ReAct Loop
  │                                  │                                 │
  │                                  │   SSE: event:message.delta      │
  │                                  │←────────────────────────────────│
  │                                  │   SSE: event:message.delta      │
  │                                  │←────────────────────────────────│
  │                                  │   ...                           │
  │                                  │   SSE: event:turn.end           │
  │                                  │←────────────────────────────────│
  │                                  │                                 │
  │                                  │ 6. 解析 SSE，提取 text           │
  │                                  │ 7. 保存 AI 回复到本地            │
  │                                  │                                 │
  │ text/plain stream                │                      8. 异步事实提取
  │←─────────────────────────────────│                      9. 偏好检测
  │                                  │                                 │
```

---

## 3. 改动清单

### 3.1 文件改动总览

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `lib/server/env.ts` | 修改 | 新增 ClawCore 环境变量 |
| `server/core/ai/provider.ts` | 修改 | 新增 `clawcore` provider + SSE 解析 |
| `server/modules/chat/chat.types.ts` | 修改 | `ChatProvider` 新增 `"clawcore"` |
| `server/modules/chat/chat.repository.ts` | 修改 | provider 白名单新增 `"clawcore"` |
| `server/modules/chat/chat.service.ts` | 修改 | 传入 user_id 给 provider |

**不改动**：前端、API route、system-prompts、认证、其他模块。

### 3.2 详细改动

#### 3.2.1 `lib/server/env.ts` — 新增环境变量

```ts
// 新增
clawcoreBaseUrl: process.env.CLAWCORE_BASE_URL ?? "http://localhost:8000",
clawcoreApiKey: process.env.CLAWCORE_API_KEY ?? "",
```

- `CLAWCORE_BASE_URL`：ClawCore 服务地址，默认 `http://localhost:8000`
- `CLAWCORE_API_KEY`：API 密钥（ClawCore 当前无鉴权，预留字段）

#### 3.2.2 `server/core/ai/provider.ts` — 核心改动

**Provider 优先级调整：**

```
ClawCore > OrbitAI > DeepSeek > Mock
```

当 `CLAWCORE_BASE_URL` 可达时，优先使用 ClawCore。

**新增 `callClawCore` 函数：**

与现有 `callChat` 并列，处理 ClawCore 特有的请求格式：

```
请求格式差异：
  mentoraix → { messages: [{role, content}], stream: true }  (OpenAI 格式)
  ClawCore  → { user_id, text, session_id?, client_meta? }    (自定义格式)

响应格式差异：
  DeepSeek  → SSE: data: {"choices":[{"delta":{"content":"..."}}]}
  ClawCore  → SSE: event:message.delta\ndata: {"text":"..."}
```

**SSE 解析逻辑：**

ClawCore 的 SSE 事件格式：
```
event: turn.start
data: {"session_id":"s_xxx"}

event: message.delta
data: {"text":"你"}

event: message.delta
data: {"text":"好"}

event: message.complete
data: {"text":"你好！","tokens":42}

event: turn.end
data: {}
```

解析策略：
1. 按行读取 SSE 事件（`event:` + `data:` 成对）
2. 只处理 `event: message.delta`，提取 `data.text` 字段
3. 遇到 `event: turn.end` 结束
4. 遇到 `event: error` 抛出异常
5. 忽略 `tool.start` / `tool.progress` / `tool.complete` 事件（工具调用过程不展示给用户）

#### 3.2.3 `server/modules/chat/chat.service.ts` — 传入 user_id

当前 `streamText` 不接收 user_id，但 ClawCore 需要 user_id 来隔离记忆。

改动：
- `streamText` 和 `generateText` 的 input 类型新增可选 `userId?: string`
- `chat.service.ts` 在调用时传入 `user.id`
- provider 层在 ClawCore 模式下将 `userId` 映射为 `user_id`

#### 3.2.4 `server/modules/chat/chat.types.ts` — 类型扩展

```ts
// Before
export type ChatProvider = "mock" | "deepseek" | "orbitai";

// After
export type ChatProvider = "mock" | "deepseek" | "orbitai" | "clawcore";
```

#### 3.2.5 `server/modules/chat/chat.repository.ts` — provider 白名单

`normalizeThread()` 中的 provider 校验新增 `"clawcore"`。

---

## 4. SSE 格式适配详解

这是联调中**最关键的技术难点**。完整梳理两端的流式协议：

### 4.1 mentoraix 内部流式链路（不动）

```
provider.ts streamText()
  ↓ onChunk(delta: string)          ← 解析后的纯文本片段
chat.service.ts
  ↓ content += delta; input.onChunk(delta)
route.ts
  ↓ controller.enqueue(encoder.encode(delta))   ← 写入 ReadableStream
Response
  ↓ content-type: text/plain; charset=utf-8    ← 纯文本流
Frontend
  ↓ reader.read() → decoder.decode()           ← 逐 chunk 拼接
chat-screen.tsx
```

**关键点**：provider.ts 的 `onChunk` 是一个 `(delta: string) => void` 回调。只要我们把 ClawCore 的 SSE 解析成同样的 `delta` 字符串传给 `onChunk`，下游完全不需要改动。

### 4.2 新增 ClawCore SSE 解析器

在 `provider.ts` 中新增一个 `parseClawCoreSSE` 函数：

```ts
async function parseClawCoreSSE(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  onChunk: (delta: string) => void,
): Promise<void> {
  const decoder = new TextDecoder();
  let buffered = "";
  let currentEvent = "";

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;

    buffered += decoder.decode(value, { stream: true });

    // SSE 按 \n\n 分割事件块
    let boundary: number;
    while ((boundary = buffered.indexOf("\n\n")) !== -1) {
      const block = buffered.slice(0, boundary);
      buffered = buffered.slice(boundary + 2);

      for (const line of block.split("\n")) {
        if (line.startsWith("event:")) {
          currentEvent = line.slice(6).trim();
        } else if (line.startsWith("data:")) {
          const payload = line.slice(5).trim();
          if (!payload) continue;

          if (currentEvent === "message.delta") {
            try {
              const parsed = JSON.parse(payload);
              if (parsed.text) onChunk(parsed.text);
            } catch { /* skip */ }
          } else if (currentEvent === "error") {
            throw new Error(`ClawCore error: ${payload}`);
          }
          // tool.* / turn.start / turn.end / message.complete — 忽略
        }
      }
    }
  }
}
```

---

## 5. Session 映射

### 5.1 mentoraix threadId ↔ ClawCore session_id

mentoraix 用 `threadId`（如 `thread_m0abc123`）管理对话线程。
ClawCore 用 `session_id`（如 `s_xxxxxxxxxxxx`）管理会话。

**映射策略**：将 mentoraix 的 `threadId` 作为 `session_id_hint` 传给 ClawCore。ClawCore 会尝试复用匹配的活跃 session（24 小时内有效），否则创建新 session。

这样做的效果：
- 同一个 thread 下的连续消息会共享 ClawCore session
- ClawCore 的记忆在同一个 session 内自然累积
- ClawCore 的 session 超时后自动创建新 session，不影响 mentoraix

### 5.2 user_id 映射

mentoraix 当前使用硬编码 demo user：`user_7f3d8f18-65b1-4c9a-a7e8-3d6b2f1a9c44`。
直接将此 ID 传给 ClawCore 作为 `user_id`。

未来接入真实登录后，`getSessionUser()` 返回真实 user.id，自动传递。

---

## 6. 降级与容错

| 场景 | 处理方式 |
|------|----------|
| ClawCore 服务不可达 | 自动降级到 OrbitAI → DeepSeek → Mock |
| ClawCore 返回 error 事件 | 抛出异常，触发降级到下一个 provider |
| SSE 解析异常 | 跳过 malformed 事件，继续解析后续事件 |
| ClawCore 响应超时 | AbortSignal 控制超时，降级到下一个 provider |

降级逻辑：在 `selectedProvider()` 中检测 ClawCore 可达性，不可达时自动切换。

---

## 7. 环境变量

### mentoraix `.env` 新增

```env
# ClawCore AgentCore — 设置后优先使用 ClawCore 作为 Chat 后端
CLAWCORE_BASE_URL=http://localhost:8000
CLAWCORE_API_KEY=
```

不设置 `CLAWCORE_BASE_URL` 或留空时，回退到现有的 OrbitAI / DeepSeek 链路，行为完全不变。

---

## 8. 测试策略

| 测试 | 内容 |
|------|------|
| 单元测试 | SSE 解析器：验证 `message.delta` 事件正确提取 text |
| 单元测试 | SSE 解析器：验证 `error` 事件抛出异常 |
| 单元测试 | SSE 解析器：验证 tool.* 事件被忽略 |
| 单元测试 | 请求格式转换：验证 mentoraix input → ClawCore request body |
| 集成测试 | 启动 ClawCore → mentoraix 发送消息 → 验证流式响应 |
| E2E 测试 | 浏览器操作 → 聊天界面 → 验证消息收发 + 记忆召回 |

---

## 9. 实施步骤

| 步骤 | 内容 | 预估 |
|------|------|------|
| 1 | `env.ts` 新增 ClawCore 环境变量 | 10 min |
| 2 | `chat.types.ts` 扩展 ChatProvider 类型 | 5 min |
| 3 | `chat.repository.ts` 更新 provider 白名单 | 5 min |
| 4 | `provider.ts` 新增 clawcore provider + SSE 解析器 | 45 min |
| 5 | `chat.service.ts` 传入 userId，适配 ClawCore 模式 | 20 min |
| 6 | 本地联调：启动 ClawCore + mentoraix，端到端测试 | 30 min |
| 7 | 验证记忆：连续对话 → 检查 ClawCore 的 user_facts 表 | 15 min |

**总计预估：2-3 小时**

---

## 10. 后续升级方向（联调通之后）

联调验证效果后，可在 ClawCore 侧升级：

1. **向量语义搜索**：FTS5 → pgvector + Embedding，提升记忆召回质量
2. **独立记忆 API**：暴露 `/api/memory/recall` 等端点，供其他模块调用
3. **记忆压缩**：大量 facts 时的摘要/合并策略
4. **CORS + 鉴权**：生产环境安全加固
5. **平台枚举扩展**：`InboundMessage.platform` 新增 `"mentoraix"`
