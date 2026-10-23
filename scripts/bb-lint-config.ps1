# bb-lint-config.ps1 - Static assertions for BuddyBridge guard config
# Usage: powershell -ExecutionPolicy Bypass -File bb-lint-config.ps1 [-Repo <path>]
# Exit 0 = all checks pass; exit 1 = at least one FAIL

[CmdletBinding()]
param([string]$Repo = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$fail = 0
$pass = 0

function Check($name, $cond, $detail) {
  if ($cond) {
    $script:pass++
    Write-Host ('PASS  ' + $name) -ForegroundColor Green
  } else {
    $script:fail++
    Write-Host ('FAIL  ' + $name + '  -> ' + $detail) -ForegroundColor Red
  }
}

$winCfg = Join-Path $Repo 'install\settings.windows.json'
$macCfg = Join-Path $Repo 'install\settings.macos.json'

# 1. files exist and parse
Check 'windows settings exists' (Test-Path -LiteralPath $winCfg) $winCfg
Check 'macos settings exists' (Test-Path -LiteralPath $macCfg) $macCfg

$win = $null
try { $win = Get-Content -LiteralPath $winCfg -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
Check 'windows settings is valid JSON' ($null -ne $win) 'parse failed'

if ($win) {
  $deny = @($win.permissions.deny)

  # 2. no broad interpreter allow rules
  $badAllow = @($deny | Where-Object { $_ -match '^Bash\((node|python):\*\)$' })
  Check 'no Bash(node:*)/Bash(python:*) deny-only leftovers' ($badAllow.Count -eq 0) ($badAllow -join ', ')
  $allowList = @()
  if ($win.permissions.allow) { $allowList = @($win.permissions.allow) }
  $broad = @($allowList | Where-Object { $_ -match '^Bash\((node|python):\*\)$' })
  Check 'no broad interpreter allow rules' ($broad.Count -eq 0) ($broad -join ', ')

  # 3. every dangerous cmdlet must have both exact and prefix forms
  $cmds = @('Remove-Item','rd','del','rmdir','takeown','icacls','Set-ExecutionPolicy','iex','Invoke-Expression','iwr','Invoke-WebRequest','Invoke-RestMethod','schtasks','reg','Stop-Process','Start-Process','Format-Volume','diskpart','cmd','wsl','bash','Set-Content','Out-File','Add-Content','Copy-Item','Move-Item')
  $missing = @()
  foreach ($c in $cmds) {
    if ($deny -notcontains ('PowerShell(' + $c + ':*)')) { $missing += ($c + ':*)') }
  }
  Check 'all PowerShell cmdlets have prefix deny' ($missing.Count -eq 0) ($missing -join ', ')

  # 4. critical Bash rules still present
  $mustBash = @('Bash(rm -rf:*)','Bash(sudo:*)','Bash(curl:*)','Bash(git push:*)','Bash(powershell:*)','Bash(node -e:*)','Bash(python -c:*)')
  $missBash = @($mustBash | Where-Object { $deny -notcontains $_ })
  Check 'critical Bash denies present' ($missBash.Count -eq 0) ($missBash -join ', ')

  # 5. approval file protected
  Check 'APPROVED.json edit protected' ($deny -contains 'Edit(APPROVED.json)') 'missing Edit(APPROVED.json)'

  # 6. no defaultMode auto (ignored under -y / overridden project-level)
  $mode = $win.permissions.defaultMode
  Check 'windows defaultMode is not auto' ($mode -ne 'auto') ('defaultMode=' + $mode)
}

# 7. hooks scripts referenced by templates/skill exist
$hookDir = Join-Path $Repo 'hooks'
foreach ($h in @('bb-heartbeat.sh','bb-stop.sh')) {
  Check ('hook exists: ' + $h) (Test-Path -LiteralPath (Join-Path $hookDir $h)) 'missing file'
}

# 8. wrapper scripts exist
foreach ($s in @('bb-run.ps1','bb-approve.ps1','bb-watch.ps1')) {
  Check ('script exists: ' + $s) (Test-Path -LiteralPath (Join-Path $Repo ('scripts\' + $s))) 'missing file'
}

Write-Host ''
Write-Host ('RESULT: ' + $pass + ' pass / ' + $fail + ' fail')
if ($fail -gt 0) { exit 1 } else { exit 0 }
