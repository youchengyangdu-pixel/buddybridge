# PROMPT.md — 派发任务书（bb-run 的唯一输入）

> `bb-run.ps1` 从本文件读取任务文本，通过 stdin 传给 CLI。
> **不要**把任务文本内联进命令行 —— 这是注入面，也是引号地狱的来源。

## 写法

1. 一句话说清目标
2. 产物要求（文件名、格式、验收标准）
3. 账本纪律：每完成一项，向 `PROGRESS.md` 追加一行 `<编号>|done|<产物绝对路径>||||`
   （第 5、6 列留空 —— sha256 由 `bb-run` 在收尾时统一计算并写入 `COMPLETION.json`，agent 不需要也不应该自己算）
4. 结束条件（全部 N 项 done）

## 示例

```
按 PLAN.md 执行 3 项任务。

每完成一项：
- 先产出文件（绝对路径见 PLAN.md）
- 再向 PROGRESS.md 追加一行：<编号>|done|<产物绝对路径>||||
  （第 4/5/6 列留空，由包装器统一计算校验值）

全部 3 项完成后停止。不要修改 PLAN.md 与 APPROVED.md。
```

## 为什么 hash 交给包装器

引擎B 默认档（`--disallowedTools Bash PowerShell`）**不授予 shell**，agent 无法运行 `sha256sum`/`Get-FileHash`。
如果要求它算 hash，它只能编一个数字 —— 那正好摧毁账本的可信度。
包装器在执行结束后遍历账本、对每个产物算真实 sha256，写入 `COMPLETION.json` 的 `verified` 数组。
