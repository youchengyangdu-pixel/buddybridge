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

## 3. 权限配置（注意：`-y` 会压过 defaultMode）

把 [`settings.windows.json`](settings.windows.json) 的内容合并进 `C:\Users\<你>\.codebuddy\settings.json`（没有就新建）。三块东西各司其职：

- `defaultMode: "auto"`：**只影响你手动开 TUI 的日常会话**。派发出去的命令一律带 `-y`（等价 `--permission-mode bypassPermissions`），优先级高于 defaultMode —— auto 对挂机运行不生效。
- `deny` 数组：**挂机唯一可靠的护栏**（deny 永远优先，bypass 之下依然生效）。按需裁剪：任务确需 `git push` 就删那一行，但 `rm -rf` / `sudo` / `.env` / `~/.ssh` 建议永久保留。
- `allow` 白名单：主要服务**引擎A 的 Workflow 子代理**（它们固定跑 acceptEdits、走权限链）。调研类任务必须 `WebSearch` **和** `WebFetch` 双开，缺 WebFetch 则引用验证全挂。

**双配置目录检查**：如果你会从桌面端 AI 会话内派发，先跑 `codebuddy -p '输出环境变量 CODEBUDDY_CONFIG_DIR 的值'` —— 非空则配置要写到**该目录**的 settings.json，不是 ~/.codebuddy/。

## 4. 验证（goal 冒烟，比写文件测试更有说服力）

```powershell
mkdir C:\temp\bb-test; cd C:\temp\bb-test
codebuddy -p -y '/goal 创建 done.txt 内容为 ok，把文件内容贴进对话作为证据则达成, or stop after 5 turns'
cat .\done.txt    # 输出 ok = 引擎B 全链路通。失败 99% 是漏了 -y
```

## 5. 引擎A 自检（要用 ultracode 才做）

```powershell
cd C:\temp\bb-test
codebuddy -p -y --model kimi-k3-2 --effort ultracode --max-turns 20 'ultracode 列出当前目录文件名并把清单写入 files.txt'
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
