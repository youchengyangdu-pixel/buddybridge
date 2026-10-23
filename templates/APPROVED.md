# 批准凭证（APPROVED）

> 这是**唯一**的放行凭证。`bb-run.ps1` 只读三项：`dispatch_sha256` / `status` / `expires`。
> 指纹同时覆盖 `PLAN.md` **和** `PROMPT.md` —— 换了任务书也必须重新批准。
> 派发时脚本会立刻把 `status: approved` 改写为 `status: used`（claim-at-gate），同一份凭证不能再用第二次。

- dispatch_sha256: 000000000000
- token: 0000000000000000
- status: approved
- work_dir: <项目绝对路径（可选，填了就锁定目录；不填则只绑内容）>
- issued_at: 2026-01-01T00:00:00+08:00
- expires: 2026-01-02T00:00:00+08:00
- 拍板人: <你的名字>
- 备注: <为什么批准这一版>

## 怎么填

```powershell
$p = (Get-FileHash .\PLAN.md  -Algorithm SHA256).Hash.ToLower()
$q = (Get-FileHash .\PROMPT.md -Algorithm SHA256).Hash.ToLower()
$h = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($p + ':' + $q))
(-join ($h | ForEach-Object { $_.ToString('x2') })).Substring(0,12)
```

把输出抄进 `dispatch_sha256`，再生成一个 token：

```powershell
-join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
```

`status` 保持 `approved`。`expires` 可选；写了就按时间失效，不写就只靠 `used` 防重放。

## 为什么要人填

`bb-run` 不替你算指纹 —— 因为你（人）必须**真的看过 PLAN.md 和 PROMPT.md** 才能批准。
脚本自动填 = 门控变成自动盖章，等于没有门控。

## 边界（重要）

这套门控防的是**误操作与流程跳步**，不是恶意用户：同一 Windows 账号下，任何进程都能读写这些文件。
真正的护栏是三层叠加：`dispatch_sha256` 绑定内容 + `status` 一次性 + `--disallowedTools` 让执行 agent 没有 shell。

## 注意

- 改了 `PLAN.md` 或 `PROMPT.md` 任意一个字节，旧指纹立即失效（脚本会报出两个值）。
- 同一份 `APPROVED.md` 跑第二次会被拒（`status: used`）。
- `Edit(**/APPROVED.md)` 在 deny 列表里，执行 agent 改不了这份文件。
