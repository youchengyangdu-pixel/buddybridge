# bb-approve.ps1 - Issue a one-shot approval for a dispatch (run by the HUMAN)
# Usage:
#   powershell -ExecutionPolicy Bypass -File bb-approve.ps1 -WorkDir <dir> [-TtlHours 24] [-Approver "name"] [-Note "why"]
# Writes: <WorkDir>\APPROVED.json  +  ~\.buddybridge\pending\<token>.json
# The token is consumed by bb-run.ps1 after a successful dispatch (one-shot).

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$WorkDir,
  [string]$PlanFile = 'PLAN.md',
  [string]$PromptFile = 'PROMPT.md',
  [int]$TtlHours = 24,
  [string]$Approver = $env:USERNAME,
  [string]$Note = ''
)

$ErrorActionPreference = 'Stop'

function Fail($msg, $code) { Write-Host ('[bb-approve] BLOCKED: ' + $msg) -ForegroundColor Red; exit $code }

if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { Fail ('WorkDir not found: ' + $WorkDir) 2 }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
$planPath = Join-Path $WorkDir $PlanFile
$promptPath = Join-Path $WorkDir $PromptFile

if (-not (Test-Path -LiteralPath $planPath)) { Fail ($PlanFile + ' missing') 3 }
if (-not (Test-Path -LiteralPath $promptPath)) { Fail ($PromptFile + ' missing - write the exact task text to this file first') 4 }

$planSha12 = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLower().Substring(0, 12)
$promptSha12 = (Get-FileHash -LiteralPath $promptPath -Algorithm SHA256).Hash.ToLower().Substring(0, 12)
$promptSha256 = (Get-FileHash -LiteralPath $promptPath -Algorithm SHA256).Hash.ToLower()

# 16-byte random token (hex)
$bytes = New-Object byte[] 16
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$token = -join ($bytes | ForEach-Object { $_.ToString('x2') })

$now = Get-Date
$expires = $now.AddHours($TtlHours)

$approval = [ordered]@{
  plan_sha256 = $planSha12
  dispatch_sha256 = $promptSha12
  prompt_sha256_full = $promptSha256
  token = $token
  issued_at = $now.ToString('o')
  expires = $expires.ToString('o')
  approver = $Approver
  note = $Note
  work_dir = $WorkDir
  consumed = $false
}

$approvePath = Join-Path $WorkDir 'APPROVED.json'
$json = $approval | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($approvePath, $json, (New-Object System.Text.UTF8Encoding($false)))

$pendingDir = Join-Path $HOME '.buddybridge\pending'
New-Item -ItemType Directory -Force -Path $pendingDir | Out-Null
$nonce = [ordered]@{
  token = $token
  plan_sha256 = $planSha12
  dispatch_sha256 = $promptSha12
  work_dir = $WorkDir
  issued_at = $now.ToString('o')
  expires = $expires.ToString('o')
}
$noncePath = Join-Path $pendingDir ($token + '.json')
[System.IO.File]::WriteAllText($noncePath, ($nonce | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

Write-Host '[bb-approve] APPROVED' -ForegroundColor Green
Write-Host ('  plan sha12     : ' + $planSha12)
Write-Host ('  dispatch sha12 : ' + $promptSha12 + '  (PROMPT.md content)')
Write-Host ('  token          : ' + $token)
Write-Host ('  expires        : ' + $expires.ToString('yyyy-MM-dd HH:mm:ss') + '  (' + $TtlHours + 'h)')
Write-Host ('  approval file  : ' + $approvePath)
Write-Host ('  nonce file     : ' + $noncePath)
Write-Host ''
Write-Host 'Next: powershell -ExecutionPolicy Bypass -File bb-run.ps1 -WorkDir "' + $WorkDir + '"' -ForegroundColor Yellow
