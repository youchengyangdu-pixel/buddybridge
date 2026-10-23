# skill-install.ps1 - Install the buddybridge skill for WorkBuddy
# Usage:
#   powershell -ExecutionPolicy Bypass -File skill-install.ps1 [-Mode copy|link] [-Target <skills dir>]
# Default target: $HOME\.workbuddy\skills\buddybridge
# Writes SKILL.md + REPO.txt (repo root) + VERSION (sha256 of SKILL.md, 12 chars)

[CmdletBinding()]
param(
  [ValidateSet('copy','link')][string]$Mode = 'copy',
  [string]$Target = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$srcSkill = Join-Path $repo 'skill\buddybridge\SKILL.md'
if (-not (Test-Path -LiteralPath $srcSkill)) { Write-Error ('SKILL.md not found: ' + $srcSkill); exit 2 }

if ($Target -eq '') { $Target = Join-Path $HOME '.workbuddy\skills\buddybridge' }
New-Item -ItemType Directory -Force -Path $Target | Out-Null

if ($Mode -eq 'link') {
  # Windows symlink needs Developer Mode or admin; fall back with a clear message
  $dest = Join-Path $Target 'SKILL.md'
  if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
  try {
    New-Item -ItemType SymbolicLink -Path $dest -Target $srcSkill | Out-Null
    Write-Host '[skill-install] linked SKILL.md' -ForegroundColor Green
  } catch {
    Write-Host '[skill-install] symlink failed (Developer Mode off?) - falling back to copy' -ForegroundColor Yellow
    Copy-Item -LiteralPath $srcSkill -Destination $dest -Force
  }
} else {
  Copy-Item -LiteralPath $srcSkill -Destination (Join-Path $Target 'SKILL.md') -Force
  Write-Host '[skill-install] copied SKILL.md' -ForegroundColor Green
}

# repo root pointer (SKILL.md path resolution)
[System.IO.File]::WriteAllText((Join-Path $Target 'REPO.txt'), $repo, (New-Object System.Text.UTF8Encoding($false)))

# version fingerprint (drift detection)
$sha = (Get-FileHash -LiteralPath $srcSkill -Algorithm SHA256).Hash.ToLower().Substring(0, 12)
[System.IO.File]::WriteAllText((Join-Path $Target 'VERSION'), $sha, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ('  target : ' + $Target)
Write-Host ('  repo   : ' + $repo)
Write-Host ('  version: ' + $sha)
Write-Host ''
Write-Host 'Restart WorkBuddy (or start a new session) for the skill to load.' -ForegroundColor Yellow
