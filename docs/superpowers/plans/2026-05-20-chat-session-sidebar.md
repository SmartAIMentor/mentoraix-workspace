# Chat Session Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ChatGPT-style persistent session history to the chat page with server-backed thread management.

**Architecture:** Extend the existing chat repository with list/delete/rename methods, add 3 new API routes, create an independent chat layout (detached from LpShell), and build a sidebar component that loads threads from the server instead of localStorage.

**Tech Stack:** Next.js 16, React 19, TypeScript, Tailwind CSS, existing file-based JSON persistence

---

## File Structure

### Create
- `app/api/chat/threads/route.ts` — GET list all threads
- `app/api/chat/threads/[threadId]/route.ts` — PATCH rename, DELETE thread
- `app/(shell)/chat/layout.tsx` — independent chat layout (no LpShell)
- `features/chat-lp/chat-sidebar.tsx` — sidebar component
- `features/chat-lp/chat-drawer.tsx` — mobile drawer wrapper

### Modify
- `server/modules/chat/chat.types.ts` — add `title` to `ChatThread`
- `server/modules/chat/chat.repository.ts` — add `listThreads`, `deleteThread`, `renameThread`
- `server/modules/chat/chat.service.ts` — add `listThreads`, `deleteThread`, `renameThread`
- `features/chat-lp/chat-home.tsx` — remove localStorage, use server API, accept sidebar props

---

## Task 1: Extend ChatThread type with title

**Files:**
- Modify: `server/modules/chat/chat.types.ts`

- [ ] **Step 1: Add title field to ChatThread**

```typescript
// In server/modules/chat/chat.types.ts
// Add 'title' field to ChatThread type

export type ChatThread = {
  threadId: string;
  userId: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  messages: PersistedChatMessage[];
};
```

- [ ] **Step 2: Commit**

```bash
cd /Users/leon/Developer/CodeProject/AI-mentor-coProject/mentoraix
git add server/modules/chat/chat.types.ts
git commit -m "refactor(chat): ChatThread 新增 title 字段"
```

---

## Task 2: Extend repository with list/delete/rename

**Files:**
- Modify: `server/modules/chat/chat.repository.ts`

- [ ] **Step 1: Add listThreads, deleteThread, renameThread methods**

After the existing `saveMessage` method, add three new methods to `chatRepository`:

```typescript
async listThreads(userId: string) {
  const store = await readStore(userId);
  return store.threads
    .map(({ threadId, title, createdAt, updatedAt, messages }) => ({
      threadId,
      title,
      createdAt,
      updatedAt,
      messageCount: messages.length,
    }))
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
},

async deleteThread(input: { userId: string; threadId: string }) {
  const store = await readStore(input.userId);
  const filtered = store.threads.filter(
    (t) => t.threadId !== input.threadId,
  );
  if (filtered.length === store.threads.length) return false;
  await writeStore({ ...store, threads: filtered });
  return true;
},

async renameThread(input: {
  userId: string;
  threadId: string;
  title: string;
}) {
  const store = await readStore(input.userId);
  const thread = store.threads.find(
    (t) => t.threadId === input.threadId,
  );
  if (!thread) return false;
  thread.title = input.title;
  await writeStore(store);
  return true;
},
```

Also update `normalizeThread` to include `title`:

```typescript
// In normalizeThread, after the updatedAt extraction:
const title = typeof record.title === "string" ? record.title : "";
```

And in the return object, add `title`:

```typescript
return {
  threadId,
  userId,
  title,
  createdAt,
  updatedAt,
  messages: normalizedMessages,
};
```

And in `saveMessage`, set default title when creating a new thread:

```typescript
// In saveMessage, where a new thread is created:
thread = {
  threadId: input.threadId,
  userId: input.userId,
  title: input.message.content.slice(0, 20),
  createdAt: now,
  updatedAt: now,
  messages: [],
};
```

- [ ] **Step 2: Commit**

```bash
git add server/modules/chat/chat.repository.ts
git commit -m "feat(chat): repository 新增 listThreads/deleteThread/renameThread"
```

---

## Task 3: Extend service with list/delete/rename

**Files:**
- Modify: `server/modules/chat/chat.service.ts`

- [ ] **Step 1: Add service methods**

```typescript
// In chatService object, after streamReply:

async listThreads() {
  const user = await getSessionUser();
  if (!user) throw new AppError("UNAUTHORIZED", "User session is required", 401);
  return chatRepository.listThreads(user.id);
},

async deleteThread(threadId: string) {
  const user = await getSessionUser();
  if (!user) throw new AppError("UNAUTHORIZED", "User session is required", 401);
  const deleted = await chatRepository.deleteThread({ userId: user.id, threadId });
  if (!deleted) throw new AppError("NOT_FOUND", "Thread not found", 404);
},

async renameThread(threadId: string, title: string) {
  const user = await getSessionUser();
  if (!user) throw new AppError("UNAUTHORIZED", "User session is required", 401);
  const renamed = await chatRepository.renameThread({ userId: user.id, threadId, title });
  if (!renamed) throw new AppError("NOT_FOUND", "Thread not found", 404);
},
```

Also import `AppError` (already imported at top).

- [ ] **Step 2: Commit**

```bash
git add server/modules/chat/chat.service.ts
git commit -m "feat(chat): service 层新增 listThreads/deleteThread/renameThread"
```

---

## Task 4: Add API routes for thread management

**Files:**
- Create: `app/api/chat/threads/route.ts`
- Create: `app/api/chat/threads/[threadId]/route.ts`

- [ ] **Step 1: Create GET /api/chat/threads**

```typescript
// app/api/chat/threads/route.ts
import { chatService } from "@/server/modules/chat/chat.service";
import { apiError, apiSuccess } from "@/lib/server/response";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const threads = await chatService.listThreads();
    return apiSuccess({ threads }, { status: 200 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    const status = (error as { status?: number })?.status ?? 500;
    return apiError("THREAD_LIST_ERROR", message, { status });
  }
}
```

- [ ] **Step 2: Create PATCH + DELETE /api/chat/threads/[threadId]**

```typescript
// app/api/chat/threads/[threadId]/route.ts
import type { NextRequest } from "next/server";

import { chatService } from "@/server/modules/chat/chat.service";
import { AppError } from "@/server/shared/errors/app-error";
import { apiError, apiSuccess } from "@/lib/server/response";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ threadId: string }> },
) {
  try {
    const { threadId } = await params;
    const body = await request.json();
    const title = typeof body?.title === "string" ? body.title.trim() : "";
    if (!title) {
      return apiError("INVALID_REQUEST", "title is required", { status: 400 });
    }
    await chatService.renameThread(threadId, title);
    return apiSuccess({ ok: true }, { status: 200 });
  } catch (error) {
    if (error instanceof AppError) {
      return apiError(error.code, error.message, { status: error.status });
    }
    return apiError("INTERNAL_SERVER_ERROR", "Unexpected error", { status: 500 });
  }
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ threadId: string }> },
) {
  try {
    const { threadId } = await params;
    await chatService.deleteThread(threadId);
    return apiSuccess({ ok: true }, { status: 200 });
  } catch (error) {
    if (error instanceof AppError) {
      return apiError(error.code, error.message, { status: error.status });
    }
    return apiError("INTERNAL_SERVER_ERROR", "Unexpected error", { status: 500 });
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add app/api/chat/threads/
git commit -m "feat(chat): 新增线程管理 API（列表/重命名/删除）"
```

---

## Task 5: Create independent chat layout

**Files:**
- Create: `app/(shell)/chat/layout.tsx`

- [ ] **Step 1: Create chat-specific layout**

The chat page uses its own layout, bypassing LpShell. This layout provides the full-height grid for sidebar + conversation.

```typescript
// app/(shell)/chat/layout.tsx
import type { ReactNode } from "react";

export default function ChatLayout({
  children,
}: Readonly<{
  children: ReactNode;
}>) {
  return (
    <div
      style={{
        height: "100dvh",
        minHeight: 0,
        overflow: "hidden",
      }}
    >
      {children}
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add app/\(shell\)/chat/layout.tsx
git commit -m "feat(chat): 聊天页独立布局，脱离 LpShell"
```

---

## Task 6: Create ChatSidebar component

**Files:**
- Create: `features/chat-lp/chat-sidebar.tsx`

- [ ] **Step 1: Build the sidebar component**

```typescript
// features/chat-lp/chat-sidebar.tsx
"use client";

import { useState } from "react";
import { useLocale } from "@/components/providers/locale-provider";

export type ThreadSummary = {
  threadId: string;
  title: string;
  messageCount: number;
  updatedAt: string;
};

type ChatSidebarProps = {
  threads: ThreadSummary[];
  activeThreadId: string | null;
  onSelect: (threadId: string) => void;
  onNewChat: () => void;
  onDelete: (threadId: string) => void;
  onRename: (threadId: string, title: string) => void;
};

function groupByDate(
  threads: ThreadSummary[],
  locale: "zh" | "en",
): { label: string; threads: ThreadSummary[] }[] {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterday = new Date(today.getTime() - 86400000);

  const groups: {
    today: ThreadSummary[];
    yesterday: ThreadSummary[];
    older: ThreadSummary[];
  } = { today: [], yesterday: [], older: [] };

  for (const t of threads) {
    const d = new Date(t.updatedAt);
    if (d >= today) groups.today.push(t);
    else if (d >= yesterday) groups.yesterday.push(t);
    else groups.older.push(t);
  }

  const result: { label: string; threads: ThreadSummary[] }[] = [];
  if (groups.today.length)
    result.push({
      label: locale === "zh" ? "今天" : "Today",
      threads: groups.today,
    });
  if (groups.yesterday.length)
    result.push({
      label: locale === "zh" ? "昨天" : "Yesterday",
      threads: groups.yesterday,
    });
  if (groups.older.length)
    result.push({
      label: locale === "zh" ? "更早" : "Earlier",
      threads: groups.older,
    });
  return result;
}

export function ChatSidebar({
  threads,
  activeThreadId,
  onSelect,
  onNewChat,
  onDelete,
  onRename,
}: ChatSidebarProps) {
  const { locale } = useLocale();
  const [menuOpenId, setMenuOpenId] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editTitle, setEditTitle] = useState("");

  const groups = groupByDate(threads, locale);

  const startRename = (t: ThreadSummary) => {
    setEditingId(t.threadId);
    setEditTitle(t.title);
    setMenuOpenId(null);
  };

  const submitRename = (threadId: string) => {
    const trimmed = editTitle.trim();
    if (trimmed) onRename(threadId, trimmed);
    setEditingId(null);
  };

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100%",
        background: "var(--lp-bg)",
      }}
    >
      {/* Header */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "16px 14px 12px",
        }}
      >
        <div
          style={{
            width: 28,
            height: 28,
            borderRadius: 8,
            background: "var(--lp-accent, #7c6ff7)",
            display: "grid",
            placeItems: "center",
            color: "#fff",
            fontSize: 13,
            fontWeight: 700,
          }}
        >
          M
        </div>
        <span
          style={{
            fontWeight: 600,
            fontSize: 14,
            color: "var(--lp-ink)",
            flex: 1,
          }}
        >
          Mentoraix
        </span>
        <button
          type="button"
          onClick={onNewChat}
          title={locale === "zh" ? "新建对话" : "New chat"}
          style={{
            padding: "4px 10px",
            borderRadius: 6,
            border: "1px solid var(--lp-line)",
            background: "var(--lp-bg-elev)",
            color: "var(--lp-ink-2)",
            cursor: "pointer",
            fontSize: 12,
          }}
        >
          +
        </button>
      </div>

      {/* Thread list */}
      <div style={{ flex: 1, overflowY: "auto", padding: "0 8px" }}>
        {groups.map((group) => (
          <div key={group.label} style={{ marginBottom: 12 }}>
            <div
              style={{
                fontSize: 10,
                textTransform: "uppercase",
                letterSpacing: "0.08em",
                color: "var(--lp-ink-3)",
                fontWeight: 600,
                padding: "4px 8px 6px",
              }}
            >
              {group.label}
            </div>
            {group.threads.map((t) => {
              const active = t.threadId === activeThreadId;
              const isEditing = editingId === t.threadId;

              return (
                <div
                  key={t.threadId}
                  style={{
                    position: "relative",
                    borderRadius: "var(--lp-r-sm, 6px)",
                    background: active ? "var(--lp-bg-elev)" : "transparent",
                    marginBottom: 2,
                  }}
                  onMouseEnter={() => setMenuOpenId(t.threadId)}
                  onMouseLeave={() => {
                    if (menuOpenId === t.threadId) setMenuOpenId(null);
                  }}
                >
                  {isEditing ? (
                    <input
                      autoFocus
                      value={editTitle}
                      onChange={(e) => setEditTitle(e.target.value)}
                      onBlur={() => submitRename(t.threadId)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") submitRename(t.threadId);
                        if (e.key === "Escape") setEditingId(null);
                      }}
                      style={{
                        width: "100%",
                        border: "1px solid var(--lp-line-strong)",
                        borderRadius: 4,
                        padding: "6px 8px",
                        fontSize: 13,
                        background: "var(--lp-bg-elev)",
                        color: "var(--lp-ink)",
                        outline: "none",
                      }}
                    />
                  ) : (
                    <button
                      type="button"
                      onClick={() => onSelect(t.threadId)}
                      style={{
                        width: "100%",
                        textAlign: "left",
                        background: "transparent",
                        border: "none",
                        padding: "8px 28px 8px 10px",
                        cursor: "pointer",
                        color: active ? "var(--lp-ink)" : "var(--lp-ink-2)",
                        display: "flex",
                        flexDirection: "column",
                        gap: 2,
                      }}
                    >
                      <span
                        style={{
                          fontSize: 13,
                          fontWeight: active ? 500 : 400,
                          overflow: "hidden",
                          textOverflow: "ellipsis",
                          whiteSpace: "nowrap",
                        }}
                      >
                        {t.title || t.threadId}
                      </span>
                    </button>
                  )}

                  {/* Context menu trigger */}
                  {menuOpenId === t.threadId && !isEditing && (
                    <div
                      style={{
                        position: "absolute",
                        top: 4,
                        right: 4,
                        display: "flex",
                        gap: 2,
                      }}
                    >
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          startRename(t);
                        }}
                        title={locale === "zh" ? "重命名" : "Rename"}
                        style={{
                          width: 22,
                          height: 22,
                          borderRadius: 4,
                          background: "var(--lp-bg-sunk)",
                          border: "none",
                          color: "var(--lp-ink-3)",
                          cursor: "pointer",
                          fontSize: 10,
                          display: "grid",
                          placeItems: "center",
                        }}
                      >
                        ✎
                      </button>
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onDelete(t.threadId);
                          setMenuOpenId(null);
                        }}
                        title={locale === "zh" ? "删除" : "Delete"}
                        style={{
                          width: 22,
                          height: 22,
                          borderRadius: 4,
                          background: "var(--lp-bg-sunk)",
                          border: "none",
                          color: "var(--lp-ink-3)",
                          cursor: "pointer",
                          fontSize: 10,
                          display: "grid",
                          placeItems: "center",
                        }}
                      >
                        ×
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        ))}
      </div>

      {/* Footer */}
      <div
        style={{
          padding: "10px 14px",
          borderTop: "1px solid var(--lp-line)",
        }}
      >
        <a
          href="/insights"
          style={{
            fontSize: 12,
            color: "var(--lp-ink-3)",
            textDecoration: "none",
            display: "flex",
            alignItems: "center",
            gap: 4,
          }}
        >
          ← {locale === "zh" ? "返回主页" : "Back to home"}
        </a>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add features/chat-lp/chat-sidebar.tsx
git commit -m "feat(chat): 新增 ChatSidebar 侧边栏组件（日期分组/重命名/删除）"
```

---

## Task 7: Create ChatDrawer for mobile

**Files:**
- Create: `features/chat-lp/chat-drawer.tsx`

- [ ] **Step 1: Build the mobile drawer wrapper**

```typescript
// features/chat-lp/chat-drawer.tsx
"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type ChatDrawerProps = {
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
};

export function ChatDrawer({ open, onClose, children }: ChatDrawerProps) {
  const [visible, setVisible] = useState(false);
  const drawerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (open) {
      setVisible(true);
    } else {
      // Wait for animation to finish
      const timer = setTimeout(() => setVisible(false), 200);
      return () => clearTimeout(timer);
    }
  }, [open]);

  const onBackdropClick = useCallback(
    (e: React.MouseEvent) => {
      if (e.target === e.currentTarget) onClose();
    },
    [onClose],
  );

  if (!visible && !open) return null;

  return (
    <div
      onClick={onBackdropClick}
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 50,
        background: open ? "rgba(0,0,0,0.3)" : "rgba(0,0,0,0)",
        transition: "background 0.2s",
        display: "flex",
      }}
    >
      <div
        ref={drawerRef}
        style={{
          width: "85vw",
          maxWidth: 360,
          height: "100%",
          background: "var(--lp-bg)",
          transform: open ? "translateX(0)" : "translateX(-100%)",
          transition: "transform 0.2s ease-out",
          overflow: "hidden",
        }}
      >
        {children}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add features/chat-lp/chat-drawer.tsx
git commit -m "feat(chat): 新增 ChatDrawer 移动端抽屉组件"
```

---

## Task 8: Refactor ChatHome to use server API

**Files:**
- Modify: `features/chat-lp/chat-home.tsx`

This is the largest task. Replace localStorage thread management with server API calls, integrate ChatSidebar and ChatDrawer, add mobile responsive behavior.

- [ ] **Step 1: Rewrite ChatHome**

Key changes:
1. Remove `loadStore`, `persist`, `STORE_KEY`, `ACTIVE_KEY` and all localStorage logic
2. Add `fetchThreads()`, `fetchThreadMessages()` functions calling server API
3. Add `handleDeleteThread()`, `handleRenameThread()` functions
4. Render `ChatSidebar` in desktop slot, `ChatDrawer` + `ChatSidebar` in mobile
5. Replace inline sidebar JSX with `<ChatSidebar />`
6. Add mobile hamburger button in chat header

The full rewrite of `chat-home.tsx`:

```typescript
"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { useLocale } from "@/components/providers/locale-provider";
import { ChatToolsStrip } from "./chat-tools-strip";
import { TodayContextStrip } from "./today-context-strip";
import { useToast } from "@/components/ui/toast";
import { LpButton, LpPill } from "@/components/lp";
import { ChatSidebar, type ThreadSummary } from "./chat-sidebar";
import { ChatDrawer } from "./chat-drawer";

type Message = {
  role: "user" | "assistant";
  content: string;
  createdAt: number;
  actions?: { label: string; href?: string; intent?: string }[];
};

const SUGGESTED_PROMPTS_ZH = ["今天发什么", "本周复盘"] as const;
const SUGGESTED_PROMPTS_EN = ["What today", "Week recap"] as const;

function formatWhen(ts: number, locale: "zh" | "en"): string {
  const diffMs = Date.now() - ts;
  const min = Math.floor(diffMs / 60_000);
  if (min < 1) return locale === "zh" ? "刚刚" : "now";
  if (min < 60) return locale === "zh" ? `${min} 分前` : `${min}m`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return locale === "zh" ? `${hr} 小时前` : `${hr}h`;
  return new Date(ts).toLocaleDateString();
}

async function fetchThreads(): Promise<ThreadSummary[]> {
  const res = await fetch("/api/chat/threads");
  const body = await res.json();
  if (!body.ok) throw new Error(body.error?.message ?? "Failed to load threads");
  return body.data.threads;
}

async function fetchThreadMessages(
  threadId: string,
): Promise<{ messages: Message[]; threadId: string }> {
  const res = await fetch(`/api/chat?threadId=${encodeURIComponent(threadId)}`);
  const body = await res.json();
  if (!body.ok) throw new Error(body.error?.message ?? "Failed to load thread");
  const thread = body.data.thread;
  if (!thread) return { messages: [], threadId };
  return {
    threadId: thread.threadId,
    messages: (thread.messages ?? []).map(
      (m: { role: string; content: string; createdAt: string }) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
        createdAt: new Date(m.createdAt).getTime(),
      }),
    ),
  };
}

export function ChatHome() {
  const { locale } = useLocale();
  const { toast } = useToast();
  const searchParams = useSearchParams();

  const [threads, setThreads] = useState<ThreadSummary[]>([]);
  const [activeThreadId, setActiveThreadId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [loadingThread, setLoadingThread] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const initRef = useRef(false);

  // Load thread list on mount
  useEffect(() => {
    if (initRef.current) return;
    initRef.current = true;

    fetchThreads()
      .then((t) => {
        setThreads(t);
        // Select latest thread or wait for ?new=1
        if (searchParams?.get("new") !== "1" && t.length > 0) {
          setActiveThreadId(t[0].threadId);
        }
      })
      .catch((err) => {
        toast(err.message, "error");
      });

    const prefill = searchParams?.get("prefill");
    if (prefill) {
      setInput(prefill);
      setTimeout(() => inputRef.current?.focus(), 80);
    }
  }, [searchParams, toast]);

  // Load messages when active thread changes
  useEffect(() => {
    if (!activeThreadId) {
      setMessages([]);
      return;
    }
    setLoadingThread(true);
    fetchThreadMessages(activeThreadId)
      .then((data) => {
        setMessages(data.messages);
      })
      .catch((err) => {
        toast(err.message, "error");
      })
      .finally(() => setLoadingThread(false));
  }, [activeThreadId, toast]);

  // Auto-scroll
  useEffect(() => {
    scrollRef.current?.scrollTo({
      top: scrollRef.current.scrollHeight,
      behavior: "smooth",
    });
  }, [messages.length, activeThreadId]);

  const refreshThreads = useCallback(async () => {
    try {
      const t = await fetchThreads();
      setThreads(t);
    } catch {
      // silent
    }
  }, []);

  const send = useCallback(
    async (raw?: string) => {
      const text = (raw ?? input).trim();
      if (!text || busy) return;
      setError(null);
      setBusy(true);
      setInput("");

      const userMsg: Message = {
        role: "user",
        content: text,
        createdAt: Date.now(),
      };
      setMessages((prev) => [...prev, userMsg]);

      try {
        const res = await fetch("/api/chat", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            message: text,
            threadId: activeThreadId ?? undefined,
          }),
        });
        const body = await res.json();
        if (!body.ok) throw new Error(body.error?.message ?? "Send failed");

        const reply: Message = {
          role: "assistant",
          content: body.data.message.content as string,
          createdAt: Date.now(),
        };
        setMessages((prev) => [...prev, reply]);

        // If this was a new thread, capture the server-assigned ID
        if (!activeThreadId) {
          setActiveThreadId(body.data.threadId);
        }
        // Refresh thread list to reflect new/updated thread
        await refreshThreads();
      } catch (err) {
        const msg = err instanceof Error ? err.message : "Network error";
        setError(msg);
        toast(msg, "error");
      } finally {
        setBusy(false);
        inputRef.current?.focus();
      }
    },
    [input, busy, activeThreadId, toast, refreshThreads],
  );

  const startNewChat = useCallback(() => {
    setActiveThreadId(null);
    setMessages([]);
    setInput("");
    setDrawerOpen(false);
    inputRef.current?.focus();
  }, []);

  const handleSelectThread = useCallback(
    (threadId: string) => {
      setActiveThreadId(threadId);
      setDrawerOpen(false);
    },
    [],
  );

  const handleDeleteThread = useCallback(
    async (threadId: string) => {
      try {
        const res = await fetch(`/api/chat/threads/${encodeURIComponent(threadId)}`, {
          method: "DELETE",
        });
        const body = await res.json();
        if (!body.ok) throw new Error(body.error?.message ?? "Delete failed");

        if (threadId === activeThreadId) {
          const remaining = threads.filter((t) => t.threadId !== threadId);
          setActiveThreadId(remaining[0]?.threadId ?? null);
        }
        await refreshThreads();
        toast(locale === "zh" ? "会话已删除" : "Thread removed", "info");
      } catch (err) {
        toast(err instanceof Error ? err.message : "Delete failed", "error");
      }
    },
    [activeThreadId, threads, locale, toast, refreshThreads],
  );

  const handleRenameThread = useCallback(
    async (threadId: string, title: string) => {
      try {
        const res = await fetch(`/api/chat/threads/${encodeURIComponent(threadId)}`, {
          method: "PATCH",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ title }),
        });
        const body = await res.json();
        if (!body.ok) throw new Error(body.error?.message ?? "Rename failed");
        await refreshThreads();
      } catch (err) {
        toast(err instanceof Error ? err.message : "Rename failed", "error");
      }
    },
    [toast, refreshThreads],
  );

  const activeTitle = useMemo(
    () => threads.find((t) => t.threadId === activeThreadId)?.title ?? null,
    [threads, activeThreadId],
  );

  const sidebarContent = (
    <ChatSidebar
      threads={threads}
      activeThreadId={activeThreadId}
      onSelect={handleSelectThread}
      onNewChat={startNewChat}
      onDelete={handleDeleteThread}
      onRename={handleRenameThread}
    />
  );

  return (
    <>
      {/* Mobile drawer */}
      <ChatDrawer open={drawerOpen} onClose={() => setDrawerOpen(false)}>
        {sidebarContent}
      </ChatDrawer>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "240px 1fr",
          height: "100%",
          minHeight: 0,
        }}
        className="lp-chat-grid"
      >
        {/* Desktop sidebar */}
        <aside
          className="lp-chat-aside"
          style={{
            borderRight: "1px solid var(--lp-line)",
            display: "flex",
            flexDirection: "column",
            overflow: "hidden",
          }}
        >
          {sidebarContent}
        </aside>

        {/* Conversation column */}
        <section
          style={{
            display: "flex",
            flexDirection: "column",
            minWidth: 0,
            minHeight: 0,
          }}
        >
          {/* Chat header */}
          <div
            style={{
              padding: "20px 32px 12px",
              display: "flex",
              alignItems: "center",
              gap: 12,
            }}
          >
            {/* Mobile hamburger */}
            <button
              type="button"
              onClick={() => setDrawerOpen(true)}
              className="lp-chat-hamburger"
              aria-label={locale === "zh" ? "打开侧边栏" : "Open sidebar"}
              style={{
                display: "none",
                width: 32,
                height: 32,
                borderRadius: 6,
                border: "1px solid var(--lp-line)",
                background: "var(--lp-bg-elev)",
                color: "var(--lp-ink-2)",
                cursor: "pointer",
                fontSize: 16,
                placeItems: "center",
                flexShrink: 0,
              }}
            >
              ☰
            </button>
            <h1
              style={{
                margin: 0,
                fontSize: 20,
                fontWeight: 600,
                letterSpacing: "-0.02em",
                color: "var(--lp-ink)",
              }}
            >
              M · {locale === "zh" ? "你的导师" : "Your mentor"}
            </h1>
            <span style={{ fontSize: 12, color: "var(--lp-ink-3)" }}>
              {activeTitle}
              {busy ? (locale === "zh" ? " · M 正在想…" : " · M thinking…") : ""}
            </span>
            <button
              type="button"
              onClick={startNewChat}
              className="lp-btn lp-btn-sm lp-btn-ghost"
              style={{ marginLeft: "auto" }}
            >
              {locale === "zh" ? "+ 新对话" : "+ New chat"}
            </button>
          </div>

          <TodayContextStrip />

          {/* Scroll region */}
          <div
            ref={scrollRef}
            style={{
              flex: 1,
              overflowY: "auto",
              padding: "16px 32px 32px",
            }}
          >
            <div
              style={{
                maxWidth: 720,
                margin: "0 auto",
                display: "flex",
                flexDirection: "column",
                gap: 20,
              }}
            >
              {loadingThread ? (
                <div
                  style={{
                    textAlign: "center",
                    padding: 48,
                    color: "var(--lp-ink-3)",
                    fontSize: 14,
                  }}
                >
                  {locale === "zh" ? "加载中…" : "Loading…"}
                </div>
              ) : messages.length === 0 ? (
                <div
                  style={{
                    textAlign: "center",
                    padding: "48px 16px",
                    color: "var(--lp-ink-3)",
                    fontSize: 14,
                  }}
                >
                  <div
                    style={{
                      fontSize: 24,
                      fontWeight: 600,
                      color: "var(--lp-ink)",
                      letterSpacing: "-0.02em",
                    }}
                  >
                    {locale === "zh" ? "和 M 聊点什么" : "What's on your mind"}
                  </div>
                  <p style={{ marginTop: 8, lineHeight: 1.7 }}>
                    {locale === "zh"
                      ? "粘一段品牌邮件 / 商品 URL,或者从下面的快捷开场开始。"
                      : "Paste a brand DM or product URL, or pick a starter below."}
                  </p>
                </div>
              ) : (
                messages.map((m, i) => <MessageRow key={i} message={m} />)
              )}
              {busy ? <TypingIndicator locale={locale} /> : null}
              {error ? (
                <div
                  style={{
                    padding: "10px 14px",
                    background: "var(--lp-danger-soft)",
                    color: "var(--lp-danger)",
                    borderRadius: "var(--lp-r-sm)",
                    fontSize: 13,
                  }}
                >
                  {error}
                </div>
              ) : null}
            </div>
          </div>

          {/* Composer */}
          <div
            className="lp-chat-composer"
            style={{
              borderTop: "1px solid var(--lp-line)",
              padding: "12px 32px 24px",
              background: "var(--lp-bg)",
            }}
          >
            <div style={{ maxWidth: 720, margin: "0 auto" }}>
              <ChatToolsStrip />
              <div
                className="lp-chat-suggested"
                style={{
                  display: "flex",
                  gap: 6,
                  flexWrap: "wrap",
                  marginBottom: 10,
                  overflowX: "auto",
                }}
              >
                {(locale === "zh" ? SUGGESTED_PROMPTS_ZH : SUGGESTED_PROMPTS_EN).map(
                  (p) => (
                    <button
                      key={p}
                      type="button"
                      onClick={() => void send(p)}
                      className="lp-btn lp-btn-sm"
                      style={{ whiteSpace: "nowrap" }}
                      disabled={busy}
                    >
                      {p}
                    </button>
                  ),
                )}
              </div>
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  void send();
                }}
                style={{
                  background: "var(--lp-bg-elev)",
                  border: "1px solid var(--lp-line-strong)",
                  borderRadius: "var(--lp-r-md)",
                  padding: "10px 12px",
                  display: "flex",
                  gap: 10,
                  alignItems: "center",
                  boxShadow: "var(--lp-shadow-soft)",
                }}
              >
                <input
                  ref={inputRef}
                  value={input}
                  onChange={(e) => setInput(e.target.value)}
                  placeholder={locale === "zh" ? "回复 M……" : "Reply to M…"}
                  aria-label={locale === "zh" ? "对话输入" : "Chat input"}
                  style={{
                    flex: 1,
                    border: "none",
                    outline: "none",
                    background: "transparent",
                    fontFamily: "inherit",
                    fontSize: 14,
                    color: "var(--lp-ink)",
                    minWidth: 0,
                  }}
                />
                <kbd
                  style={{
                    fontSize: 10,
                    color: "var(--lp-ink-3)",
                    background: "var(--lp-bg-sunk)",
                    padding: "2px 6px",
                    borderRadius: 4,
                    fontFamily:
                      "var(--font-mono, ui-monospace, monospace)",
                  }}
                  aria-hidden
                >
                  ⏎
                </kbd>
                <LpButton
                  type="submit"
                  variant="primary"
                  size="sm"
                  disabled={!input.trim() || busy}
                >
                  {locale === "zh" ? "发送" : "Send"} →
                </LpButton>
              </form>
            </div>
          </div>
        </section>
      </div>

      {/* Mobile responsive overrides */}
      <style>{`
        @media (max-width: 768px) {
          .lp-chat-grid {
            grid-template-columns: 1fr !important;
          }
          .lp-chat-aside {
            display: none !important;
          }
          .lp-chat-hamburger {
            display: grid !important;
          }
        }
      `}</style>
    </>
  );
}

function MessageRow({ message }: { message: Message }) {
  const { locale } = useLocale();
  const isM = message.role === "assistant";
  return (
    <div style={{ display: "flex", gap: 12 }}>
      <div
        aria-hidden
        style={{
          width: 28,
          height: 28,
          borderRadius: "var(--lp-r-sm)",
          background: isM ? "var(--lp-ink)" : "var(--lp-accent)",
          color: "#fff",
          display: "grid",
          placeItems: "center",
          fontSize: 12,
          fontWeight: 600,
          flexShrink: 0,
        }}
      >
        {isM ? "M" : "L"}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <p
          style={{
            margin: 0,
            fontSize: 14,
            lineHeight: 1.65,
            color: "var(--lp-ink)",
            whiteSpace: "pre-wrap",
          }}
        >
          {message.content}
        </p>
        {message.actions?.length ? (
          <div style={{ marginTop: 10, display: "flex", gap: 6, flexWrap: "wrap" }}>
            {message.actions.map((a, i) => {
              const cls =
                i === 0 ? "lp-btn lp-btn-sm lp-btn-primary" : "lp-btn lp-btn-sm";
              if (a.href) {
                return (
                  <Link key={i} href={a.href} className={cls}>
                    {a.label}
                  </Link>
                );
              }
              return (
                <button key={i} type="button" className={cls}>
                  {a.label}
                </button>
              );
            })}
          </div>
        ) : null}
        {!message.actions?.length && isM ? (
          <div style={{ marginTop: 6, display: "flex", gap: 4 }}>
            <LpPill>M</LpPill>
            <span style={{ fontSize: 10, color: "var(--lp-ink-3)" }}>
              {formatWhen(message.createdAt, locale)}
            </span>
          </div>
        ) : null}
      </div>
    </div>
  );
}

function TypingIndicator({ locale }: { locale: "zh" | "en" }) {
  return (
    <div style={{ display: "flex", gap: 12 }}>
      <div
        style={{
          width: 28,
          height: 28,
          borderRadius: "var(--lp-r-sm)",
          background: "var(--lp-ink)",
          color: "#fff",
          display: "grid",
          placeItems: "center",
          fontSize: 12,
          fontWeight: 600,
        }}
      >
        M
      </div>
      <div
        style={{
          padding: "8px 14px",
          background: "var(--lp-bg-soft)",
          borderRadius: "var(--lp-r-md)",
          fontSize: 13,
          color: "var(--lp-ink-3)",
          display: "flex",
          alignItems: "center",
          gap: 6,
        }}
      >
        <span
          style={{
            width: 6,
            height: 6,
            borderRadius: "50%",
            background: "var(--lp-accent)",
            animation: "skeleton-pulse 1s ease-in-out infinite",
          }}
        />
        {locale === "zh" ? "M 正在想…" : "M is thinking…"}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add features/chat-lp/chat-home.tsx
git commit -m "feat(chat): 重构 ChatHome，从 localStorage 迁移到服务端 API"
```

---

## Task 9: Build and smoke test

- [ ] **Step 1: Run TypeScript check**

```bash
cd /Users/leon/Developer/CodeProject/AI-mentor-coProject/mentoraix
npx tsc --noEmit
```

Expected: No type errors.

- [ ] **Step 2: Run build**

```bash
npm run build
```

Expected: Build succeeds with no errors.

- [ ] **Step 3: Run lint**

```bash
npm run lint
```

Expected: No lint errors (or only pre-existing ones).

- [ ] **Step 4: Commit any fixes**

If any type errors or lint issues arise, fix them and commit:

```bash
git add -A
git commit -m "fix(chat): 修复类型检查和 lint 问题"
```

---

## Task 10: Manual smoke test and push

- [ ] **Step 1: Start dev server**

```bash
cd /Users/leon/Developer/CodeProject/AI-mentor-coProject/mentoraix
npm run dev
```

- [ ] **Step 2: Verify in browser**

Open http://localhost:3000/chat and verify:

1. Desktop: Sidebar shows on left (240px), conversation on right
2. Sidebar shows thread list loaded from server (may be empty initially)
3. Click "+ New chat" → clears messages, starts fresh
4. Send a message → creates new thread, reply appears
5. Send another message in same thread → conversation continues
6. Thread appears in sidebar after first message
7. Click thread in sidebar → switches to that conversation
8. Hover thread → rename/delete buttons appear
9. Rename a thread → title updates in sidebar
10. Delete a thread → removed from sidebar, switches to another
11. Mobile (< 768px): sidebar hidden, hamburger button visible
12. Hamburger opens drawer with thread list

- [ ] **Step 3: Push to remote**

```bash
git push origin leroy
```
