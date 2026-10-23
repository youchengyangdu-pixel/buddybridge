# bb-watch.ps1 - Watch a dispatched run and print state changes (desktop side)
# Usage:
#   powershell -ExecutionPolicy Bypass -File bb-watch.ps1 -WorkDir <dir> [-IntervalSec 15] [-Once]
# State machine (single source of truth):
#   COMPLETION exists, exit=0, done>=N  -> DONE
#   COMPLETION exists, exit!=0          -> FAILED
#   COMPLETION exists, exit=0, done<N   -> INCOMPLETE
#   no COMPLETION, STOP exists, 30s idle-> UNKNOWN
#   progress idle > 30min               -> STALLED
#   progress idle > 10min               -> SUSPECT
#   otherwise                           -> RUNNING

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$WorkDir,
  [int]$IntervalSec = 15,
  [switch]$Once,
  [int]$ExpectedItems = 0
)

$ErrorActionPreference = 'Continue'

function Read-JsonFile($p) {
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-State($workDir) {
  $bb = Join-Path $workDir '.buddybridge'
  $latest = Read-JsonFile (Join-Path $bb 'LATEST.json')
  if (-not $latest) { return [pscustomobject]@{ state = 'NORUN'; detail = 'no LATEST.json'; run = '' } }

  $runDir = $latest.run_dir
  $run = $latest.run_id
  $comp = Read-JsonFile (Join-Path $runDir 'COMPLETION.json')
  $stop = Read-JsonFile (Join-Path $runDir 'STOP.json')
  $progress = Join-Path $workDir 'PROGRESS.md'

  if ($comp) {
    $done = 0; if ($comp.ledger) { $done = [int]$comp.ledger.done }
    $status = [string]$comp.status
    $exit = [int]$comp.exit_code
    if ($status -eq 'TIMEOUT') { return [pscustomobject]@{ state='STALLED'; detail='timeout after ' + $comp.duration_sec + 's (exit 124)'; run=$run } }
    if ($exit -ne 0) { return [pscustomobject]@{ state='FAILED'; detail='exit=' + $exit + ' duration=' + $comp.duration_sec + 's'; run=$run } }
    if ($ExpectedItems -gt 0 -and $done -lt $ExpectedItems) {
      return [pscustomobject]@{ state='INCOMPLETE'; detail=('done=' + $done + '/' + $ExpectedItems); run=$run }
    }
    return [pscustomobject]@{ state='DONE'; detail=('exit=0 done=' + $done + ' duration=' + $comp.duration_sec + 's'); run=$run }
  }

  if ($stop) {
    $st = if ($stop.at) { [DateTimeOffset]::Parse($stop.at) } else { [DateTimeOffset]::Now }
    $idle = ([DateTimeOffset]::Now - $st).TotalSeconds
    if ($idle -gt 30) { return [pscustomobject]@{ state='UNKNOWN'; detail='STOP written but no COMPLETION (' + [int]$idle + 's idle)'; run=$run } }
  }

  if (Test-Path -LiteralPath $progress) {
    $idleMin = ((Get-Date) - (Get-Item -LiteralPath $progress).LastWriteTime).TotalMinutes
    if ($idleMin -gt 30) { return [pscustomobject]@{ state='STALLED'; detail=('progress idle ' + [int]$idleMin + ' min'); run=$run } }
    if ($idleMin -gt 10) { return [pscustomobject]@{ state='SUSPECT'; detail=('progress idle ' + [int]$idleMin + ' min'); run=$run } }
  }

  return [pscustomobject]@{ state='RUNNING'; detail='started ' + $latest.updated_at; run=$run }
}

$last = ''
$lastSeq = -1
while ($true) {
  $s = Get-State $WorkDir
  $bb = Join-Path $WorkDir '.buddybridge'
  $latest = Read-JsonFile (Join-Path $bb 'LATEST.json')
  $seq = -1
  $progressCount = 0
  if ($latest -and $latest.run_dir) {
    $hb = Read-JsonFile (Join-Path $latest.run_dir 'HEARTBEAT.json')
    if ($hb) { $seq = [int]$hb.seq }
  }
  $progress = Join-Path $WorkDir 'PROGRESS.md'
  if (Test-Path -LiteralPath $progress) {
    $progressCount = @(Get-Content -LiteralPath $progress -Encoding UTF8 | Where-Object { $_ -match '^\d' }).Count
  }

  $key = $s.state + '|' + $progressCount + '|' + $seq
  if ($key -ne $last) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host ('[' + $ts + '] ' + $s.state.PadRight(10) + ' ' + $s.detail + '  (ledger=' + $progressCount + ' hb=' + $seq + ')')
    $last = $key
  }

  if ($Once) { break }
  if ($s.state -in @('DONE','FAILED','STALLED','INCOMPLETE','UNKNOWN')) { break }
  Start-Sleep -Seconds $IntervalSec
}
