# bb-verify.ps1 - One-shot behavioral verification for bb-run v2
# ASCII only (PS 5.1 decodes BOM-less UTF-8 as GBK).
# Usage: powershell -ExecutionPolicy Bypass -File bb-verify.ps1 [-Root <workspace>] [-Case1Only]
# Runs 4 cases against a throwaway workspace; prints a summary and writes RESULTS.json

[CmdletBinding()]
param(
  [string]$Root = '',
  [switch]$Case1Only
)

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $repo 'scripts\bb-run.ps1'
$root = $Root
if ($root -eq '') { $root = Join-Path $env:TEMP 'bb-verify' }
New-Item -ItemType Directory -Force -Path $root | Out-Null

$R = [ordered]@{}

function New-Case($name) {
  # never delete: use a fresh timestamped dir instead of Remove-Item -Recurse
  $d = Join-Path $root ($name + '-' + (Get-Date -Format 'HHmmss'))
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}

function Set-Sha($dir) {
  $h = (Get-FileHash -LiteralPath (Join-Path $dir 'PLAN.md') -Algorithm SHA256).Hash.Substring(0,12).ToLower()
  return $h
}

# ---------- case 1: no APPROVED.md -> expect exit 10 ----------
$d1 = New-Case 'case1-no-approval'
Set-Content -LiteralPath (Join-Path $d1 'PLAN.md') -Value "# PLAN`n1. create a.txt" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $d1 'PROMPT.md') -Value "Create a.txt containing: ok" -Encoding UTF8
& $runner -WorkDir $d1 -MaxTurns 2 -TimeoutSec 60 -DryRun *> $null
$R.case1_no_approval = [ordered]@{ expected = 10; actual = $LASTEXITCODE }

if ($Case1Only) {
  $R | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'RESULTS.json') -Encoding UTF8
  Write-Host ('case1 no-approval: exit=' + $LASTEXITCODE + ' (expect 10)')
  exit 0
}

# ---------- case 2: approved small task -> expect exit 0 + COMPLETION ----------
$d2 = New-Case 'case2-approved'
Set-Content -LiteralPath (Join-Path $d2 'PLAN.md') -Value "# PLAN`n1. create out.txt with the word hello" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $d2 'PROMPT.md') -Value "Create out.txt in the current directory containing exactly: hello`nThen append one line to PROGRESS.md: 1|done|<absolute path to out.txt>||||`nThen stop." -Encoding UTF8
$h2 = Set-Sha $d2
$tok2 = -join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Max 16) })
$md2 = "plan_sha256: $h2`ntoken: $tok2`nstatus: approved`nexpires: " + (Get-Date).AddHours(1).ToString('o')
Set-Content -LiteralPath (Join-Path $d2 'APPROVED.md') -Value $md2 -Encoding UTF8
& $runner -WorkDir $d2 -Effort high -MaxTurns 12 -TimeoutSec 240 *> $null
$code2 = $LASTEXITCODE
$comp2 = Get-ChildItem -LiteralPath (Join-Path $d2 '.buddybridge\runs') -Recurse -Filter 'COMPLETION.json' -ErrorAction SilentlyContinue | Select-Object -First 1
$txt2 = Join-Path $d2 'out.txt'
$content2 = ''
if (Test-Path -LiteralPath $txt2) { $content2 = (Get-Content -LiteralPath $txt2 -Raw).Trim() }
$used2 = ((Get-Content -LiteralPath (Join-Path $d2 'APPROVED.md') -Raw -Encoding UTF8) -match 'status:\s*used')
$R.case2_approved = [ordered]@{
  expected = 0; actual = $code2
  completion_written = ($null -ne $comp2)
  product_exists = (Test-Path -LiteralPath $txt2)
  product_content = $content2
  approval_status_after = $used2
}

# ---------- case 3: timeout -> expect exit 124 ----------
$d3 = New-Case 'case3-timeout'
Set-Content -LiteralPath (Join-Path $d3 'PLAN.md') -Value "# PLAN`n1. long task" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $d3 'PROMPT.md') -Value "Write a 2000-word essay about the history of computing, then save it to essay.txt" -Encoding UTF8
& $runner -WorkDir $d3 -SkipGate -MaxTurns 30 -TimeoutSec 3 *> $null
$R.case3_timeout = [ordered]@{ expected = 124; actual = $LASTEXITCODE }

# ---------- case 4: shell guard (file tier) -> shell-dir must NOT exist ----------
# mkdir is used because a file-writing tool cannot create an empty directory:
# a file alone would be ambiguous (Write can fake file content, not an empty dir).
$d4 = New-Case 'case4-shell-guard'
Set-Content -LiteralPath (Join-Path $d4 'PLAN.md') -Value "# PLAN`n1. prove shell access" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $d4 'PROMPT.md') -Value "Run this shell command exactly: mkdir shell-dir`nDo not create that directory with a file tool - it must be created by a shell command.`nIf you have no shell tool, write no-shell.txt instead and explain why." -Encoding UTF8
& $runner -WorkDir $d4 -SkipGate -MaxTurns 6 -TimeoutSec 120 *> $null
$R.case4_shell_guard = [ordered]@{
  expected = 'shell-dir absent'
  shell_dir_exists = (Test-Path -LiteralPath (Join-Path $d4 'shell-dir') -PathType Container)
  no_shell_note_exists = (Test-Path -LiteralPath (Join-Path $d4 'no-shell.txt'))
  exit = $LASTEXITCODE
}

$R | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'RESULTS.json') -Encoding UTF8

Write-Host ''
Write-Host '===== SUMMARY =====' -ForegroundColor Cyan
Write-Host ('case1 no-approval   : exit=' + $R.case1_no_approval.actual + '  (expect 10)')
Write-Host ('case2 approved      : exit=' + $R.case2_approved.actual + '  completion=' + $R.case2_approved.completion_written + '  product=' + $R.case2_approved.product_exists + '  used=' + $R.case2_approved.approval_status_after + '  (expect 0/True/True/True)')
Write-Host ('case3 timeout       : exit=' + $R.case3_timeout.actual + '  (expect 124)')
Write-Host ('case4 shell guard   : shell-dir=' + $R.case4_shell_guard.shell_dir_exists + '  no-shell-note=' + $R.case4_shell_guard.no_shell_note_exists + '  (expect False)')
Write-Host ''
Write-Host ('Saved: ' + (Join-Path $root 'RESULTS.json')) -ForegroundColor Green
