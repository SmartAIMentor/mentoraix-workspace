# P0：给新 Agent 注入 M 人格（system prompt）方案

> 状态：可执行方案（2026-08-07），待实施。
> 这是 ClawCore→Hermes **完整替换的唯一行为缺口**——补完它，新栈行为就与旧的对齐。

---

## 问题

新栈 adapter→Hermes **没注入 system prompt** → 新 agent 用 Hermes 默认人格，**不像产品里的"M"**，也无个性化。
- 证据：adapter `main.py` 只发 `message`；Hermes session 用 `{}` 建（无 system_prompt）。
- 对比：ClawCore `prompt_builder` 内部拼了分层 system prompt（`identity + profile + persona + strategies + preferences`）。

---

## M 人格的权威来源

**`mentoraixs/src/server/core/ai/system-prompts.ts`** 的 `chat` key = **"Mate"** 导师（服务 Leroy Chen @leroy3c，3C 电子产品带货创作者；含真实数据、风格、标志性 hook、**中英双语**）。

- `SHARED_VOICE_EN / SHARED_VOICE_ZH` = 核心人格；`chat` = 人格 + 对话规范（短、诚实、实用、<90 字、不谄媚）。
- 取用：`getSystemPrompt('chat', locale)`（locale 决定中/英）。
- ⚠ ClawCore 自己的 `_IDENTITY`（"ClawTok, TikTok 变现助手"）是**旧的不一致版本**，不用。

---

## 方案：mentoraixs 发 system_prompt → adapter 传给 Hermes

```
mentoraixs provider.ts ──body 加 system_prompt──→ adapter :8003
  getSystemPrompt('chat', locale)                     │ 建 Hermes session 时带 system_prompt
                                                     ↓
                                              Hermes :8002（session 带 M 人格）
```

**为什么这样**：mentoraixs 是人格的**唯一真相源**（system-prompts.ts，含 localization）；adapter 保持通用、不内置人格。
**向后兼容**：旧 ClawCore(:8001) 会忽略 body 里多余的 `system_prompt` 字段，所以 mentoraixs 一直发它，**新旧栈都工作**——切换/回滚不受影响。

---

## 具体改动（2 处，都很小）

### ① mentoraixs — `src/server/core/ai/provider.ts` + `clawcore-session-client.ts`

```ts
// 现在（provider.ts:178 附近）：只发 user text（注释说 ClawCore 自己管 system prompt）
const body = buildClawCoreBody({ userId, sessionId, text });

// 改成：带 system_prompt（新 adapter 用；旧 ClawCore 会忽略）
const body = buildClawCoreBody({
  userId, sessionId, text,
  systemPrompt: getSystemPrompt('chat', locale),   // 从 system-prompts.ts import
});
```
（`buildClawCoreBody` / `clawcore-session-client.ts` 对应把 `systemPrompt` 序列化进 body 的 `system_prompt` 字段。）

### ② adapter — `agent-runtime-lab/hermes-clawcore-adapter/main.py`

```python
# _create_hermes_session：现在 POST {} ，改成带 system_prompt
async def _create_hermes_session(client, system_prompt: str = "") -> str:
    resp = await client.post(
        f"{HERMES_BASE}/api/sessions", headers=_hermes_headers(),
        json={"system_prompt": system_prompt} if system_prompt else {},
        timeout=30.0,
    )
    ...

# clawcore_chat：把 body 的 system_prompt 透传下去
system_prompt = body.get("system_prompt") or ""
hermes_sid = await _ensure_hermes_session(client, user_id, mentoraixs_sid, system_prompt)
```
（Hermes api_server 已支持 session `system_prompt`——验证过：`gateway/platforms/api_server.py:689` 建会话接受、`:1501` 请求体读取。）

---

## per-user 个性化怎么办

ClawCore 的 `[profile/persona/strategies/preferences]`（per-user curated 文档）→ **不迁**（冷启动，已确认）。
新栈个性化由 **OpenViking 召回**承担：adapter 每轮 recall 该 user 的记忆（OV 自动抽取事实/偏好）→ 注入 message。用一段时间后 OV 自己沉淀出"用户画像"，等效替代 curated 文档。

> 即：**system_prompt = M 身份（恒定）+ OV recall = per-user 个性化（动态）**，两者合起来 = ClawCore 原来的 [identity + profile/persona/preferences]。

---

## 验收
- chat 回复像 **Mate**（Leroy 风格：诚实/具体/接地气/不浮夸）+ **中英按 locale 正确**。
- 多用户隔离 + 跨 session 召回**不回归**（仍 OK）。

## 备注
- **localization**：mentoraixs 按 user locale 选 EN/ZH system_prompt；adapter 透传（不关心语言）。
- **单一真相源**：以后 persona 变了，只改 mentoraixs `system-prompts.ts` 一处。
- 备选（不推荐）：把人格硬编码进 adapter 配置——会和 mentoraixs 重复，DRY 差。
