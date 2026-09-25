# Quickstart Demo：5 分钟跑通引擎B 全链路

前提：已按 `install/windows.md` 或 `install/macos.md` 完成安装 + 登录 + 配置。

## 1. 复制本目录到一个临时工作目录

```powershell
Copy-Item -Recurse 'D:\path\to\buddybridge\examples\quickstart' C:\temp\bb-demo
cd C:\temp\bb-demo
```

（macOS：`cp -r .../examples/quickstart /tmp/bb-demo && cd /tmp/bb-demo`）

## 2. 跑派发命令（引擎B：goal + max）

```powershell
cd C:\temp\bb-demo
codebuddy -p -y --model kimi-k3-2 --fallback-model glm-5.3 --effort max --max-turns 40 '/goal 按 C:/temp/bb-demo/PLAN.md 逐条执行：先读 C:/temp/bb-demo/PROGRESS.md，某编号已有 done 记录且产物 sha256 前 8 位一致则跳过；每完成一项：先产出完整文件，再计算其字节数与 sha256 前 8 位，然后向进度文件追加一行「编号|done|产物路径|字节数|sha256前8位」；全部 3 项在进度文件均有 done 且产物存在时判定达成，最后一轮把 cat 进度文件与 ls 的输出贴进对话作为证据, or stop after 15 turns' > run.log 2>&1
```

（macOS 把路径换成 `/tmp/bb-demo/...`，其余一字不改）

## 3. 验收三件套

```powershell
Get-Content .\PROGRESS.md      # 3 行，编号 1-3 零空号，每行有字节数 + sha256 前 8 位
Get-Content .\task1.txt        # item-1-done
Get-FileHash .\task1.txt -Algorithm SHA256   # 前 8 位与 PROGRESS 第 1 行一致（task2/3 同理抽查）
Get-Content .\run.log -Tail 5  # 找 Goal achieved
```

孤儿进程检查见 install 卡常见坑表。

## 4. 重派测试（验证幂等保护）

原样再跑一遍第 2 步的命令 —— agent 应判定「已达成，无需执行」，PROGRESS.md **不会**新增重复行。这就是断点续跑/防重复执行的机制。

## 你刚跑通了什么

- 无状态桥接：PLAN/PROGRESS 是两个 AI 之间唯一的契约
- 进度自曝：账本带校验值，验收靠重算不靠信任
- 幂等保护：重派不重复干活
- 人工门控的反面演示：这个 demo 故意**没有** REVIEW/APPROVED 环节（因为它是零风险的玩具任务）—— 真实任务必须先走审查链路，见仓库根 README 的四段流水线
