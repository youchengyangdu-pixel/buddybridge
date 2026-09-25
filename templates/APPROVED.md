# APPROVED

> 填写说明：本文件是**人工终裁的拍板凭证**，是引擎B（执行）派发的唯一放行条件。
> **必须由人填写或人在桌面端 AI 面前逐字口述、由人确认后落盘 —— AI 不得代写、不得代填、不得提示措辞。**
> 派发前桌面端 AI 必须机械校验：① 本文件存在 ② 计划校验值与 PLAN.md 当前内容实际计算的 sha256 一致 ③ 拍板人声明包含本轮生成的随机 token。任一不满足 → 拒绝派发。

- 被审计划：〈PLAN.md 绝对路径〉
- 计划版本：v〈N〉
- 计划校验：〈sha256 前 12 位 —— PowerShell: `(Get-FileHash '<PLAN.md>' -Algorithm SHA256).Hash.Substring(0,12).ToLower()`；macOS/Linux: `shasum -a 256 '<PLAN.md>' | cut -c1-12`〉
- 审查报告：〈REVIEW-REPORT.md 绝对路径〉
- 拍板时间：〈ISO8601，例 2026-09-25T18:30:00+08:00〉
- 拍板人声明：〈用户手打一句话，必须原样包含桌面端本轮给出的随机 token：〈TOKEN〉〉
