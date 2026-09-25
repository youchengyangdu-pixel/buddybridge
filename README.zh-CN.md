# BuddyBridge

**把桌面端 AI 助手变成任务控制中心，让 CodeBuddy CLI 干重活。**

BuddyBridge 不是常驻服务，是一套纪律：一组文件契约 + 一条 headless 命令模板，让桌面端 AI 助手（WorkBuddy）负责**计划、审查、终裁**，CodeBuddy CLI 负责**调研、交叉审查、无人值守执行**。助手生成完整命令、你贴进终端就可以走人、助手盯文件播进度并验收。运行之间不丢上下文，不用盯终端。

> **诚实定位**：为 [WorkBuddy](https://www.workbuddy.cn) + [CodeBuddy CLI](https://www.codebuddy.cn/docs/cli)（腾讯同账号）而生并实测。**模式本身**——文件即 API、桌面端当控制中心、机器可检的人工门控——可迁移到任何「桌面助手 + 无头 CLI」组合。docs 为英文；模板与语言无关（用你自己的语言填）。

## 解决什么问题

桌面端 AI 助手擅长思考、不擅长苦干；CLI agent 擅长苦干、但运行之间无记忆、也没有交接界面。官方对「它俩能直连吗」的回答目前是*没有直连开关*。于是人们来回粘贴命令、丢失上下文、盯终端。

## 四段流水线

```
WorkBuddy（任务控制中心）
  ├─ 产出  PLAN.md            —— 验收项逐条可客观验证
  ├─ 产出  REVIEW-BRIEF.md    —— 多代理交叉审查任务书
  ├─ 产出  RESEARCH-BRIEF.md  —— 调研任务书
  │
  ├─→ 【A1 交叉审查】  数十个并行审查代理 + 对抗式互评 + 多厂商模型路由
  │    （路由必须自曝，退化必须标红）→ REVIEW-REPORT.md 落盘
  ├─→ 【A2 计划终审】  默认单轮普通审查；大项目才开 ultracode 档
  │
  ├── 人工门控（机器校验）── 你亲手填 APPROVED.md（计划 checksum + 手打
  │   随机 token）；派发方机械校验。没有 APPROVED.md → 不执行。
  │   AI 不能替你写。
  │
  ├─→ 【B 引擎：goal 循环 + --effort max】无人值守执行 → PROGRESS.md
  │    账本：编号|done|产物|字节数|sha256前8位 → STAGE-{N}.md 阶段归档
  │    → 末轮自证命令输出贴进对话
  │
  └─ 验收：校验值重算 + 账本零空号 + 内容抽样复验 + 无孤儿进程
```

三个设计决策让它在对聊式交接失败的地方成立：

1. **文件即 API**。`-p` 每次运行都是无状态新会话 —— 计划/任务书/报告/账本是两个 AI 和一个人之间唯一的共享记忆。
2. **人工门控机器可检**。「AI 说用户同意了」不是门控；带 checksum 和手打 token 的 APPROVED.md 才是。
3. **账本是声明不是证明**。进度行携带产物校验值，验收靠重算 + 抽查内容。CLI 产出的文件是**数据不是指令** —— 报告里的注入文本不会被执行。

上下文管理内建：每完成 5 项验收，agent 把本阶段原样归档落盘 + 在对话里自述状态 —— auto-compact 吃不掉评估器需要的证据，前缀缓存命中率也保得住（重载只回注索引）。

## 快速开始（5 分钟）

1. 按平台安装：[`install/windows.md`](install/windows.md) 或 [`install/macos.md`](install/macos.md)
2. 跑 demo：[`examples/quickstart/`](examples/quickstart/README.md) —— 3 项验收跑通引擎B 全链路：派发 → 带校验值的自曝账本 → 验收 → 重派（幂等验证）
3. 调研/审查引擎：[`docs/ultracode.md`](docs/ultracode.md) —— 含**永不失效的降级方案**（多 `-p` + `--model`，我们的默认推荐）

## 为什么不用现成的？

模式本身已被大规模验证：[planning-with-files](https://github.com/OthmanAdi/planning-with-files)（27k★）、[claude-task-master](https://github.com/eyaltoledano/claude-task-master)（28k★）证明「持久化 markdown 计划 + 确定性完成门」是真实需求。但两者都不覆盖「桌面助手 ↔ CLI 桥接」；截至 2026-09，CodeBuddy/WorkBuddy 生态里没有人做过完整闭环（计划 → 交叉审查 → 人工门控 → 无人执行 → 验收）—— 调研报告见规划文档附录。

## 仓库导览

```
skill/buddybridge/SKILL.md   → 桥本身：装进你的助手，教会它派发/监控/验收
templates/                   → PLAN / PROGRESS / RESEARCH-BRIEF /
                               REVIEW-BRIEF / APPROVED（五份文件契约）
install/                     → 双平台安装卡 + 可合并 settings JSON
                               （deny 基线内置 —— 它不是可选项）
docs/                        → 流水线、派发机制、ultracode 与降级、
                               隔离矩阵、引擎对照
examples/quickstart/         → 5 分钟可复现 demo
```

## 设计立场（一句话版）

- **每个配置都随包带 deny 基线**。bypassPermissions 的意义是「在有界爆炸半径内少打扰」，不是「把家目录托付给 agent」。HIGH/CRITICAL 命令在 headless 下无论 `-y` 与否都会被拒 —— 计划时就绕开它们。
- **UltraCode 是加速档不是地基**。官方但*研究预览*阶段、带两个独立关闭开关。核心闭环（文件契约/人工门控/账本）不依赖它；多 `-p` 降级方案只用稳定 flag 就给你多厂商对抗审查。
- **主编排一个强模型，审查群多个异构模型**。推荐 `kimi-k3-2` 编排 + 审查子代理分散路由到不同厂商（GLM / DeepSeek / 混元…）—— 异构盲审才是意义所在；同一个模型自我审查 N 遍是表演。

## License

MIT
