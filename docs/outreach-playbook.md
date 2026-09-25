# BuddyBridge 官方触达操作手册（三渠道小白版）

> 目标：把项目 + 宿主注入 bug 报告送到腾讯 WorkBuddy/CodeBuddy 官方团队眼前，争取官方关注与认可。
> 时机：审查链路实测跑完 + 私有期打磨后，公开仓库时执行。
> 原则：**bug 报告是敲门砖**（官方工程师最重视），项目介绍是顺势带出的。

---

## 渠道一：WorkBuddy 腾讯频道（官方社区，最直接）

### 是什么
腾讯官方建的社区频道（类似 QQ 频道/Discord），里面有产品专家和官方运营，用户发帖提问、展示作品，他们会回复。

### 操作步骤（10 分钟）

1. **拿到入口二维码**：
   - 浏览器打开 https://www.codebuddy.cn/docs/enterprise/215235149746380800 （官方「联系我们」页）
   - 页面往下翻，找到「**WorkBuddy 腾讯频道**」，有个二维码
2. **加入频道**：
   - 手机 QQ 扫这个码 → 点「加入频道」（如果提示审核，等通过即可，一般很快）
   - 电脑上也可以：QQ 左侧「频道」入口，加入后在电脑上操作更方便发长文
3. **发帖**（找「作品展示」或「经验分享」类板块；没有就找「综合讨论」）：
   - 标题：`【作品分享】BuddyBridge：让 WorkBuddy 当指挥官、CodeBuddy CLI 干重活的开源工作流`
   - 正文直接粘贴下面「发帖模板」
   - 如果频道支持附件，把仓库 README 截图（四段流水线那张）一起传
4. **发完后的动作**：
   - 24 小时内有人回复就跟帖；有产品专家回复时，礼貌补一句「宿主注入的 bug 我在 CLI 内反馈也提了工单，附完整复现步骤，希望对团队有帮助」

### 发帖模板（直接复制）

```
【这是什么】
BuddyBridge —— 一套让 WorkBuddy（桌面端）和 CodeBuddy CLI（终端）协同工作的开源方法：
桌面端负责计划、审查、终裁；CLI 负责无人值守执行、调研、多代理交叉审查。

【解决什么痛点】
官方文档里两个产品是割裂的（无直连开关），高强度用户只能人肉复制粘贴命令来回倒。
BuddyBridge 用「文件契约」把它们打通：PLAN/PROGRESS/REVIEW-BRIEF/APPROVED 四份文件 + 一条命令模板。

【实测踩坑分享】（对官方可能有价值）
1. Windows 宿主会话内直接拉起 CLI 会继承 CODEBUDDY_MCP_CONFIG 等环境变量，
   CLI 以宿主子进程形态启动、连上宿主整个 MCP 集群，实测 prompt 滚到 138k token、11 分钟零产出
2. CLI 没有 --cwd 参数（--help 也没有，实测 unknown option）
3. ultracode 档在简单任务上会自动跳过 workflow 编排（行为发现）
这些都有完整复现步骤，欢迎官方同学交流。

【仓库】
GitHub：https://github.com/youchengyangdu-pixel/buddybridge（公开后链接生效）
MIT 协议，装好就能用，5 分钟 Quick Start。
```

---

## 渠道二：官方邮箱（bug 报告主战场）

### 是什么
`codebuddy@tencent.com` 是 CodeBuddy 官方技术支持邮箱（官方「联系我们」页明示）。WorkBuddy 的是 `workbuddy@tencent.com`。我们的宿主注入问题横跨两端，**主发 codebuddy@，抄送 workbuddy@**。

### 操作步骤（15 分钟）

1. 用你常用邮箱（QQ 邮箱/Gmail 都行）写新邮件
2. 收件人：`codebuddy@tencent.com`
3. 抄送（CC）：`workbuddy@tencent.com`
4. 标题：`【用户实测报告】Windows 宿主会话内拉起 CLI 的环境变量继承问题 + BuddyBridge 开源项目分享`
5. 正文直接粘贴下面「邮件模板」
6. 发送

### 邮件模板（直接复制）

```
CodeBuddy 团队你们好，

我是 WorkBuddy + CodeBuddy CLI 的重度用户，最近围绕「桌面端↔CLI 协同」做了一套开源工作流
（BuddyBridge），过程中实测到几个可能对团队有价值的问题，一并发上：

【问题 1：宿主会话内拉起 CLI 的环境变量继承（主要问题）】
环境：Windows 11 + WorkBuddy 桌面端 + CodeBuddy CLI v2.158.0
复现步骤：
1. 在 WorkBuddy 会话里让 AI 用 Bash 工具直接启动 codebuddy -p -y "..."
2. 观察子进程环境变量：CODEBUDDY_CONFIG_DIR 指向 .workbuddy 目录、
   CODEBUDDY_MCP_CONFIG 携带宿主全部 MCP 服务器配置
3. 表现：CLI 以「宿主子进程」形态运行，连接宿主 MCP 集群，
   单轮 prompt 达到 138,075 token，11 分钟零产出（会话正常流式响应但任务不推进）
4. 尝试清除变量后：CLI 转为独立形态，但插件/marketplace 初始化失败
   （SAFE_DELETE_BULK_GUARD helper-unavailable，exit 1）
5. 用户自己开的独立终端无这些变量，一切正常

期望：希望官方能提供一个「干净派发」开关或文档说明推荐的会话内派发姿势。

【问题 2：--cwd 参数不存在】
cli-reference 若有计划支持请考虑；当前用 cd 前置可绕过。

【问题 3：ultracode 行为观察】
--effort ultracode 在 headless 下被正常接受（--help 未列出但运行时合法），
且简单任务会自动跳过 workflow 编排直接执行 —— 行为合理，建议文档补充说明。

【项目分享】
BuddyBridge（MIT 开源）：四段流水线（交叉审查→终审→人工门控→goal 执行）、
文件契约（带校验值的进度账本）、双引擎（ultracode 调研/审查 + goal 挂机执行）、
多厂商模型路由盲审。GitHub：https://github.com/youchengyangdu-pixel/buddybridge

希望对团队有帮助，也期待官方的反馈。

（你的署名）
```

---

## 渠道三：CLI / IDE 内反馈（进官方工单系统）

### 是什么
CodeBuddy/WorkBuddy 内置的「帮助与反馈」入口，提交后直接进产品团队的工单/反馈池，比邮件更结构化，还能勾选自动上传运行日志（官方最爱，省得他们复现）。

### 操作步骤（5 分钟）

1. **打开反馈入口**：
   - CodeBuddy CLI/IDE：右上角**头像图标** → 点「**帮助与反馈**」
   - （WorkBuddy 桌面端：设置/侧栏里同样找「帮助与反馈」入口）
2. **填内容**：
   - 类型选「**功能建议**」或「**问题反馈**」（建议两条分开提：bug 一条、项目分享一条）
   - bug 那条正文写精简版：
     ```
     Windows 宿主会话内（Bash 工具）拉起 codebuddy -p 时继承 CODEBUDDY_CONFIG_DIR /
     CODEBUDDY_MCP_CONFIG 等宿主变量，CLI 以宿主子进程形态运行，连接宿主 MCP 集群，
     单轮 prompt 138k token、11 分钟零产出；清变量后插件初始化失败（guard-unavailable exit 1）。
     独立终端正常。期望提供干净派发开关。完整复现：github.com/youchengyangdu-pixel/buddybridge docs/dispatch.md
     ```
   - 项目分享那条正文写：
     ```
     做了个开源项目 BuddyBridge：WorkBuddy 当任务控制中心、CodeBuddy CLI 无人值守执行，
     含实测教程（goal 挂机 / ultracode 多代理审查 / 文件契约 / 人工门控）。
     希望对社区用户有帮助：github.com/youchengyangdu-pixel/buddybridge（MIT）
     ```
3. **关键一步：勾选「上传日志」**（反馈界面底部的复选框）—— 官方凭日志能直接定位，比文字描述高效十倍
4. 提交 → 保留弹出的反馈编号（截图存档），后续在「我的反馈」里看回复

---

## 三渠道协同策略

| 顺序 | 动作 | 目的 |
|---|---|---|
| ① | 先发渠道三（CLI 内反馈，带日志） | 拿到工单号，bug 正式入池 |
| ② | 再发渠道二（邮件），正文里带一句「已在产品内反馈提交工单」 | 双通道触达，邮件可放完整报告 |
| ③ | 最后发渠道一（频道帖），附仓库链接 + 「已提交工单」 | 社区曝光 + 官方运营可能转载 |

**统一话术原则**：三个渠道都从「帮官方发现 bug / 帮社区用户」出发，项目链接自然带出 —— 不像求认可，官方反而更愿意转。

---

## 官方认可的真实路径（供预期管理）

1. 工单/issue 被确认 → 工程师回复（最常见的第一步）
2. 官方频道帖被置顶/转载 → 运营动作
3. 被拉进「核心用户群/共创群」（腾讯常见做法）
4. 官方文档/公众号引用你的项目（终极认可，需要时间 + 项目有 star 基本盘后自然发生）
```
