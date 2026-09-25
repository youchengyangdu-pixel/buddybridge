# macOS 安装卡（CodeBuddy CLI + BuddyBridge 配置，含沙箱硬边界）

> 全程约 5 分钟。Mac 的额外福利：Bash 沙箱（仅 macOS/Linux 可用）+ 关掉逃生舱 = 真·硬边界。

## 0. 前置自检（30 秒）

```bash
node -v        # < 18.20 请先升级（brew install node 或 nvm）
which npm
```

## 1. 安装 CLI

```bash
npm install -g @tencent-ai/codebuddy-code
codebuddy --version
# 引擎B ≥ 2.99.0；引擎A（ultracode/Dynamic Workflows）≥ 2.105.0，建议最新
# 版本不够：codebuddy update
```

## 2. 登录（一次性）

```bash
codebuddy    # 交互界面 /login，Ctrl+D 按两次退出
```

## 3. 配置（放权 + 沙箱硬边界）

把 [`settings.macos.json`](settings.macos.json) 的内容合并进 `~/.codebuddy/settings.json`。四个要点：

- `defaultMode: "auto"`：只管手动 TUI 会话；派发命令带 `-y`（压过 defaultMode），挂机不靠它。
- `deny` 数组：挂机唯一可靠护栏（优先级永远最高）。按需裁剪。
- `allow` 白名单：给引擎A 子代理用；调研任务 `WebSearch` + `WebFetch` 双开。
- `sandbox` 三件套：
  - `enabled: true` —— 官方文档对默认值自相矛盾（一处 true 一处 false），**显式写，别赌默认**
  - `allowUnsandboxedCommands: false` —— **硬边界的关键**。官方默认允许「沙箱内失败的命令挪到沙箱外重试」，不关它，被注入的 agent 能自己走出笼子；关了它，越界命令会失败而不是逃跑
  - `autoAllowBashIfSandboxed: true` —— 其自动批准机制以 acceptEdits 模式为前提；`-y` 挂机下沙箱的真实收益是文件系统/网络隔离本身

**双配置目录检查**：从桌面端 AI 会话内派发时，先跑 `codebuddy -p '输出环境变量 CODEBUDDY_CONFIG_DIR 的值'`，非空则配置写到该目录。

## 4. 验证（goal 冒烟）

```bash
mkdir -p /tmp/bb-test && cd /tmp/bb-test
codebuddy -p -y '/goal 创建 done.txt 内容为 ok，把文件内容贴进对话作为证据则达成, or stop after 5 turns'
cat done.txt    # 输出 ok = 引擎B 链路通
```

## 5. 引擎A 自检（要用 ultracode 才做）

```bash
cd /tmp/bb-test
codebuddy -p -y --model kimi-k3-2 --effort ultracode --max-turns 20 'ultracode 列出当前目录文件名并把清单写入 files.txt'
cat files.txt   # 有产出 = ultracode headless 可用；无产出 → 降级方案（docs/ultracode.md）
```

## Mac 与 Windows 差异速查

| 项 | macOS | Windows |
|---|---|---|
| Bash 沙箱 | ✅ 可开（+ 关逃生舱 = 硬边界） | ❌（改用 --sandbox container / --worktree） |
| goal 文本引号 | zsh 单引号（同 PowerShell） | PowerShell 单引号 |
| 路径 | `/Users/<你>/...` | `C:/Users/<你>/...` |
| 孤儿进程清理 | `ps aux \| grep codebuddy` + `kill <pid>` | `Get-CimInstance` + `taskkill /PID <pid> /F` |

## 常见坑

| 症状 | 原因与处置 |
|---|---|
| headless 一轮放弃 | 忘了 `-y` |
| Authentication required | 交互模式 `/login` 一次 |
| 挂机中途卡住 | HIGH/CRITICAL 被拒 → 读 run.log，改 PLAN 绕开 |
| 沙箱「没生效」 | 检查是否写错配置目录（双目录坑）+ enabled 是否显式 true |
| 沙箱内命令失败 | 正常 —— 要么放宽 sandbox 配置，要么接受安全失败（这正是沙箱的意义） |
| ultracode 无产物 | 版本/模型/开关三查 → 降级方案兜底 |
