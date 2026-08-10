# Agent 框架升级切换指南 (ClawCore → Hermes + OpenViking)

> **给开发者和 AI 助手**：怎么把服务从旧 agent (ClawCore) 切到新栈，以及怎么**把你负责的服务接进新 agent**。
> 状态：**ClawCore 已正式下线**，新栈（Hermes+OpenViking+Adapter）已上线并全面承接。

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
| Hermes（含 mcp SDK） | `agent-runtime-lab/hermes-agent/.venv` | `ls .venv/bin/hermes` |
| publish-service（业务后端） | :58888 | `curl -s :58888/api/health` |
| 密钥 | `~/.hermes/.env`、项目 `.env` | `API_SERVER_KEY`、`Gitee_API_KEY`、stepfun key |

> 深度背景见顶层 `AI-mentor-coProject/docs/Hermes-OpenViking-Migration-Plan.md`。

---

## ② 启动顺序

**一键**（推荐，按下表顺序起 + 健康检查 + 存 pid）：
```bash
bash agent-runtime-lab/hermes-clawcore-adapter/scripts/stack-up.sh
```
该脚本按依赖顺序拉起 **5 个后端**（含业务后端），已在跑自动跳过 + 自动健康检查。也可选择性启动：`ONLY=adapter,hermes` / `SKIP=mentor-recsys`。查状态：`bash .../scripts/stack-status.sh`。

| 序 | 服务 | 端口 | 约 | 健康检查 |
|---|---|---|---|---|
| 1 | OpenViking | 1933 | 5s | `curl :1933/health` → `{"healthy":true,"auth_mode":"trusted"}` |
| 2 | Hermes gateway | 8002 | 15s | `lsof -i:8002` 有进程 |
| 3 | adapter | 8003 | 5s | `curl :8003/health` → `{"ok":true,...}` |
| 4 | publish-service | 58888 | 5s | `curl :58888/api/health` |
| 5 | mentor-recsys | 8000 | 5s | `curl :8000/` |

停：`bash agent-runtime-lab/hermes-clawcore-adapter/stop.sh`（覆盖 5 服务端口）｜ 生产(鉴权)：`DEV_MODE=false JWT_SECRET=<密钥>`（stack-up.sh 已默认生产模式）

---

## ③ 配置（当前状态）

| 文件 | 值 | 说明 |
|---|---|---|
| `mentoraixs/.env.local` | `CLAWCORE_BASE_URL=http://localhost:8003` | 已切到 Adapter，**勿改回 :8001**（ClawCore 已下线） |
| `mentoraixs/.env.local` (生产) | 鉴权 | adapter 需 `JWT_SECRET`；`DEV_MODE=false`（stack-up.sh 已默认生产模式） |

改完重启 Mentoraixs。**ClawCore(:8001) 已下线，无回滚目标**；如需停新栈用 `agent-runtime-lab/.../stop.sh`。

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

## 回滚说明

**ClawCore(:8001) 已下线，无回滚目标。** 若新栈异常，可临时降级到直连供应商（OrbitAI/DeepSeek/Mock，改 mentoraixs `CLAWCORE_BASE_URL` 指向不可达地址即可触发降级链），但完整智能体能力会缺失。停新栈：`bash agent-runtime-lab/hermes-clawcore-adapter/stop.sh`。

---

## 上线后状态与待办
- **AGPL 法务** ✅（已过）：OpenViking 是 AGPL-3.0，当前 arm's length(HTTP API) 使用安全。
- **ClawCore 退役** ✅（已完成）：:8001 已下线，由新栈承接。
- **生产化** ⏸：systemd/launchd 守护（自启+崩重启）、性能基线（commit/recall P95）。**注意**：后台 nohup 进程在非持久终端会随会话结束被回收，上线应配守护进程。
- **M 人格注入** ⏸：见 [PERSONA-INJECTION.md](PERSONA-INJECTION.md)（待实施方案）。

## FAQ
| 问题 | 排查 |
|---|---|
| agent 说"没有这个工具" | `hermes mcp test <name>` 看连上没；Hermes venv 装了 `mcp` 库没 |
| 端口冲突 | 新栈用 :1933/:8002/:8003，业务后端 :58888/:8000，前端 :3000 |
| OV 数据会丢吗 | 不会，持久存储（重启不丢）|
| 怎么加新业务工具 | 按 ④ 写 MCP（不用改 Hermes 代码）|
| skill 调业务接口报 Connection refused | 对应后端没起——`bash .../stack-up.sh` 一键拉起全部后端 |
