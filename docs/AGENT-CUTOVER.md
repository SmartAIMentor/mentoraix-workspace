# Agent 框架切换指南 — ClawCore → Hermes + OpenViking

> 状态：影子栈**功能完备 + 端到端验证通过**，可切换。ClawCore(:8001) 保留作回滚。
> 适用：想把 Mentoraixs 从旧 agent(ClawCore) 切到新栈的协作者。

---

## 背景

旧 agent 是 **ClawCore**（:8001，FastAPI，FTS5 记忆）。新栈用 **Hermes（agent 大脑）+ 自托管 OpenViking（多租户记忆库）+ 自建 adapter（编排+鉴权）** 替换它，复用 ClawCore 已验证的"请求级 user_id + per-user 记忆隔离"多对一模式。详见 `AI-mentor-coProject/docs/Hermes-OpenViking-Migration-Plan.md`。

---

## 新栈端口

| 服务 | 端口 | 作用 |
|---|---|---|
| OpenViking（自托管，trusted 模式）| 1933 | 多租户记忆库（本地持久）|
| Hermes gateway（memory provider 关）| 8002 | agent 大脑，无状态 chat |
| hermes-clawcore-adapter | 8003 | 多租户编排 + SSE 翻译 + JWT 鉴权 |
| ClawCore（旧，保留）| 8001 | 回滚用 |

代码：`agent-runtime-lab/hermes-clawcore-adapter/`（`start.sh`/`stop.sh`/`main.py`/`openviking_client.py`/`auth.py`/`db.py`/`mentoraix_mcp.py`）。OV 持久数据：`~/.mentoraix/ov-server/`。

---

## 切换步骤（旧 → 新）

```bash
# 1. 起新栈（一键起 OV:1933 + Hermes:8002 + adapter:8003，自带健康检查）
bash agent-runtime-lab/hermes-clawcore-adapter/start.sh

# 2. Mentoraixs 指向新栈
#    编辑 mentoraixs/.env.local：
CLAWCORE_BASE_URL=http://localhost:8003

# 3. 重启 Mentoraixs，聊一轮验证（chat + 记忆 + 业务工具）

# 生产（开鉴权）：
DEV_MODE=false JWT_SECRET=<你的密钥> bash agent-runtime-lab/hermes-clawcore-adapter/start.sh
```

---

## 回滚（新 → 旧）

```bash
# 1. Mentoraixs 指回 ClawCore（备份在 mentoraixs/.env.local.bak）
CLAWCORE_BASE_URL=http://localhost:8001   # 改 .env.local，重启 Mentoraixs

# 2. 确保 ClawCore :8001 在跑（cd ClawCore && 按其文档启动）

# 3. 停新栈（可选）
bash agent-runtime-lab/hermes-clawcore-adapter/stop.sh
```

---

## 已迁移 vs 未迁移

| 能力 | 状态 |
|---|---|
| chat/ReAct、长期记忆+多租户、事实/偏好抽取 | ✅ Hermes + OpenViking |
| analytics_review、publish_social（**含图片/视频上传**）| ✅ MCP server（`mentoraix_mcp.py`）|
| infra(file/web/terminal)、调度、技能 | ✅ Hermes 原生 |
| 鉴权 / 持久化 / 启停 / 回滚 | ✅ JWT + SQLite + start.sh + :8001 |
| 飞书 / TikTok 适配器（M4）| ⏸ 暂缓（业务需要时再做；Hermes 无原生）|
| create_start / create_list / opportunity | ❌ 死代码（前端已直连绕过），不迁 |

---

## 上线前待决策

- **AGPL 法务**：OpenViking 是 AGPL-3.0。当前 arm's length（走 HTTP API，不 import SDK）姿势安全，付费上线前需法务拍板（go/no-go 门槛）。
- **正式退役 ClawCore :8001**：切换稳定运行一段时间后，再关。
- **生产部署**：systemd/launchd 守护（自启+崩溃重启）；规模化时考虑 Hermes 池化。
- **性能基线**：commit/recall P95（上线前测）。
