# BuddyBridge v1.1 验证报告

日期：2026-10-24 | HEAD：`13f06ce` | 环境：Windows PowerShell 5.1 + CodeBuddy CLI 2.159.0

## 行为验证：5/5 全绿（全真跑，非 DryRun）

命令：`powershell -ExecutionPolicy Bypass -File scripts/bb-verify.ps1`

| case | 结果 | 证明的事 |
|---|---|---|
| 1 无批准 | `exit=10` | 门控真的拒绝，不是提示性摆设 |
| 2 正常派发 | `exit=0` + `COMPLETION.json` + 产物落地 + `status=used` | 全链路通；批准被消费 |
| 3 硬超时 | `exit=124` | 卡死能被杀，不会永远挂 |
| 4 默认无 shell | `shell-dir=False` + `no-shell.txt` 存在 | 执行 agent 找不到任何 shell 工具 |
| 5 自签批准 | `still_used=True` / `flipped=False` | **deny 拦住了 agent 改写 APPROVED.md**，人工门控是真边界 |

## 修复过程中独立验证过的项

- 联合指纹：只改 `PROMPT.md` 不改 `PLAN.md` → `BLOCKED` exit 17
- `status: APPROVED`（大写）→ 正确通过并置 `used`（此前会永久重放）
- `work_dir` 不匹配 → exit 18；占位符 `<...>` 视为未绑定
- DryRun 不消费批准
- `-SkipGate` → 红字警告 + `COMPLETION.gate='skipped'`

## 仍未覆盖（诚实标注）

| 项 | 状态 |
|---|---|
| `hash_mismatch` 实际触发 | 未自动化验证（需要构造「账本声明 hash 与产物不符」的夹具） |
| `gaps` / `gaps_skipped` 实际触发 | 未自动化验证（需要日期式编号与缺号夹具） |
| `claim_rolled_back` 实际触发 | 未自动化验证（需要模型名不存在 / 凭据过期的环境） |
| macOS `bb-run.sh` | 未实现 |
| 引擎A（调研/审查）的 wrapper | 未实现，仍靠 SKILL.md 纪律 |

## 已知边界（已文档化）

- `claim-at-gate` 是**缩窗**不是锁：同一 WorkDir 不要同时派发两个 run
- `work_dir` 默认不绑定（模板里注释掉），填了就锁目录
- `token` 只校验存在，不做强可核验：同用户模型下门控是**派发纪律**，不是安全边界
- `expires` 解析失败时 fail-open（`try{}catch{}`）

## 结论

门控 / 派发 / 超时 / 无 shell / 自签防护 五项核心行为已实测通过，可以投入日常使用。
上述「未覆盖」四项是辅助判定字段，不影响主流程；如需全覆盖，构造对应夹具即可。
