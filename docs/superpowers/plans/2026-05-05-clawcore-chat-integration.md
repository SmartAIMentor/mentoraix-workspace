# ClawCore Chat Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route mentoraix's Chat M through ClawCore's existing memory-equipped chat pipeline, giving users persistent conversational memory.

**Architecture:** Add a new `clawcore` provider to mentoraix's AI provider layer that translates requests to ClawCore's format and parses ClawCore's SSE event stream back into plain text deltas. The rest of the mentoraix stack (route, service, frontend) stays untouched.

**Tech Stack:** TypeScript (Next.js), ClawCore (Python FastAPI, SSE via sse-starlette)

**Spec:** `docs/superpowers/specs/2026-05-05-clawcore-chat-integration-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `mentoraix/lib/server/env.ts` | Modify | Add `clawcoreBaseUrl`, `clawcoreApiKey` env vars |
| `mentoraix/server/modules/chat/chat.types.ts` | Modify | Add `"clawcore"` to `ChatProvider` union |
| `mentoraix/server/modules/chat/chat.repository.ts` | Modify | Add `"clawcore"` to provider whitelist in `normalizeThread` |
| `mentoraix/server/core/ai/provider.ts` | Modify | Add clawcore provider, SSE parser, request builder |
| `mentoraix/server/modules/chat/chat.service.ts` | Modify | Pass `userId` to provider for ClawCore user isolation |
| `mentoraix/.env` | Modify | Add `CLAWCORE_BASE_URL` and `CLAWCORE_API_KEY` |

---

### Task 1: Add environment variables

**Files:**
- Modify: `mentoraix/lib/server/env.ts`
- Modify: `mentoraix/.env`

- [ ] **Step 1: Add ClawCore env vars to env.ts**

Append two new entries to the `env` object in `mentoraix/lib/server/env.ts` (after the `orbitaiModel` line, before `geminiApiKey`):

```ts
  // ClawCore AgentCore — memory-equipped agent backend.
  // Takes priority over OrbitAI/DeepSeek when CLAWCORE_BASE_URL is set.
  clawcoreBaseUrl: process.env.CLAWCORE_BASE_URL ?? "",
  clawcoreApiKey: process.env.CLAWCORE_API_KEY ?? "",
```

- [ ] **Step 2: Add to .env**

Append to `mentoraix/.env`:

```env

# ClawCore AgentCore — memory-equipped agent backend (priority over DeepSeek/OrbitAI)
CLAWCORE_BASE_URL=http://localhost:8000
CLAWCORE_API_KEY=
```

- [ ] **Step 3: Commit**

```bash
cd mentoraix
git add lib/server/env.ts .env
git commit -m "feat(chat): add ClawCore AgentCore env config"
```

---

### Task 2: Extend ChatProvider type and repository whitelist

**Files:**
- Modify: `mentoraix/server/modules/chat/chat.types.ts:2`
- Modify: `mentoraix/server/modules/chat/chat.repository.ts:59-63`

- [ ] **Step 1: Update ChatProvider type**

In `mentoraix/server/modules/chat/chat.types.ts`, change line 2:

```ts
// Before:
export type ChatProvider = "mock" | "deepseek" | "orbitai";

// After:
export type ChatProvider = "mock" | "deepseek" | "orbitai" | "clawcore";
```

- [ ] **Step 2: Update provider whitelist in repository**

In `mentoraix/server/modules/chat/chat.repository.ts`, update the provider validation block (lines 59-63):

```ts
// Before:
        const provider =
          messageRecord.provider === "mock" ||
          messageRecord.provider === "deepseek" ||
          messageRecord.provider === "orbitai"
            ? messageRecord.provider
            : undefined;

// After:
        const provider =
          messageRecord.provider === "mock" ||
          messageRecord.provider === "deepseek" ||
          messageRecord.provider === "orbitai" ||
          messageRecord.provider === "clawcore"
            ? messageRecord.provider
            : undefined;
```

- [ ] **Step 3: Commit**

```bash
cd mentoraix
git add server/modules/chat/chat.types.ts server/modules/chat/chat.repository.ts
git commit -m "feat(chat): add clawcore to ChatProvider type and whitelist"
```

---

### Task 3: Add ClawCore SSE parser

This is the core technical challenge. We add a standalone SSE parser function that converts ClawCore's event stream into plain text deltas.

**Files:**
- Modify: `mentoraix/server/core/ai/provider.ts`

- [ ] **Step 1: Add `ClawCoreProvider` type and helper types**

At the top of `provider.ts`, update the `Provider` type and add the ClawCore provider type:

```ts
// Before (line 28):
type Provider = "orbitai" | "deepseek" | "none";

// After:
type Provider = "orbitai" | "deepseek" | "clawcore" | "none";
```

Update the `AiGenerateResult` type (line 10):

```ts
// Before:
export type AiGenerateResult = {
  text: string;
  provider: "mock" | "deepseek" | "orbitai";
};

// After:
export type AiGenerateResult = {
  text: string;
  provider: "mock" | "deepseek" | "orbitai" | "clawcore";
};
```

- [ ] **Step 2: Update `selectedProvider()` to include ClawCore**

Replace the `selectedProvider()` function (lines 30-34):

```ts
function selectedProvider(): Provider {
  if (env.clawcoreBaseUrl) return "clawcore";
  if (env.orbitaiApiKey) return "orbitai";
  if (env.deepSeekApiKey) return "deepseek";
  return "none";
}
```

- [ ] **Step 3: Add ClawCore request builder**

Add after the `buildMessages` function (after line 63). This converts mentoraix's input into ClawCore's expected request body:

```ts
function buildClawCoreBody(input: {
  userId: string;
  text: string;
  sessionId?: string;
}): Record<string, unknown> {
  return {
    user_id: input.userId,
    text: input.text,
    session_id: input.sessionId ?? undefined,
    client_meta: { lang: "zh", tz: "Asia/Shanghai" },
  };
}
```

- [ ] **Step 4: Add ClawCore SSE parser**

Add after `buildClawCoreBody`. This is the critical function that reads ClawCore's SSE events and extracts text deltas:

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
              const parsed = JSON.parse(payload) as { text?: string };
              if (parsed.text) onChunk(parsed.text);
            } catch {
              /* skip malformed SSE data */
            }
          } else if (currentEvent === "error") {
            throw new Error(`ClawCore error: ${payload}`);
          }
        }
      }

      currentEvent = "";
    }
  }
}
```

- [ ] **Step 5: Add `callClawCore` function**

Add after `parseClawCoreSSE`. This handles both streaming and non-streaming calls to ClawCore:

```ts
async function callClawCore(input: {
  userId: string;
  text: string;
  sessionId?: string;
  stream: boolean;
  onChunk?: (delta: string) => void;
  signal?: AbortSignal;
}): Promise<string> {
  const body = buildClawCoreBody({
    userId: input.userId,
    text: input.text,
    sessionId: input.sessionId,
  });

  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (env.clawcoreApiKey) {
    headers["Authorization"] = `Bearer ${env.clawcoreApiKey}`;
  }

  const response = await fetch(`${env.clawcoreBaseUrl}/api/chat`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    signal: input.signal,
  });

  if (!response.ok) {
    throw new Error(`ClawCore request failed: ${response.status}`);
  }

  if (!response.body) {
    throw new Error("ClawCore returned no body");
  }

  const reader = response.body.getReader();

  if (input.stream && input.onChunk) {
    await parseClawCoreSSE(reader, input.onChunk);
    return "";
  }

  // Non-streaming: collect all deltas into a single string
  let fullText = "";
  await parseClawCoreSSE(reader, (delta) => {
    fullText += delta;
  });
  return fullText;
}
```

- [ ] **Step 6: Verify TypeScript compiles**

Run: `cd mentoraix && npx tsc --noEmit 2>&1 | head -30`

Expected: No errors related to the new code. (There may be pre-existing warnings; those are fine.)

- [ ] **Step 7: Commit**

```bash
cd mentoraix
git add server/core/ai/provider.ts
git commit -m "feat(chat): add ClawCore SSE parser and request builder"
```

---

### Task 4: Wire ClawCore provider into generateText and streamText

**Files:**
- Modify: `mentoraix/server/core/ai/provider.ts`

The input types need a `userId` field so we can pass it to ClawCore. Both `generateText` and `streamText` need to handle the `"clawcore"` provider case.

- [ ] **Step 1: Update AiGenerateInput and AiStreamInput types**

Update `AiGenerateInput` (line 3):

```ts
// Before:
export type AiGenerateInput = {
  system: string;
  prompt: string;
  context?: string;
};

// After:
export type AiGenerateInput = {
  system: string;
  prompt: string;
  context?: string;
  userId?: string;
  sessionId?: string;
};
```

Update `AiStreamInput` (line 14):

```ts
// Before:
export type AiStreamInput = {
  system: string;
  prompt: string;
  context?: string;
  maxTokens?: number;
  onChunk: (delta: string) => void;
  signal?: AbortSignal;
};

// After:
export type AiStreamInput = {
  system: string;
  prompt: string;
  context?: string;
  maxTokens?: number;
  onChunk: (delta: string) => void;
  signal?: AbortSignal;
  userId?: string;
  sessionId?: string;
};
```

- [ ] **Step 2: Update generateText to handle ClawCore**

Replace the `generateText` function (lines 88-119):

```ts
export async function generateText(input: AiGenerateInput): Promise<AiGenerateResult> {
  const provider = selectedProvider();
  if (provider === "none") {
    return {
      text: `Mock mentor response: ${input.prompt}`,
      provider: "mock",
    };
  }

  if (provider === "clawcore") {
    if (!input.userId) {
      throw new Error("userId is required for ClawCore provider");
    }

    const promptWithContext = input.context
      ? `${input.context}\n\n---\n\n${input.prompt}`
      : input.prompt;

    const text = await callClawCore({
      userId: input.userId,
      text: promptWithContext,
      sessionId: input.sessionId,
      stream: false,
    });

    return { text: text.trim(), provider: "clawcore" };
  }

  const response = await callChat(provider, {
    messages: buildMessages(input),
    maxTokens: 220,
    stream: false,
  });

  if (!response.ok) {
    throw new Error(`${provider} request failed: ${response.status}`);
  }

  const payload = (await response.json()) as {
    choices?: Array<{
      message?: {
        content?: string | null;
      };
    }>;
  };

  return {
    text: payload.choices?.[0]?.message?.content?.trim() || "",
    provider,
  };
}
```

- [ ] **Step 3: Update streamText to handle ClawCore**

Replace the `streamText` function (lines 121-187):

```ts
export async function streamText(input: AiStreamInput): Promise<AiGenerateResult["provider"]> {
  const provider = selectedProvider();
  if (provider === "none") {
    input.onChunk(`Mock mentor response: ${input.prompt}`);
    return "mock";
  }

  if (provider === "clawcore") {
    if (!input.userId) {
      throw new Error("userId is required for ClawCore provider");
    }

    const promptWithContext = input.context
      ? `${input.context}\n\n---\n\n${input.prompt}`
      : input.prompt;

    await callClawCore({
      userId: input.userId,
      text: promptWithContext,
      sessionId: input.sessionId,
      stream: true,
      onChunk: input.onChunk,
      signal: input.signal,
    });

    return "clawcore";
  }

  const response = await callChat(provider, {
    messages: buildMessages(input),
    maxTokens: input.maxTokens,
    stream: true,
    signal: input.signal,
  });

  if (!response.ok || !response.body) {
    throw new Error(`${provider} stream failed: ${response.status}`);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffered = "";

  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }

    buffered += decoder.decode(value, { stream: true });

    let separatorIndex: number;
    while ((separatorIndex = buffered.indexOf("\n\n")) !== -1) {
      const block = buffered.slice(0, separatorIndex);
      buffered = buffered.slice(separatorIndex + 2);

      for (const line of block.split("\n")) {
        if (!line.startsWith("data:")) {
          continue;
        }

        const payload = line.slice(5).trim();
        if (!payload || payload === "[DONE]") {
          continue;
        }

        try {
          const parsed = JSON.parse(payload) as {
            choices?: Array<{
              delta?: {
                content?: string;
              };
            }>;
          };

          const delta = parsed.choices?.[0]?.delta?.content;
          if (delta) {
            input.onChunk(delta);
          }
        } catch {
          /* skip malformed SSE chunks silently */
        }
      }
    }
  }

  return provider;
}
```

- [ ] **Step 4: Verify TypeScript compiles**

Run: `cd mentoraix && npx tsc --noEmit 2>&1 | head -30`

Expected: No errors related to the changed code.

- [ ] **Step 5: Commit**

```bash
cd mentoraix
git add server/core/ai/provider.ts
git commit -m "feat(chat): wire ClawCore provider into generateText and streamText"
```

---

### Task 5: Pass userId and sessionId from chat.service.ts

**Files:**
- Modify: `mentoraix/server/modules/chat/chat.service.ts`

- [ ] **Step 1: Update reply() to pass userId and sessionId**

In `chat.service.ts`, update the `generateText` call in `reply()` (around line 75). Add `userId` and `sessionId`:

```ts
// Before:
    const generated = await generateText({
      system: aiSystemPrompts.chat,
      prompt: input.message,
      context: buildChatContext({
        surface: input.context?.surface,
        priorMessages: existingThread?.messages,
      }),
    });

// After:
    const generated = await generateText({
      system: aiSystemPrompts.chat,
      prompt: input.message,
      context: buildChatContext({
        surface: input.context?.surface,
        priorMessages: existingThread?.messages,
      }),
      userId: user.id,
      sessionId: threadId,
    });
```

- [ ] **Step 2: Update streamReply() to pass userId and sessionId**

In `chat.service.ts`, update the `streamText` call in `streamReply()` (around line 127). Add `userId` and `sessionId`:

```ts
// Before:
    const provider = await streamText({
      system: aiSystemPrompts.chat,
      prompt: input.message,
      context: buildChatContext({
        surface: input.context?.surface,
        priorMessages: existingThread?.messages,
      }),
      maxTokens: 220,
      signal: input.signal,
      onChunk: (delta) => {
        content += delta;
        input.onChunk(delta);
      },
    });

// After:
    const provider = await streamText({
      system: aiSystemPrompts.chat,
      prompt: input.message,
      context: buildChatContext({
        surface: input.context?.surface,
        priorMessages: existingThread?.messages,
      }),
      maxTokens: 220,
      signal: input.signal,
      userId: user.id,
      sessionId: threadId,
      onChunk: (delta) => {
        content += delta;
        input.onChunk(delta);
      },
    });
```

- [ ] **Step 3: Verify TypeScript compiles**

Run: `cd mentoraix && npx tsc --noEmit 2>&1 | head -30`

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
cd mentoraix
git add server/modules/chat/chat.service.ts
git commit -m "feat(chat): pass userId and sessionId to AI provider for ClawCore"
```

---

### Task 6: End-to-end verification

**Prerequisites:**
- ClawCore running on `localhost:8000` with a valid LLM API key configured
- mentoraix Next.js dev server running

- [ ] **Step 1: Start ClawCore**

Run in a separate terminal:

```bash
cd /Users/leon/Documents/AI-mentor-coProject/ClawCore
# Check how to start — look at README or pyproject.toml
# Typical: python -m clawtok or uvicorn clawtok.app:app --port 8000
```

Verify: `curl http://localhost:8000/api/health` → `{"status":"ok"}`

- [ ] **Step 2: Start mentoraix**

Run in a separate terminal:

```bash
cd /Users/leon/Documents/AI-mentor-coProject/mentoraix
npm run dev
```

- [ ] **Step 3: Test chat via browser**

1. Open `http://localhost:3000` in browser
2. Navigate to the Chat page
3. Send a message: "你好，我是做科技测评的创作者"
4. Verify: Response streams in normally
5. Send a follow-up: "你记得我是做什么的吗？"
6. Verify: ClawCore's memory system should recall the earlier context

- [ ] **Step 4: Verify memory was stored in ClawCore**

Check ClawCore's SQLite database for extracted facts:

```bash
cd /Users/leon/Documents/AI-mentor-coProject/ClawCore
sqlite3 clawtok.db "SELECT topic, content, confidence FROM user_facts ORDER BY created_at DESC LIMIT 10;"
```

Expected: At least one fact about the user's niche/content area.

- [ ] **Step 5: Test fallback (ClawCore off)**

1. Stop ClawCore
2. Set `CLAWCORE_BASE_URL=` (empty) in mentoraix `.env`
3. Restart mentoraix
4. Send a chat message
5. Verify: Falls back to OrbitAI or DeepSeek (response still works)

- [ ] **Step 6: Final commit**

```bash
cd mentoraix
git add -A
git commit -m "feat(chat): ClawCore integration complete with SSE adapter and fallback"
```

---

## Self-Review Checklist

**1. Spec coverage:**
- SSE format adaptation → Task 3 (parseClawCoreSSE)
- Request format conversion → Task 3 (buildClawCoreBody)
- Provider priority (ClawCore > OrbitAI > DeepSeek > Mock) → Task 3 (selectedProvider)
- userId/sessionId mapping → Task 4 (input types) + Task 5 (service passes them)
- Provider type + whitelist → Task 2
- Environment variables → Task 1
- Fallback/degradation → Task 3 (selectedProvider returns next provider when ClawCore URL empty)
- E2E testing → Task 6

**2. Placeholder scan:** No TBD, TODO, or vague instructions found.

**3. Type consistency:** All types (`Provider`, `ChatProvider`, `AiGenerateResult.provider`, `AiGenerateInput`, `AiStreamInput`) updated consistently across tasks.
