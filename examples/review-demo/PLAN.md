# PLAN：Mini 审查与收口 Demo（5 项）

- 计划版本：v1
- 创建日期：2026-09-25
- 目标产物目录：本文件所在目录
- 进度文件：本目录 PROGRESS.md
- 预计验收项总数：5 项

## 背景

BuddyBridge 实测用最小计划：5 项小任务，用于验证①降级方案交叉审查链路②阶段收口机制（每 5 项归档一次 STAGE）。任务本身无业务含义。

## 验收项清单

1. 创建 `config.json`，合法 JSON，含 `"name": "bb-demo"` 与 `"version": "1.0.0"` 两个键
2. 创建 `readme.txt`，内容一行：`mini demo readme`
3. 创建 `notes.md`，Markdown 格式，含一级标题 `# Notes` 与一行正文 `stage checkpoint test`
4. 创建 `checklist.txt`，三行：`a`、`b`、`c`（每行一个字母）
5. 创建 `summary.txt`，内容一行：`all five items done`

## 依赖顺序

顺序执行，无并行。

## 失败与回滚处置

某项失败：记 `编号|failed|原因` 跳过继续；产物均为新建文件，删除即回滚。

## 阶段收口约定（每完成 5 项执行一次）

第 5 项完成后执行一次阶段收口：① 把 5 项产物清单与各自 sha256 写入本目录 `STAGE-1.md` ② 在对话中输出状态自述（已完成 1-5 / 产物清单 / 本阶段结束）。

## 约束

- 只在本目录内创建文件
- 不使用任何高危命令

## 完成标志

5 个文件全部存在且内容符合各自验收标准；PROGRESS.md 5 行齐全零空号带校验值；STAGE-1.md 已生成；最后一轮把 cat 进度文件与 ls 输出贴进对话。
