# Windows 安装卡（CodeBuddy CLI + BuddyBridge 配置）

> 全程约 5 分钟。Fill in your own language — templates are language-agnostic.

## 0. 前置自检（30 秒，别跳过）

```powershell
node -v                       # < 18.20 请先升级 Node
npm config get prefix         # 记下路径；装完若提示「codebuddy 不是内部或外部命令」→ 把它加进 PATH 或重开终端
```

公司机器/无管理员权限下 `npm install -g` 报 EPERM → 用 nvm-windows 或 `npm config set prefix` 指到用户目录。

## 1. 安装 CLI

```powershell
npm install -g @tencent-ai/codebuddy-code
codebuddy --version
# 引擎B（goal）≥ 2.99.0；引擎A（Dynamic Workflows/ultracode）≥ 2.105.0，建议最新
# 版本不够：codebuddy update
```

## 2. 登录（一次性）

```powershell
codebuddy
```

进交互界面后 `/login`，浏览器授权，`Ctrl+D`（按两次）退出。headless 依赖这份登录态。

## 3. 权限配置（v1.1 起由 `bb-run` 自动管理）

`bb-run` 每次派发前，会把 [`settings.windows.json`](settings.windows.json) 部署到**独立配置目录** `~/.buddybridge/home/settings.json`。你不用手动往 `~/.codebuddy` 合并 —— 那条老路径只管你自己开 TUI 的日常会话。

**默认档的三层护栏（全部实测过）**：

1. **`--disallowedTools Bash PowerShell`** —— 注意是**两个独立参数**。写成 `"Bash,PowerShell"` 会被当成一个不存在的工具名，等于没禁（实测：agent 照样跑 shell 成功）
2. **deny 双写** —— 只写 `Bash(echo:*)` 拦不住 PowerShell 工具（实测：Bash 被拒后 agent 改用 PowerShell 执行成功）
3. **门控** —— `dispatch_sha256` 同时绑定 `PLAN.md` 与 `PROMPT.md`（换任务书也拒）；`status` 在派发瞬间变 `used`，不能重放

`allow` 白名单只服务**引擎A 的 Workflow 子代理**（固定 acceptEdits、走权限链）。调研类任务要 `WebSearch` + `WebFetch` 双开。

## 4. 验证（4 个 case，全真跑，约 2 分钟）

```powershell
powershell -ExecutionPolicy Bypass -File "<仓库>\scripts\bb-verify.ps1"
```

期望输出：

```
case1 no-approval   : exit=10
case2 approved      : exit=0  completion=True  product=True  used=True
case3 timeout       : exit=124
case4 shell guard   : shell-dir=False  no-shell-note=True
```

任一项不符就别往下用 —— 说明门控或护栏没生效。

## 5. 日常派发（v1.1 流程）

1. 写 `PLAN.md`（验收项要可验证）
2. 写 `PROMPT.md`（任务书，模板 `templates/PROMPT.md`；**永远不要把任务文本贴进命令行**）
3. 人填 `APPROVED.md`（指纹同时覆盖 PLAN 与 PROMPT）：
   ```powershell
   $p = (Get-FileHash .\PLAN.md  -Algorithm SHA256).Hash.ToLower()
   $q = (Get-FileHash .\PROMPT.md -Algorithm SHA256).Hash.ToLower()
   $h = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($p + ':' + $q))
   (-join ($h | ForEach-Object { $_.ToString('x2') })).Substring(0,12)

   -join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
   ```
   两个结果抄进模板（`dispatch_sha256` 与 `token`），`status` 保持 `approved`
4. 派发：
   ```powershell
   powershell -ExecutionPolicy Bypass -File "<仓库>\scripts\bb-run.ps1" -WorkDir "<项目绝对路径>" -Effort max -MaxTurns 200 -TimeoutSec 7200
   ```
5. 看结果：`.buddybridge\runs\<时间戳>\COMPLETION.json`（status / exit_code / ledger / verified / log_tail）

跨会话收通知：用 `templates/AUTOMATION-POLL.md` 配一个周期性 automation。

## 6. 旧流程（引擎A 自检 / 手贴命令）

```powershell
mkdir C:\temp\bb-test; cd C:\temp\bb-test
codebuddy -p -y '/goal 创建 done.txt 内容为 ok，把文件内容贴进对话作为证据则达成, or stop after 5 turns'
cat .\done.txt    # 输出 ok = 引擎B 全链路通。失败 99% 是漏了 -y
```

## 7. 引擎A 自检（要用 ultracode 才做）

```powershell
cd C:\temp\bb-test
codebuddy -p -y --model kimi-k3-2 --effort high --max-turns 20 'ultracode 列出当前目录文件名并把清单写入 files.txt'
cat .\files.txt   # 有产出 = ultracode headless 在你的版本可用；无产出 → 用降级方案（多 -p 分维度），见 docs/ultracode.md
```

交互态跑一次 `/effort` 确认菜单里有 ultracode 档（没有 = 当前模型不支持 xhigh，换 `--model` 显式路由）。

## 常见坑

| 症状 | 原因与处置 |
|---|---|
| headless 一轮就放弃 / 写文件被拒 | 忘了 `-y` |
| Authentication required | 未登录：交互模式 `/login` 一次 |
| 挂机跑一半不动了 | 可能命中 HIGH/CRITICAL 被拒 → 读 run.log 尾部确认，改 PLAN 绕开高危命令 |
| 改了 settings.json 不生效 | 不热加载：重启进程或开新会话；/permissions 面板内改即时生效 |
| 放权完全失效 | 查是否有 `disableBypassPermissionsMode: "disable"`（四层任一即生效） |
| ultracode 派发无产物 | 版本 < 2.105.0 / 模型不支持 xhigh / disableWorkflows 已开 / 官方研究预览特性在你版本行为不同 → 全部有降级方案 |
| 进程残留继续烧额度 | `Get-CimInstance Win32_Process -Filter "Name='node.exe'"` 查 codebuddy 残留 → `taskkill /PID <pid> /F` |

## 想要更强隔离？

Windows 没有 Bash 沙箱，但有跨平台选项：`--sandbox container`（Docker/Podman，Beta）或 `--worktree`（git 工作树隔离）。见 docs/mac-sandbox.md 的隔离选项矩阵。
