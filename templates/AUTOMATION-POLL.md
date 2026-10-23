# Automation 轮询模板（跨会话自动回传）

> 用法：把下面的正文作为 WorkBuddy automation 的 prompt（周期性，建议 10-15 分钟一次）。
> prompt 必须自包含 —— 未来执行时看不到当前对话。

## 模板正文（复制到 automation 的 prompt）

```
检查 BuddyBridge 派发任务的完成情况，有新结果才告诉我。

监控目录：<WORKDIR>

步骤：
1. 列出 <WORKDIR>\.buddybridge\runs\ 下的子目录，取名字最大的那个（时间戳命名）。
2. 读其中的 COMPLETION.json：
   - 不存在 → 读 <WORKDIR>\PROGRESS.md 的修改时间；距今超过 30 分钟才报告「疑似卡住，进度静默 X 分钟」，否则只回一行「仍在运行」。
   - 存在 → 提取 run_id / status / exit_code / duration_sec / ledger / log_tail。
3. 去重：读 <WORKDIR>\.buddybridge\notified.log（不存在就当空）。如果里面已有该 run_id，只回一行「已汇报过」。
   没有则把该 run_id 追加进去，然后报告。
4. 报告格式（三行以内）：
   状态：DONE / FAILED / TIMEOUT / INCOMPLETE
   数字：exit=… done=…/N 用时=…s
   下一步：建议动作（验收 / 看 log_tail / 缩短范围重派）
```

## 状态对照（与 bb-run 一致）

| COMPLETION.status | exit_code | 含义 |
|---|---|---|
| EXITED | 0 | 正常结束（再看 ledger.done 是否等于 N） |
| EXITED | ≠0 | CLI 报错退出，看 log_tail |
| TIMEOUT | 124 | 被硬超时杀掉，任务太长或卡死 |
| ERROR | 1 | 包装器自身异常（看 log_tail 的 stderr 段） |

**另外三个字段要一起看**：
- `claim_rolled_back=true` → 这次派发没真正干活，批准已退回 `approved`，可以直接重派
- `ledger.hash_mismatch>0` → 账本里声明的 hash 与实际不符（要么产物被改，要么 agent 编了值）
- `ledger.gaps>0` → 编号有空号（有验收项根本没跑）；`gaps_skipped=true` 表示编号是日期式，需人工确认

## 为什么不用 hooks

实测（2026-10-23）：`-p` 模式下 Stop / PostToolUse hook 均不触发，且 Git Bash 不在 PATH。所以回传只依赖文件轮询，不依赖任何 hook。

## 与旧版差异

- 不依赖 `LATEST.json`（已删除）—— 直接扫 `runs\` 目录取最新
- 去重靠 `notified.log`（automation 自己写），不依赖没人写的 `NOTIFIED.json`
