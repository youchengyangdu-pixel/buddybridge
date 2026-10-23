# bb-run.ps1 - BuddyBridge dispatch wrapper (Windows)
# Purpose: clean environment, isolated config, stdin prompt, hard timeout, real exit code.
# Usage:
#   powershell -ExecutionPolicy Bypass -File bb-run.ps1 -WorkDir <dir> [-ToolProfile file|shell|review] [-MaxTurns 40] [-TimeoutSec 3600] [-Model kimi-k3-2] [-DryRun]
# Requires: APPROVED.json in WorkDir (unless -SkipGate for demo runs)

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$WorkDir,
  [string]$ToolProfile = 'file',
  [int]$MaxTurns = 40,
  [int]$TimeoutSec = 3600,
  [string]$Model = '',
  [switch]$DryRun,
  [switch]$SkipGate
)

$ErrorActionPreference = 'Stop'

# ---------- helpers ----------
function Fail($msg, $code) {
  Write-Host ("[bb-run] BLOCKED: " + $msg) -ForegroundColor Red
  exit $code
}

function Write-Json($path, $obj) {
  $json = $obj | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-FileSha($path, $len) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
  if ($len -gt 0) { return $h.Substring(0, $len) }
  return $h
}

# ---------- 1. contract checks ----------
if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { Fail ("WorkDir not found: " + $WorkDir) 2 }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
$PlanPath = Join-Path $WorkDir 'PLAN.md'
$PromptPath = Join-Path $WorkDir 'PROMPT.md'
$ProgressPath = Join-Path $WorkDir 'PROGRESS.md'
$ApprovePath = Join-Path $WorkDir 'APPROVED.json'

if (-not (Test-Path -LiteralPath $PromptPath)) { Fail 'PROMPT.md missing (the task text must be written to a file, never inlined)' 3 }

$bbRoot = Join-Path $HOME '.buddybridge'
$runsRoot = Join-Path $WorkDir '.buddybridge\runs'
$locksRoot = Join-Path $WorkDir '.buddybridge\locks'
New-Item -ItemType Directory -Force -Path $runsRoot, $locksRoot | Out-Null

$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,6))
$runDir = Join-Path $runsRoot $runId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$logPath = Join-Path $runDir 'run.log'
$completionPath = Join-Path $runDir 'COMPLETION.json'
$heartbeatPath = Join-Path $runDir 'HEARTBEAT.json'
$stopPath = Join-Path $runDir 'STOP.json'

$planSha12 = Get-FileSha $PlanPath 12
$promptSha12 = Get-FileSha $PromptPath 12
$promptSha256 = Get-FileSha $PromptPath 0

# gate (unless explicitly skipped)
if (-not $SkipGate) {
  if (-not (Test-Path -LiteralPath $ApprovePath)) { Fail 'APPROVED.json missing - run bb-approve.ps1 first' 10 }
  try { $appr = Get-Content -LiteralPath $ApprovePath -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { Fail 'APPROVED.json is not valid JSON' 11 }
  if ($appr.plan_sha256 -ne $planSha12) { Fail ('PLAN hash mismatch: approved=' + $appr.plan_sha256 + ' actual=' + $planSha12) 12 }
  if ($appr.dispatch_sha256 -ne $promptSha12) { Fail ('PROMPT hash mismatch: approved=' + $appr.dispatch_sha256 + ' actual=' + $promptSha12) 13 }
  if ($appr.consumed -eq $true) { Fail 'APPROVED.json already consumed (one-shot token)' 14 }
  if ($appr.expires) {
    $exp = [DateTimeOffset]::Parse($appr.expires)
    if ([DateTimeOffset]::Now -gt $exp) { Fail 'APPROVED.json expired' 15 }
  }
  $noncePath = Join-Path $bbRoot ('pending\' + $appr.token + '.json')
  if (-not (Test-Path -LiteralPath $noncePath)) { Fail 'nonce not issued (token unknown to this machine)' 16 }
}

# lock
$lockName = $planSha12 + '.lock'
$lockPath = Join-Path $locksRoot $lockName
if (Test-Path -LiteralPath $lockPath) {
  $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $alive = $false
  if ($lock.pid) { $alive = [bool](Get-Process -Id $lock.pid -ErrorAction SilentlyContinue) }
  if ($alive) { Fail ('another run is active (pid=' + $lock.pid + ', run=' + $lock.run_id + ')') 17 }
}

# ---------- 2. tool profile ----------
$disallowed = ''
switch ($ToolProfile.ToLower()) {
  'file'   { $disallowed = 'Bash,PowerShell' }                                   # no shell at all
  'shell'  { $disallowed = '' }                                                   # allow shell (deny rules still apply)
  'review' { $disallowed = 'Bash,PowerShell,Write,Edit,MultiEdit' }               # read-only
  default  { Fail ('unknown ToolProfile: ' + $ToolProfile) 18 }
}

# ---------- 3. clean environment ----------
$envBackup = @{}
$toClear = @(
  'CODEBUDDY_MCP_CONFIG','CODEBUDDY_SESSION_ID','CODEBUDDY_CONVERSATION_REQUEST_ID',
  'CODEBUDDY_MESSAGE_ID','CODEBUDDY_TOOL_CALL_ID','CODEBUDDY_ARTIFACTS',
  'CODEBUDDY_SERVICE_PROXY_URL','CODEBUDDY_FORCE_HEADLESS_BUNDLE','CODEBUDDY_FORCE_LITE_WB_BUNDLE',
  'CODEBUDDY_SKILL_TOOL_CHAR_BUDGET','CODEBUDDY_USE_POWERSHELL_TOOL'
)
foreach ($k in $toClear) {
  $envBackup[$k] = [System.Environment]::GetEnvironmentVariable($k)
  [System.Environment]::SetEnvironmentVariable($k, $null)
}
$envBackup['CODEBUDDY_CONFIG_DIR'] = [System.Environment]::GetEnvironmentVariable('CODEBUDDY_CONFIG_DIR')
$homeCfg = Join-Path $bbRoot 'home'
New-Item -ItemType Directory -Force -Path $homeCfg | Out-Null
[System.Environment]::SetEnvironmentVariable('CODEBUDDY_CONFIG_DIR', $homeCfg)

# hook channel: hooks read BB_RUN_DIR to find this run's folder
$envBackup['BB_RUN_DIR'] = [System.Environment]::GetEnvironmentVariable('BB_RUN_DIR')
[System.Environment]::SetEnvironmentVariable('BB_RUN_DIR', $runDir)

# ---------- 4. build command ----------
$cb = Get-Command codebuddy -ErrorAction SilentlyContinue
if (-not $cb) { Fail 'codebuddy not in PATH (npm prefix missing?)' 19 }

# Prefer: node + package bin (no .ps1/.cmd shim, clean exit code, stdin-friendly)
$npmRoot = Split-Path -Parent $cb.Source
$pkgBin = Join-Path $npmRoot 'node_modules\@tencent-ai\codebuddy-code\bin\codebuddy'
$nodeExe = $null
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) { $nodeExe = $nodeCmd.Source }

$useNode = $false
if ($nodeExe -and (Test-Path -LiteralPath $pkgBin)) { $useNode = $true }

# Empty MCP config via file (avoids JSON quoting hell on the Windows command line)
$mcpFile = Join-Path $runDir 'empty-mcp.json'
[System.IO.File]::WriteAllText($mcpFile, '{"mcpServers":{}}', (New-Object System.Text.UTF8Encoding($false)))

$argList = @()
$argList += '-p'
$argList += '--max-turns'
$argList += [string]$MaxTurns
$argList += '--output-format'
$argList += 'text'
$argList += '--session-id'
$argList += $runId
$argList += '--strict-mcp-config'
$argList += '--mcp-config'
$argList += $mcpFile
if ($Model -ne '') { $argList += '--model'; $argList += $Model }
if ($disallowed -ne '') { $argList += '--disallowedTools'; $argList += $disallowed }

if ($useNode) {
  $fileName = $nodeExe
  $allArgs = @($pkgBin) + $argList
  $cliDesc = $nodeExe + ' ' + $pkgBin
} else {
  $fileName = $cb.Source
  $allArgs = $argList
  $cliDesc = $cb.Source
}

# ---------- 5. write run metadata + lock ----------
$runMeta = [ordered]@{
  run_id = $runId
  started_at = (Get-Date).ToString('o')
  work_dir = $WorkDir
  plan_sha256_12 = $planSha12
  prompt_sha256_12 = $promptSha12
  prompt_sha256 = $promptSha256
  tool_profile = $ToolProfile
  disallowed_tools = $disallowed
  model = $Model
  max_turns = $MaxTurns
  timeout_sec = $TimeoutSec
  config_dir = $homeCfg
  cli_path = $cliDesc
  status = 'RUNNING'
}
Write-Json (Join-Path $runDir 'RUN.json') $runMeta
$lockObj = [ordered]@{ run_id = $runId; pid = $PID; started_at = (Get-Date).ToString('o'); work_dir = $WorkDir }
Write-Json $lockPath $lockObj

$latest = [ordered]@{ run_id = $runId; run_dir = $runDir; status = 'RUNNING'; updated_at = (Get-Date).ToString('o') }
Write-Json (Join-Path $WorkDir '.buddybridge\LATEST.json') $latest

if ($DryRun) {
  Write-Host '[bb-run] DRY RUN - no CLI started' -ForegroundColor Yellow
  Write-Host ('  cli      : ' + $cliDesc)
  Write-Host ('  args     : ' + ($argList -join ' '))
  Write-Host ('  config   : ' + $homeCfg)
  Write-Host ('  run dir  : ' + $runDir)
  Write-Host ('  cleared  : ' + ($toClear -join ','))
  Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
  exit 0
}

# ---------- 6. start process (stdin prompt + hard timeout) ----------
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $fileName
$psi.Arguments = (($allArgs | ForEach-Object {
  $s = [string]$_
  if ($s -match '[\s"]') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
}) -join ' ')
$psi.WorkingDirectory = $WorkDir
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi

try {
  $proc.Start() | Out-Null
  $promptText = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
  $proc.StandardInput.Write($promptText)
  $proc.StandardInput.Close()

  $outTask = $proc.StandardOutput.ReadToEndAsync()
  $errTask = $proc.StandardError.ReadToEndAsync()

  $timeoutMs = $TimeoutSec * 1000
  $finished = $proc.WaitForExit($timeoutMs)
  if (-not $finished) {
    try { & taskkill /PID $proc.Id /T /F | Out-Null } catch {}
    $status = 'TIMEOUT'
    $exitCode = 124
  } else {
    $status = 'EXITED'
    $exitCode = $proc.ExitCode
  }
  $sw.Stop()
  $stdout = ''
  $stderr = ''
  if ($outTask.Wait(5000)) { $stdout = $outTask.Result }
  if ($errTask.Wait(5000)) { $stderr = $errTask.Result }
  $combined = ($stdout + "`n" + $stderr)
  [System.IO.File]::WriteAllText($logPath, $combined, (New-Object System.Text.UTF8Encoding($false)))
} catch {
  $sw.Stop()
  $status = 'ERROR'
  $exitCode = 1
  [System.IO.File]::WriteAllText($logPath, ('[bb-run] ' + $_.Exception.Message), (New-Object System.Text.UTF8Encoding($false)))
}

# ---------- 7. ledger verify + COMPLETION ----------
$ledger = [ordered]@{ entries = 0; done = 0; failed = 0; missing_files = 0; hash_mismatch = 0 }
if (Test-Path -LiteralPath $ProgressPath) {
  $lines = Get-Content -LiteralPath $ProgressPath -Encoding UTF8 | Where-Object { $_ -match '^\d' }
  $ledger.entries = @($lines).Count
  foreach ($l in $lines) {
    $f = $l -split '\|'
    if ($f.Count -ge 5) {
      if ($f[1] -eq 'done') { $ledger.done++ }
      if ($f[1] -eq 'failed') { $ledger.failed++ }
      $p = $f[2]
      if ($p -and -not (Test-Path -LiteralPath $p)) { $ledger.missing_files++ }
      elseif ($p -and $f[4]) {
        $real = Get-FileSha $p 8
        if ($real -and $real -ne $f[4].ToLower()) { $ledger.hash_mismatch++ }
      }
    }
  }
}

$completion = [ordered]@{
  run_id = $runId
  status = $status
  exit_code = $exitCode
  started_at = $runMeta.started_at
  finished_at = (Get-Date).ToString('o')
  duration_sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  tool_profile = $ToolProfile
  model = $Model
  log_path = $logPath
  log_tail = ''
  ledger = $ledger
}
if (Test-Path -LiteralPath $logPath) {
  $tail = Get-Content -LiteralPath $logPath -Tail 20 -Encoding UTF8 -ErrorAction SilentlyContinue
  $completion.log_tail = ($tail -join "`n")
}
Write-Json $completionPath $completion

$latest.status = $status
$latest.updated_at = (Get-Date).ToString('o')
$latest.exit_code = $exitCode
Write-Json (Join-Path $WorkDir '.buddybridge\LATEST.json') $latest

# consume approval (one-shot)
if (-not $SkipGate -and (Test-Path -LiteralPath $ApprovePath)) {
  $a = Get-Content -LiteralPath $ApprovePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $a | Add-Member -NotePropertyName consumed -NotePropertyValue $true -Force
  $a | Add-Member -NotePropertyName consumed_at -NotePropertyValue ((Get-Date).ToString('o')) -Force
  Write-Json $ApprovePath $a
  $np = Join-Path $bbRoot ('pending\' + $a.token + '.json')
  Remove-Item -LiteralPath $np -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue

# restore env
foreach ($k in $envBackup.Keys) {
  [System.Environment]::SetEnvironmentVariable($k, $envBackup[$k])
}

Write-Host ('[bb-run] ' + $status + ' exit=' + $exitCode + ' in ' + $completion.duration_sec + 's') -ForegroundColor Green
Write-Host ('  run dir : ' + $runDir)
Write-Host ('  ledger  : entries=' + $ledger.entries + ' done=' + $ledger.done + ' failed=' + $ledger.failed + ' missing=' + $ledger.missing_files + ' hash_mismatch=' + $ledger.hash_mismatch)
exit $exitCode
