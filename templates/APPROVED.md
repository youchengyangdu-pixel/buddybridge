# 批准凭证（APPROVED）

> 这是**唯一**的放行凭证。`bb-run.ps1` 只读三项：`plan_sha256` / `status` / `expires`。
> 执行成功后脚本会把 `status: approved` 改写为 `status: used` —— 同一份凭证不能再用第二次。

- plan_sha256: 000000000000
- token: 0000000000000000
- status: approved
- issued_at: 2026-01-01T00:00:00+08:00
- expires: 2026-01-02T00:00:00+08:00
- 拍板人: <你的名字>
- 备注: <为什么批准这一版>

## 怎么填

```powershell
# 1) PLAN 的校验值（前 12 位）
(Get-FileHash .\PLAN.md -Algorithm SHA256).Hash.Substring(0,12).ToLower()

# 2) 随机 token（16 位 hex）
-join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
```

把两个结果抄进上面的 `plan_sha256` 和 `token`，`status` 保持 `approved`。
`expires` 可选；写了就按时间失效，不写就只靠 `used` 防重放。

## 为什么要人填

`bb-run` 不替你生成 hash —— 因为你（人）必须**真的看过 PLAN.md** 才能批准。
脚本自动填 = 门控变成自动盖章，等于没有门控。

## 注意

- 改了 `PLAN.md` 任意一个字节，旧 hash 立即失效（脚本会拒绝并报出两个值）。
- 同一份 `APPROVED.md` 跑第二次会被拒（`status: used`）。
- `Edit(**/APPROVED.md)` 在 deny 列表里，执行 agent 改不了这份文件。
