<#
.SYNOPSIS
    Launch Ralph in the background with no visible window.
.DESCRIPTION
    Starts ralph.ps1 as a hidden background process. All output goes to
    .ralph-logs/ directory. Use ralph-status.ps1 to check progress.
.EXAMPLE
    .\ralph-headless.ps1
    .\ralph-headless.ps1 -MaxIterations 50 -MaxTurns 100
#>

param(
    [int]$MaxIterations = 120,
    [int]$MaxTurns = 75,
    [int]$Delay = 10,
    [switch]$StopOnFail
)

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RalphScript = Join-Path $ProjectDir "ralph.ps1"
$LogDir = Join-Path $ProjectDir ".ralph-logs"
$SessionLog = Join-Path $LogDir "ralph-session_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

$stopOnFailArg = if ($StopOnFail) { "-StopOnFail" } else { "" }

$argList = "-NoProfile -ExecutionPolicy Bypass -File `"$RalphScript`" -MaxIterations $MaxIterations -MaxTurns $MaxTurns -Delay $Delay $stopOnFailArg"

$process = Start-Process powershell.exe `
    -ArgumentList $argList `
    -WindowStyle Hidden `
    -RedirectStandardOutput $SessionLog `
    -RedirectStandardError (Join-Path $LogDir "ralph-session-errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').log") `
    -PassThru

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RALPH - Running Headless" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PID:        $($process.Id)" -ForegroundColor White
Write-Host "  Session log: $SessionLog" -ForegroundColor DarkGray
Write-Host "  Per-story logs: $LogDir" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  To follow progress:" -ForegroundColor Yellow
Write-Host "    Get-Content `"$SessionLog`" -Wait" -ForegroundColor White
Write-Host ""
Write-Host "  To stop:" -ForegroundColor Yellow
Write-Host "    Stop-Process -Id $($process.Id)" -ForegroundColor White
Write-Host ""

# Save PID for easy stopping
$process.Id | Out-File (Join-Path $LogDir "ralph.pid") -Encoding UTF8
