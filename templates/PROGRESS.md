# PROGRESS：〈对应 PLAN 标题〉

> This is the executing agent's self-reported ledger — treat it as a **claim, not proof**.（本文件是执行 agent 的「声明」而非「证明」；真实校验值由 `bb-run` 在收尾时统一计算，写进 `COMPLETION.json.verified`。）
>
> 格式：`编号|状态|产物路径|||`（**后三列留空**）。状态：done / skipped / failed。
> **不要自己算 sha256 / 字节数**：默认档不授予 shell，你算不出来，填一个编造的值会让 `COMPLETION.ledger.hash_mismatch` 误报。
> 记账顺序铁律：**先产出完整文件 → 再追加进度行**（先记账后写产物 = 崩溃时半截产物被永久跳过）。
> 重派时只追加不删除历史行；同一编号的重试请用新编号 `<原编号>r<次数>`（如 `3r1`）。
> 验收以 `COMPLETION.json` 的 `ledger`（done / failed / missing_files / hash_mismatch / gaps）为准，不以本文件的最后一行为准。

1|done|〈产物绝对路径〉|||
2|done|〈产物绝对路径〉|||
