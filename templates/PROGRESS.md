# PROGRESS：〈对应 PLAN 标题〉

> This is the executing agent's self-reported ledger — treat it as a **claim, not proof**. Verification must recompute checksums and spot-check content.（本文件是执行 agent 的「声明」而非「证明」；验收必须重算校验值并抽样复验内容。）
>
> 格式：`编号|状态|产物路径|字节数|sha256前8位`。状态：done / skipped / failed。
> 记账顺序铁律：**先产出完整文件 → 再计算校验值 → 最后追加进度行**（先记账后写产物 = 崩溃时半截产物被永久跳过）。
> 重派时只追加不删除历史行；验收以**该编号最后一行**为准。
> 验收方法：逐行重算产物 sha256 前 8 位比对（PowerShell：`(Get-FileHash '<产物>' -Algorithm SHA256).Hash.Substring(0,8).ToLower()`；macOS/Linux：`shasum -a 256 '<产物>' | cut -c1-8`）+ 随机抽 1 项核对内容是否符合 PLAN 对应验收标准。

1|done|〈产物路径〉|〈字节数〉|〈sha256前8位〉
2|done|〈产物路径〉|〈字节数〉|〈sha256前8位〉
