# Agent 框架升级切换指南 (ClawCore → Hermes + OpenViking)

> **给开发者和 AI 助手**：怎么把服务从旧 agent (ClawCore) 切到新栈，以及怎么**把你负责的服务接进新 agent**。
> 状态：影子栈功能完备 + 端到端验证通过；ClawCore(:8001) 保留作回滚。

---

## 一图看懂：旧 → 新

```
 【旧】                                 【新】
 Mentoraixs :3000                       Mentoraixs :3000
   └→ ClawCore :8001                      └→ adapter :8003 ──┬→ Hermes :8002 (agent 大脑·无状态)
        ├ FTS5 记忆(单库)                     (多租户编排      ├→ OpenViking :1933 (多租户记忆)
        ├ 内置业务工具                        +SSE翻译+JWT)    └→ MCP servers (各服务自己暴露的 tool)
        └ ReAct LLM                              ↑
                                               你的服务 —— 写个 MCP 接进来（见 ④）
```

**核心变化**：记忆 `FTS5 单库 → OpenViking 多租户`；业务工具 `ClawCore 内置 → 各服务用 MCP 标准协议接入`。

---

## ① 准备清单

**首次部署 OpenViking**（clone 仓库后做一次，~2 分钟）：
```bash
cd agent-runtime-lab/hermes-clawcore-adapter/ov-server
cp .env.example .env     # 填 GITEE_API_KEY(embedding) + VLM_API_KEY(stepfun/OpenAI)
bash setup.sh            # 建 venv + 生成 ov.conf + root_key（产物都 gitignore）
```

**每次启动前检查**：

| 需要什么 | 位置 | 检查命令 |
|---|---|---|
| 新栈代码 | `agent-runtime-lab/hermes-clawcore-adapter/` | `ls start.sh stop.sh ov-server/setup.sh` |
| OpenViking（已部署） | `.../hermes-clawcore-adapter/ov-server/` | `ls ov-server/venv ov-server/ov.conf` |
| Hermes（含 mcp SDK） | `agent-runtime-lab/hermes-agent/.venv` | `.venv/bin/hermes --version` |
| publish-service（业务后端） | :58888 | `curl -s :58888/api/health` |
| 密钥 | `~/.hermes/.env`、项目 `.env` | `API_SERVER_KEY`、`Gitee_API_KEY`、stepfun key |

> 深度背景见顶层 `AI-mentor-coProject/docs/Hermes-OpenViking-Migration-Plan.md`。

---

## ② 启动顺序

**一键**（推荐，按下表顺序起 + 健康检查 + 存 pid）：
```bash
bash agent-runtime-lab/hermes-clawcore-adapter/start.sh
```

| 序 | 服务 | 端口 | 约 | 健康检查 |
|---|---|---|---|---|
| 1 | OpenViking | 1933 | 5s | `curl :1933/health` → `{"healthy":true,"auth_mode":"trusted"}` |
| 2 | Hermes gateway | 8002 | 15s | `lsof -i:8002` 有进程 |
| 3 | adapter | 8003 | 5s | `curl :8003/health` → `{"ok":true,...}` |

停：`bash .../stop.sh` ｜ 生产(鉴权)：`DEV_MODE=false JWT_SECRET=<密钥> bash start.sh`

---

## ③ 配置切换

| 文件 | 改什么 | 旧 → 新 |
|---|---|---|
| `mentoraixs/.env.local` | `CLAWCORE_BASE_URL` | `http://localhost:8001` → `:8003` |
| `mentoraixs/.env.local` (生产) | 鉴权 | 加 `DEV_MODE=false` + 给 adapter 设 `JWT_SECRET` |

改完重启 Mentoraixs。**回滚** = 把 `CLAWCORE_BASE_URL` 改回 `:8001`。

---

## ④ 把你的服务接进新 Agent（写 MCP）⭐ 重点

新 agent 用 **MCP 标准协议**调外部服务。把你的服务暴露成一个 MCP tool，agent 就能在对话里调它。**3 步**：

```
① 写 MCP tool（调你服务的 API）  →  ② 注册到 Hermes config  →  ③ 验证
```

**最小模板**（复制改 `your_service_mcp.py`，参考 `mentoraix_mcp.py`）：
```python
from mcp.server.fastmcp import FastMCP
import httpx, os
mcp = FastMCP("your-service")
BASE = os.getenv("YOUR_SERVICE_URL", "http://localhost:<你的端口>")

@mcp.tool()
async def do_something(creator_id: str, foo: str) -> str:
    """一句话描述这工具干嘛（agent 靠这句决定何时调它）。"""
    async with httpx.AsyncClient(timeout=60) as c:
        r = await c.get(f"{BASE}/api/xxx",
                        headers={"X-User-Id": creator_id}, params={"foo": foo})
        r.raise_for_status()
        return r.text          # 返回字符串给 agent；失败就返回错误信息，别抛异常

if __name__ == "__main__":
    mcp.run()
```

**注册**（`~/.hermes/config.yaml` 加一段）：
```yaml
mcp_servers:
  your_service:
    command: "/Users/leon/.mentoraix/ov-server/venv/bin/python"   # 任何装了 mcp 的 venv
    args: ["/绝对路径/your_service_mcp.py"]
    env:
      YOUR_SERVICE_URL: "http://localhost:<你的端口>"
```

**验证**：`hermes mcp test your_service` → 应列出你的 tool。

> **案例**：`mentoraix_mcp.py` 的 `analytics_posts` 就这么把 publish-service `/api/analytics/posts` 包成 tool——agent 在对话里被问"分析我发帖效果"时自动调用。实测已通。

**写 MCP tool 的要点**：

| 要点 | 说明 |
|---|---|
| 名字 + docstring | agent 据此判断何时调，**写清"能干什么"** |
| 参数 | 用基础类型（str/int/list）；**`creator_id` 必带**（agent 从上下文知道当前用户）|
| 返回 | 返字符串（`json.dumps`）；**别抛异常**，失败返错误文案 |
| 鉴权 | 服务端用 `X-User-Id` 头标识用户；**别硬编码 key** |
| 运行 venv | 必须装了 `mcp` 库——**Hermes venv** 或 **OV venv**(`agent-runtime-lab/hermes-clawcore-adapter/ov-server/venv`) |

---

## 已迁 / 未迁 / 谁负责什么

| 能力 | 状态 | 负责人 |
|---|---|---|
| chat / 记忆 / 多租户 / 抽取 | ✅ 新栈自带 | — |
| analytics、publish(含媒体上传) | ✅ 已迁 MCP | publish-service 负责人 |
| 飞书 / TikTok | ⏸ 待做 | 谁负责谁按 ④ 写 MCP |
| 你负责的其他服务 | ⏸ 按 ④ 接入 | 各服务负责人 |
| `create_*` / `opportunity` | ❌ 不迁（死代码，前端已直连）| — |

---

## 回滚（新 → 旧）

```bash
# 1. Mentoraixs 指回 ClawCore
CLAWCORE_BASE_URL=http://localhost:8001   # 改 mentoraixs/.env.local，重启 Mentoraixs
# 2. 确保 ClawCore :8001 在跑
# 3. 停新栈（可选）
bash agent-runtime-lab/hermes-clawcore-adapter/stop.sh
```

---

## 上线前待决策
- **AGPL 法务**：OpenViking 是 AGPL-3.0；当前 arm's length(HTTP API) 安全，付费上线前法务拍板。
- **正式退役 ClawCore :8001**：切换稳定运行一段时间后关。
- **生产化**：systemd/launchd 守护（自启+崩重启）、性能基线（commit/recall P95）。

## FAQ
| 问题 | 排查 |
|---|---|
| agent 说"没有这个工具" | `hermes mcp test <name>` 看连上没；Hermes venv 装了 `mcp` 库没 |
| 端口冲突 | 新栈用 :1933/:8002/:8003，与旧的 :8001/:58888/:3000 不冲突 |
| OV 数据会丢吗 | 不会，在 `~/.mentoraix/ov-server/data`（持久，重启不丢）|
| 怎么加新业务工具 | 按 ④ 写 MCP（不用改 Hermes 代码）|
