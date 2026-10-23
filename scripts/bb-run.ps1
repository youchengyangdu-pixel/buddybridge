# bb-run.ps1 v2 - BuddyBridge dispatch wrapper (slim)
# One job: clean env -> isolated config -> stdin prompt -> hard timeout -> real exit code -> COMPLETION.json
# Gate: APPROVED.md must exist, dispatch_sha256 must cover PLAN.md + PROMPT.md, status "approved" -> "used" at claim time
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File bb-run.ps1 -WorkDir <dir> [-Effort high] [-Model kimi-k3-2] [-MaxTurns 40] [-TimeoutSec 3600] [-SkipGate] [-DryRun]

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$WorkDir,
  [string]$Effort = 'high',
  [string]$Model = 'kimi-k3-2',
  [int]$MaxTurns = 40,
  [int]$TimeoutSec = 3600,
  [switch]$SkipGate,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Fail($msg, $code) { Write-Host ('[bb-run] BLOCKED: ' + $msg) -ForegroundColor Red; exit $code }
function WriteJson($path, $obj) {
  $tmp = $path + '.tmp'
  [System.IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $path -Force
}

# ---------- paths ----------
if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { Fail ('WorkDir not found: ' + $WorkDir) 2 }
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
$PlanPath = Join-Path $WorkDir 'PLAN.md'
$PromptPath = Join-Path $WorkDir 'PROMPT.md'
$ProgressPath = Join-Path $WorkDir 'PROGRESS.md'
$ApprovePath = Join-Path $WorkDir 'APPROVED.md'
$bbRoot = Join-Path $HOME '.buddybridge'
$homeCfg = Join-Path $bbRoot 'home'
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss')
$runDir = Join-Path $WorkDir ('.buddybridge\runs\' + $runId)
New-Item -ItemType Directory -Force -Path $runDir, $homeCfg | Out-Null
$logPath = Join-Path $runDir 'run.log'
$completionPath = Join-Path $runDir 'COMPLETION.json'

if (-not (Test-Path -LiteralPath $PromptPath)) { Fail 'PROMPT.md missing - write the task text to that file (see templates/PROMPT.md)' 3 }

# ---------- guard settings must live in the isolated config dir ----------
# Done BEFORE the gate: a broken settings template must never burn an approval.
$repoRoot = Split-Path -Parent $PSScriptRoot
$tpl = Join-Path $repoRoot 'install\settings.windows.json'
$bbSettings = Join-Path $homeCfg 'settings.json'
if (Test-Path -LiteralPath $tpl) {
  try {
    $cfg = Get-Content -LiteralPath $tpl -Raw -Encoding UTF8 | ConvertFrom-Json
    [System.IO.File]::WriteAllText($bbSettings, ($cfg | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
  } catch {
    Fail ('settings template is not valid JSON: ' + $tpl + ' - fix it before dispatching') 21
  }
}

# ---------- gate: APPROVED.md (single carrier, human-readable) ----------
# Fingerprint covers BOTH files: approving PLAN.md but swapping PROMPT.md must fail.
# PROMPT is read ONCE here and that exact byte array is fed to the CLI later,
# so "verify A, execute B" is impossible.
function Get-DispatchSha12($planFile, [byte[]]$promptBytes) {
  $p = (Get-FileHash -LiteralPath $planFile -Algorithm SHA256).Hash.ToLower()
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $q = -join ($sha.ComputeHash($promptBytes) | ForEach-Object { $_.ToString('x2') })
  $seed = [System.Text.Encoding]::ASCII.GetBytes($p + ':' + $q)
  $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash($seed)
  return (-join ($h | ForEach-Object { $_.ToString('x2') })).Substring(0, 12)
}

$PromptBytes = [System.IO.File]::ReadAllBytes($PromptPath)

$gateInfo = [ordered]@{ checked = $false; status = 'skipped'; claimed = $false }
# availability must be verified BEFORE claiming an approval, otherwise a missing CLI burns it
$cb = Get-Command codebuddy -ErrorAction SilentlyContinue
if (-not $cb) { Fail 'codebuddy not in PATH' 19 }
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
$pkgBin = Join-Path (Split-Path -Parent $cb.Source) 'node_modules\@tencent-ai\codebuddy-code\bin\codebuddy'
$useNode = ($nodeCmd -and (Test-Path -LiteralPath $pkgBin))
if (-not $useNode) { Fail 'node or package entry not found - reinstall @tencent-ai/codebuddy-code' 20 }

if (-not $SkipGate) {
  if (-not (Test-Path -LiteralPath $ApprovePath)) { Fail 'APPROVED.md missing' 10 }
  if (-not (Test-Path -LiteralPath $PlanPath)) { Fail 'PLAN.md missing' 11 }
  $md = Get-Content -LiteralPath $ApprovePath -Raw -Encoding UTF8
  # case-insensitive + anchored at line start (a stray mention in the prose must never match)
  $opt = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline
  $hm = [regex]::Match($md, '(?m)^\s*[-*]?\s*dispatch_sha256\s*:\s*([0-9a-f]{12})', $opt)
  $tm = [regex]::Match($md, '(?m)^\s*[-*]?\s*token\s*:\s*([0-9a-f]{8,32})', $opt)
  $sm = [regex]::Match($md, '(?m)^\s*[-*]?\s*status\s*:\s*([A-Za-z]+)', $opt)
  $em = [regex]::Match($md, '(?m)^\s*[-*]?\s*expires\s*:\s*([0-9T:+\-\.]{10,40})', $opt)
  $wm = [regex]::Match($md, '(?m)^\s*[-*]?\s*work_dir\s*:\s*(.+)$', $opt)
  if (-not $hm.Success) { Fail 'APPROVED.md has no dispatch_sha256 (it must cover PLAN.md + PROMPT.md)' 12 }
  if (-not $tm.Success) { Fail 'APPROVED.md has no token' 13 }
  if (-not $sm.Success) { Fail 'APPROVED.md has no status' 14 }
  $status = $sm.Groups[1].Value.ToLower()
  if ($status -ne 'approved') { Fail ('APPROVED.md status is "' + $status + '" (expected approved; used means already consumed)') 15 }
  if ($em.Success) {
    try {
      $exp = [DateTimeOffset]::Parse($em.Groups[1].Value)
      if ([DateTimeOffset]::Now -gt $exp) { Fail 'APPROVED.md expired' 16 }
    } catch { }
  }
  # optional binding to this directory: a copied bundle must not approve a different folder
  if ($wm.Success) {
    $declaredDir = $wm.Groups[1].Value.Trim().Trim('"')
    # an unfilled placeholder ("<项目绝对路径>") means "not bound", not a mismatch
    if ($declaredDir -and $declaredDir -notmatch '^[<（(]') {
      $normDeclared = $declaredDir.Replace('\','/').TrimEnd('/').ToLower()
      $normActual = $WorkDir.Replace('\','/').TrimEnd('/').ToLower()
      if ($normDeclared -ne $normActual) {
        Fail ('work_dir mismatch: approved for "' + $declaredDir + '" but dispatching "' + $WorkDir + '"') 18
      }
    }
  }
  $actual = Get-DispatchSha12 $PlanPath $PromptBytes
  if ($hm.Groups[1].Value.ToLower() -ne $actual) {
    Fail ('dispatch hash mismatch: approved=' + $hm.Groups[1].Value.ToLower() + ' actual=' + $actual + ' (covers PLAN.md + PROMPT.md)') 17
  }
  # claim-at-gate: flip to used before the CLI runs, which shrinks the replay window
  # from "the whole run" to "a few milliseconds". This is NOT a lock: two processes
  # that read the file in the same instant can still both pass. One WorkDir = one run
  # at a time is a documented operating rule, not an enforced invariant.
  # A dry run must NOT consume the approval.
  if (-not $DryRun) {
    $mdUsed = [regex]::Replace($md, '(?m)^(\s*[-*]?\s*status\s*:\s*)approved', '${1}used', $opt)
    [System.IO.File]::WriteAllText($ApprovePath, $mdUsed, (New-Object System.Text.UTF8Encoding($false)))
    $gateInfo.status = 'used'
    $gateInfo.claimed = $true
  } else {
    $gateInfo.status = 'approved (dry-run, not consumed)'
  }
  $gateInfo.checked = $true
  $gateInfo.token = $tm.Groups[1].Value
} else {
  Write-Host '[bb-run] WARNING: gate SKIPPED - this dispatch has no approval and no plan lock' -ForegroundColor Red
}

# ---------- clean environment ----------
$backup = @{}
foreach ($k in @(
  'CODEBUDDY_MCP_CONFIG','CODEBUDDY_SESSION_ID','CODEBUDDY_CONVERSATION_REQUEST_ID',
  'CODEBUDDY_MESSAGE_ID','CODEBUDDY_TOOL_CALL_ID','CODEBUDDY_ARTIFACTS',
  'CODEBUDDY_SERVICE_PROXY_URL','CODEBUDDY_FORCE_HEADLESS_BUNDLE','CODEBUDDY_FORCE_LITE_WB_BUNDLE',
  'CODEBUDDY_CONFIG_DIR'
)) {
  $backup[$k] = [System.Environment]::GetEnvironmentVariable($k)
  [System.Environment]::SetEnvironmentVariable($k, $null)
}
[System.Environment]::SetEnvironmentVariable('CODEBUDDY_CONFIG_DIR', $homeCfg)

# ---------- build command ----------
# ($cb / $nodeCmd / $pkgBin / $useNode were resolved before the gate, so a missing CLI never burns an approval)

$mcpFile = Join-Path $runDir 'empty-mcp.json'
[System.IO.File]::WriteAllText($mcpFile, '{"mcpServers":{}}', (New-Object System.Text.UTF8Encoding($false)))

$args = @('-p','-y','--effort',$Effort,'--max-turns',[string]$MaxTurns,'--output-format','text',
          '--strict-mcp-config','--mcp-config',$mcpFile,'--model',$Model,
          '--disallowedTools','Bash','PowerShell')
if ($useNode) { $fileName = $nodeCmd.Source; $allArgs = @($pkgBin) + $args; $cliDesc = $fileName + ' ' + $pkgBin }
else { Fail 'node or package entry not found - reinstall @tencent-ai/codebuddy-code' 20 }

if ($DryRun) {
  Write-Host '[bb-run] DRY RUN' -ForegroundColor Yellow
  Write-Host ('  cli    : ' + $cliDesc)
  Write-Host ('  args   : ' + ($allArgs -join ' '))
  Write-Host ('  config : ' + $homeCfg)
  Write-Host ('  gate   : ' + $gateInfo.status)
  Write-Host ('  run    : ' + $runDir)
  exit 0
}

# ---------- run ----------
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $fileName
$psi.Arguments = (($allArgs | ForEach-Object {
  $s = [string]$_
  if ($s -match '[\s"]') { '"' + ($s -replace '"','\"') + '"' } else { $s }
}) -join ' ')
$psi.WorkingDirectory = $WorkDir
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

$startedAt = (Get-Date).ToString('o')
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$status = 'ERROR'; $exitCode = 1; $stdout = ''; $stderr = ''

try {
  $proc.Start() | Out-Null
  # use the exact bytes that were fingerprinted during the gate (no second read)
  $u8 = New-Object System.Text.UTF8Encoding($false)
  $bytes = $PromptBytes
  # Async write: a large prompt into a process that does not read stdin would block
  # forever, and WaitForExit would never be reached (TimeoutSec would be useless).
  try {
    $writeTask = $proc.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length)
    if ($writeTask.Wait(15000)) {
      $proc.StandardInput.BaseStream.Flush()
    }
  } catch { }
  try { $proc.StandardInput.Close() } catch { }

  $outTask = $proc.StandardOutput.ReadToEndAsync()
  $errTask = $proc.StandardError.ReadToEndAsync()

  $finished = $proc.WaitForExit($TimeoutSec * 1000)
  if (-not $finished) {
    try { & taskkill /PID $proc.Id /T /F | Out-Null } catch {}
    try { $proc.WaitForExit(5000) | Out-Null } catch {}
    $status = 'TIMEOUT'; $exitCode = 124
  } else {
    $status = 'EXITED'; $exitCode = $proc.ExitCode
  }
  if ($outTask.Wait(10000)) { $stdout = $outTask.Result }
  if ($errTask.Wait(10000)) { $stderr = $errTask.Result }
} catch {
  # keep the real exit code when the pipe dies (CLI exits before reading stdin)
  if ($proc -and $proc.HasExited) {
    try { $exitCode = $proc.ExitCode } catch { $exitCode = 1 }
    $status = 'EXITED'
  } else {
    $status = 'ERROR'; $exitCode = 1
  }
  $stderr = $_.Exception.Message
}
$sw.Stop()
[System.IO.File]::WriteAllText($logPath, ($stdout + "`n--- stderr ---`n" + $stderr), (New-Object System.Text.UTF8Encoding($false)))

# ---------- verify ledger (wrapper computes hashes; the agent never has to) ----------
$verified = @(); $done = 0; $failed = 0; $missing = 0; $hashMismatch = 0
$ids = @()
if (Test-Path -LiteralPath $ProgressPath) {
  foreach ($l in (Get-Content -LiteralPath $ProgressPath -Encoding UTF8 | Where-Object { $_ -match '^\d' })) {
    $f = $l -split '\|'
    if ($f.Count -lt 3) { continue }
    if ($f[1] -eq 'done') { $done++ }
    if ($f[1] -eq 'failed') { $failed++ }
    if ($f[0] -match '^\d+$') { $ids += [int]$f[0] }
    $p = $f[2]
    if (-not $p) { continue }
    if (Test-Path -LiteralPath $p) {
      $fi = Get-Item -LiteralPath $p
      $real = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
      $entry = [ordered]@{ id=$f[0]; status=$f[1]; path=$p; exists=$true; bytes=$fi.Length; sha256=$real }
      # compare only when the agent declared a real hash (8 or 64 hex chars).
      # Anything else (empty, "-", "00000000", "n/a", prose) is skipped: the agent
      # has no shell and cannot compute one, and a placeholder must not fake a mismatch.
      $declared = ''
      if ($f.Count -ge 5) { $declared = $f[4].Trim().ToLower() }
      if ($declared -match '^[0-9a-f]{8}$') {
        if ($real.Substring(0,8) -ne $declared) { $hashMismatch++; $entry.declared_mismatch = $true }
      } elseif ($declared -match '^[0-9a-f]{64}$') {
        if ($real -ne $declared) { $hashMismatch++; $entry.declared_mismatch = $true }
      }
      $verified += $entry
    } else {
      $missing++
      $verified += [ordered]@{ id=$f[0]; status=$f[1]; path=$p; exists=$false; bytes=0; sha256='' }
    }
  }
}

# numbering continuity: 1..max(id), guarded against date-like ids.
# NOTE: max must be taken from ALL ids first - filtering before the max made the
# guard unreachable (gaps_skipped was permanently false).
$gaps = 0
$gapsSkipped = $false
$maxId = 0
if ($ids.Count -gt 0) { $maxId = ($ids | Measure-Object -Maximum).Maximum }
if ($maxId -gt 100000) {
  $gapsSkipped = $true
} elseif ($maxId -ge 1) {
  $seen = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($i in $ids) { if ($i -ge 1 -and $i -le $maxId) { [void]$seen.Add($i) } }
  for ($k = 1; $k -le $maxId; $k++) { if (-not $seen.Contains($k)) { $gaps++ } }
}

$tail = @()
if (Test-Path -LiteralPath $logPath) { $tail = Get-Content -LiteralPath $logPath -Tail 20 -Encoding UTF8 }

# decide rollback BEFORE writing COMPLETION, so the record tells the truth.
# A fast non-zero exit is NOT proof of "no work": the agent may have written products
# and a ledger, then failed one criterion. Only roll back when nothing was left behind.
$claimRollback = $false
if ($gateInfo.claimed) {
  $didWork = (($done + $failed) -gt 0) -or (@($verified | Where-Object { $_.exists }).Count -gt 0)
  $fastFail = ($status -eq 'EXITED' -and $exitCode -ne 0 -and $sw.Elapsed.TotalSeconds -lt 30 -and -not $didWork)
  if ($status -eq 'ERROR' -or $fastFail) { $claimRollback = $true }
}

$completion = [ordered]@{
  run_id = $runId; status = $status; exit_code = $exitCode
  started_at = $startedAt; finished_at = (Get-Date).ToString('o')
  duration_sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  effort = $Effort; model = $Model; max_turns = $MaxTurns
  gate = $gateInfo.status
  claim_rolled_back = $claimRollback
  ledger = [ordered]@{ done=$done; failed=$failed; missing_files=$missing; hash_mismatch=$hashMismatch; gaps=$gaps; gaps_skipped=$gapsSkipped }
  verified = $verified
  log_path = $logPath
  log_tail = ($tail -join "`n")
}
WriteJson $completionPath $completion

# rollback the claim when the CLI did no real work (see $claimRollback above)
if ($claimRollback) {
  $mdBack = Get-Content -LiteralPath $ApprovePath -Raw -Encoding UTF8
  $mdBack = [regex]::Replace($mdBack, '(?m)^(\s*[-*]?\s*status\s*:\s*)used', '${1}approved', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  [System.IO.File]::WriteAllText($ApprovePath, $mdBack, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host '[bb-run] approval rolled back to approved (the CLI did no real work)' -ForegroundColor Yellow
}

foreach ($k in $backup.Keys) { [System.Environment]::SetEnvironmentVariable($k, $backup[$k]) }

Write-Host ('[bb-run] ' + $status + ' exit=' + $exitCode + ' in ' + $completion.duration_sec + 's') -ForegroundColor Green
Write-Host ('  ledger  : done=' + $done + ' failed=' + $failed + ' missing=' + $missing + ' hash_mismatch=' + $hashMismatch + ' gaps=' + $gaps)
Write-Host ('  run dir : ' + $runDir)
exit $exitCode
