# bb-review-run.ps1 — BuddyBridge 审查链路实测（降级方案三轮，串行）
# 用法：在独立 PowerShell 窗口运行  .\bb-review-run.ps1
$ErrorActionPreference = "Continue"
$D = "D:\workbuddy 工作区\CLI挂机测试\bb-review-demo"
Set-Location $D
$env:HTTPS_PROXY = "http://127.0.0.1:7897"  # 保险（CLI 拉模型不一定需要，但无害）

Write-Host "=== Round A: kimi-k3-2 审 可行性+风险 ===" -ForegroundColor Cyan
codebuddy -p -y --model kimi-k3-2 --max-turns 30 '按 D:/workbuddy 工作区/CLI挂机测试/bb-review-demo/REVIEW-BRIEF.md 审查 D:/workbuddy 工作区/CLI挂机测试/bb-review-demo/PLAN.md 的「可行性+风险」维度，产出 D:/workbuddy 工作区/CLI挂机测试/bb-review-demo/REVIEW-A.md，报告首行必须写 model: kimi-k3-2' > review-a.log 2>&1
Write-Host "A 完成 exit=$LASTEXITCODE"

Write-Host "=== Round B: deepseek-v4.1-flash 审 验收项+完整性 ===" -ForegroundColor Cyan
codebuddy -p -y --model deepseek-v4.1-flash --max-turns 30 '按 D:/workbuddy 工作区/CLI挂机测试/bb-review-demo/REVIEW-BRIEF.md 审查 D:/workbuddy 工作区/CLI挂机测试/bb-review-demo/PLAN.md 的「验收项可验证性+完整性」维度，产出 D:/workbuddy 工作区/CLI挂机测试/bb-review-demo/REVIEW-B.md，报告首行必须写 model: deepseek-v4.1-flash' > review-b.log 2>&1
Write-Host "B 完成 exit=$LASTEXITCODE"

Write-Host "=== Round C: hy4-preview 对抗轮 ===" -ForegroundColor Cyan
codebuddy -p -y --model hy4-preview --max-turns 30 '阅读 D:/workbuddy 工作区/CLI挂机测试/bb-review-demo/REVIEW-A.md 与 D:/workbuddy 工作区/CLI挂机测试/bb-review-demo/REVIEW-B.md，专挑两者结论的漏洞并反驳，产出 D:/workbuddy 工作区/CLI挂机测试/bb-review-demo/REVIEW-C.md，报告首行必须写 model: hy4-preview' > review-c.log 2>&1
Write-Host "C 完成 exit=$LASTEXITCODE"

Write-Host "=== 全部完成，产物清单 ===" -ForegroundColor Green
Get-ChildItem $D\REVIEW-*.md | ForEach-Object { Write-Host $_.Name $_.Length }
