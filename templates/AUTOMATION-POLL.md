# Automation 轮询模板（跨会话自动回传）

> 用法：把本文件内容作为 WorkBuddy automation 的 prompt（一次性或周期性任务）。
> 关键：prompt 必须自包含 —— 未来执行时看不到当前对话。

## 模板正文（复制到 automation 的 prompt）

```
检查 BuddyBridge 派发任务的完成情况，并把结果告诉我。

监控目录：<WORKDIR>
预期验收项数：<N>

按以下顺序判断：
1. 读 <WORKDIR>/.buddybridge/LATEST.json，取 run_dir 与 run_id。
2. 如果 run_dir/COMPLETION.json 不存在：
   - 读 <WORKDIR>/PROGRESS.md 的修改时间，若距今超过 30 分钟，报告「STALLED，进度已静默 X 分钟」并附 PROGRESS 最后 5 行；
   - 否则不要打扰我，回复一行「仍在运行」即可。
3. 如果 COMPLETION.json 存在：
   - exit_code != 0 → 报告「FAILED，exit=X」，附 COMPLETION 的 log_tail 最后 10 行；
   - exit_code == 0 但 ledger.done < N → 报告「INCOMPLETE，完成 X/N」，列出缺的编号；
   - exit_code == 0 且 done >= N → 报告「DONE」，附 ledger 统计与产物目录；
   - 若 run_dir/NOTIFIED.json 已存在且状态未变，不要重复通知，只回复「无变化」。

报告写成三行以内：状态 / 关键数字 / 下一步建议。
```

## 落地要点

1. **幂等**：automation 每次执行会写 `run_dir/NOTIFIED.json`（记录上次通知的状态与时间），状态没变就不重复打扰。
2. **不依赖 hooks**：只读文件，所以 Git Bash 不可用也能工作（探针实测 bash 不在 PATH）。
3. **周期建议**：长任务 10-15 分钟一次；短任务改用会话内 `bb-watch.ps1`（更实时）。
4. **与桌面端会话解耦**：automation 独立运行，即使当前对话关了也能报。
