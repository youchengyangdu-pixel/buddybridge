# macOS 安装卡（BuddyBridge v1.1 完整流程）

> 与 Windows 同一套：门控（`APPROVED.md`）→ `bb-run.sh` 派发 → 硬超时 → `COMPLETION.json` 验收。
> 全程约 10 分钟。Mac 的额外福利：Bash 沙箱（需要 shell 的任务才有用；默认档无 shell，用不上）。

## 0. 前置自检（30 秒）

```bash
node -v          # 建议 >= 22（< 18.20 请先升级：brew install node）
npm -v
command -v git
command -v shasum   # macOS 自带；没有则 brew install perl
```

## 1. 安装 CLI

```bash
npm install -g @tencent-ai/codebuddy-code
codebuddy --version
# 引擎B >= 2.99.0；引擎A（ultracode）>= 2.105.0，建议最新
```

## 2. 登录（一次性）

```bash
codebuddy        # 交互界面输入 /login，完成后 Ctrl+D 退出
```

## 3. 克隆仓库 + 安装 skill

```bash
git clone https://github.com/youchengyangdu-pixel/buddybridge.git
cd buddybridge

# 按你用的是 WorkBuddy 还是纯 CLI 选其一（也可以两个都装）
mkdir -p ~/.workbuddy/skills/buddybridge
cp skill/buddybridge/SKILL.md ~/.workbuddy/skills/buddybridge/
echo "$PWD" > ~/.workbuddy/skills/buddybridge/REPO.txt

mkdir -p ~/.codebuddy/skills/buddybridge
cp skill/buddybridge/SKILL.md ~/.codebuddy/skills/buddybridge/
echo "$PWD" > ~/.codebuddy/skills/buddybridge/REPO.txt

chmod +x scripts/bb-run.sh scripts/bb-verify.sh
```

## 4. 权限配置（bb-run 自动管理，不用手动合并）

`bb-run.sh` 每次派发前，会把 [`settings.macos.json`](settings.macos.json) 部署到**独立配置目录** `~/.buddybridge/home/settings.json`。你不用手动往 `~/.codebuddy` 合并。

**默认档三层护栏**：
1. `--disallowedTools Bash`（整工具禁用；Mac 没有 PowerShell 工具，所以只禁 Bash 即可）
2. `deny` 数组（`Edit(**/APPROVED.md)` 等，防止执行 agent 自签批准）
3. 门控：`dispatch_sha256` 同时绑定 `PLAN.md` 与 `PROMPT.md`，`status` 在派发瞬间变 `used`

`sandbox` 段是给「需要 shell 的任务」用的硬边界（`enabled: true` + `allowUnsandboxedCommands: false`，关掉逃生舱）。默认无 shell 时用不到，保持默认即可。

## 5. 验证（5 个 case，全真跑，约 3 分钟）

```bash
bash scripts/bb-verify.sh
```

期望输出：

```
case1 exit=10 (expect 10)
case2 exit=0 completion=1 product=1 used=1 (expect 0/1/1/1)
case3 exit=124 (expect 124)
case4 shell-dir=0 no-shell-note=1 (expect shell-dir=0)
case5 still_used=1 flipped=0 (expect still_used=1 flipped=0)
```

- case5 是威胁模型试金石：agent 试图把 `status: used` 改回 `approved`，必须失败
- 任一不符就先别往下用

## 6. 日常派发

```bash
# 1) 在项目目录写 PLAN.md（验收项可验证）
# 2) 写 PROMPT.md（任务书，模板见 templates/PROMPT.md）
# 3) 人填 APPROVED.md（模板 templates/APPROVED.md）：
p=$(shasum -a 256 PLAN.md  | awk '{print $1}')
q=$(shasum -a 256 PROMPT.md | awk '{print $1}')
printf '%s:%s' "$p" "$q" | shasum -a 256 | awk '{print $1}' | cut -c1-12
#   把输出抄进 dispatch_sha256；token 用 `openssl rand -hex 8`；status 保持 approved

# 4) 派发
bash /path/to/buddybridge/scripts/bb-run.sh \
  --workdir "/path/to/project" --effort max --max-turns 200 --timeout 7200

# 5) 看结果
cat /path/to/project/.buddybridge/runs/*/COMPLETION.json
```

跨会话收通知：用 `templates/AUTOMATION-POLL.md` 配一个周期性 automation。

## 7. Mac 与 Windows 差异速查

| 项 | macOS | Windows |
|---|---|---|
| 派发脚本 | `scripts/bb-run.sh`（bash） | `scripts\bb-run.ps1`（PowerShell） |
| 验证脚本 | `scripts/bb-verify.sh` | `scripts\bb-verify.ps1` |
| 默认无 shell | `--disallowedTools Bash` | `--disallowedTools Bash PowerShell`（**两个独立参数**） |
| 硬超时 | watchdog 子进程 `sleep` + `kill`，退出码归一化为 124 | `taskkill /T /F`，退出码 124 |
| 指纹命令 | `shasum -a 256` | `Get-FileHash -Algorithm SHA256` |
| Bash 沙箱 | ✅ 可开（关逃生舱 = 硬边界） | ❌ 不支持 |
| 配置文件 | `install/settings.macos.json` | `install/settings.windows.json` |

## 8. 常见坑

| 症状 | 原因与处置 |
|---|---|
| `codebuddy: command not found` | npm 全局 bin 不在 PATH：`npm config get prefix`，把 `<prefix>/bin` 加进 PATH |
| `package entry bin/codebuddy not found` | CLI 装在非标准位置；`command -v codebuddy` 看真实路径 |
| `Authentication required` | 交互模式 `/login` 一次 |
| `Permission denied` 跑脚本 | `chmod +x scripts/bb-run.sh`，或用 `bash scripts/bb-run.sh` |
| 指纹不一致 | 文件被改过；用第 6 节的三行命令重算（**必须和派发时同一份文件**） |
| `status: used` 后无法再派 | 正常，一次性凭证；改回 `approved` 前请确认这是你本人的决定 |
| 派发没有 `-y` 导致一轮放弃 | `bb-run.sh` 已内置 `-y`，手拼命令才容易漏 |
| 沙箱「没生效」 | 检查 `CODEBUDDY_CONFIG_DIR` 指向哪个目录（bb-run 用 `~/.buddybridge/home`） |
