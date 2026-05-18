---
name: leroy-merge-record
description: mentoraix leroy 分支合入 ClawCore 联调代码的完整操作记录与验证报告
metadata:
  type: project
---

# mentoraix leroy 分支合并记录

**日期**: 2026-05-17
**操作者**: leonalgo
**目标**: 将 ClawCore AgentCore 记忆服务联调代码从 master 合入队友的主开发分支 leroy

## 背景

mentoraix 仓库存在多个并行分支：
- **master**: 原始主分支，我们的 ClawCore 联调提交 (`d16a383`) 在此
- **leroy**: 队友 Leroy 的主开发分支（275 提交，196 个领先于 master）
- **leroy-v2**: 从 leroy 分出的精简版
- **mentor-new**: 中间整合分支（23 个提交）

队友确认以 **leroy** 作为交付主分支，需要将我们的联调代码合入。

## 分支作者身份确认

通过 Git 邮箱确认：
| Git 用户名 | 邮箱 | 真实身份 |
|------------|------|----------|
| Leroy / LeroyCreates / Leooooooow | 130833525+Leooooooow@users.noreply.github.com | 队友 Leroy |
| Qiuner | wdst3635@163.com | 队友 Qiuner |
| leon / leonalgo | — | leonalgo（本文档作者）|
| integrate | local@integrate | 自动化工具/CI |
| Claude | — | AI 辅助提交 |

## 合并策略

采用 **cherry-pick** 而非 merge/rebase，因为：
- master 上只有 4 个提交领先于 leroy
- leroy 领先 196 个提交，rebase 风险过高
- 通过 worktree 隔离操作，安全可控

## 操作过程

### 1. 创建 worktree

```
目录: .worktrees/leroy-merge/
基底: origin/leroy (3771f70)
.gitignore: 添加 .worktrees/ 条目
依赖: npm install 完成
```

### 2. Cherry-pick 执行

| 提交 | 说明 | 结果 |
|------|------|------|
| `10c9176` | fix: 修复 Me 页语言切换不生效 | 成功合入 → `3bb755b` |
| `f8972d6` | chore: add local env backups | 跳过（含 API 密钥） |
| `c605d84` | feat(aura): 移除聊天界面空状态显示 | 跳过（leroy 已有更完善版本） |
| `d16a383` | feat(chat): 接入 ClawCore AgentCore 记忆服务 | 成功合入 → `488d745`（+209 行） |

### 3. 冲突处理

仅 `chat-screen.tsx` 出现冲突（2 处），均因我们的提交要删除空状态 UI，而 leroy 已有更完善的带建议按钮版本。

**解决**: 保留 leroy 版本。

### 4. 合并到 leroy

```
git checkout leroy
git merge leroy-merge --no-ff
→ 合并提交: cd42021
→ git push origin leroy
```

## 变更文件清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `.env.example` | 新增 | CLAWCORE_BASE_URL / CLAWCORE_API_KEY 配置示例 |
| `lib/server/env.ts` | 新增 | 两个 ClawCore 环境变量读取 |
| `server/core/ai/provider.ts` | 核心变更 | +202 行，clawcore provider 完整实现 |
| `server/modules/chat/chat.service.ts` | 新增 | userId + sessionId 传入 AI 调用 |
| `server/modules/chat/chat.types.ts` | 新增 | ChatProvider 联合类型新增 "clawcore" |
| `server/modules/chat/chat.repository.ts` | 新增 | provider 白名单新增 "clawcore" |
| `features/aura/components/aura-prototype-enhancer.tsx` | 微调 | Me 页语言修复 |
| `features/aura/pages/me-screen.tsx` | 微调 | Me 页语言修复 |

## E2E 验证结果

**环境**: ClawCore `localhost:8000` (SiliconFlow Qwen) + mentoraix `localhost:3000` (Turbopack)

| # | 测试项 | 结果 | 关键证据 |
|---|--------|------|----------|
| 1 | ClawCore 直接调用 | 通过 | SSE 事件序列完整，中文回复 |
| 2 | mentoraix → ClawCore 非流式 | 通过 | `"provider":"clawcore"` |
| 3 | mentoraix → ClawCore 流式 SSE | 通过 | HTTP 200，`x-chat-thread-id` 正确 |
| 4 | 多轮对话（同 thread） | 通过 | 上下文延续正常 |
| 5 | 跨会话记忆 | 通过 | ClawCore DB 有 10+ extracted facts |
| 6 | 页面路由可达性（9 个页面） | 通过 | 全部 200 或正常重定向 |
| 7 | Provider 优先级 | 通过 | clawcore → orbitai → deepseek → mock |
| - | TypeScript 编译 | 通过 | `npx tsc --noEmit` 零错误 |
| - | Next.js 生产构建 | 通过 | `npx next build` 成功 |

## 相关文档

- [[2026-05-05-clawcore-chat-integration-design]] — ClawCore 聊天联调设计方案
- [[2026-05-05-memory-service-design]] — 独立 Memory Service 设计方案（已冻结）

## 后续

- 队友可在 leroy 分支上直接使用带记忆的 Chat M 功能
- 需在 `.env.local` 中配置 `CLAWCORE_BASE_URL=http://localhost:8000` 启用 ClawCore provider
- 未配置时自动降级到 DeepSeek/OrbitAI/Mock
