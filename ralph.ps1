#Requires -Version 5.1
<#
.SYNOPSIS
    Ralph — Autonomous build loop for Wellvo using Claude Code CLI.
.DESCRIPTION
    Reads prd.json, finds the next incomplete user story, sends ralph-prompt.md
    to Claude Code in non-interactive mode, and loops until all stories pass.
.EXAMPLE
    .\ralph.ps1
    .\ralph.ps1 -MaxIterations 50
    .\ralph.ps1 -MaxTurns 100 -Delay 30
    .\ralph.ps1 -StopOnFail
#>

param(
    [int]$MaxIterations = 120,
    [int]$MaxTurns = 75,
    [int]$Delay = 10,
    [switch]$StopOnFail
)

$ErrorActionPreference = "Continue"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PrdFile = Join-Path $ProjectDir "prd.json"
$ProgressFile = Join-Path $ProjectDir "progress.txt"
$PromptFile = Join-Path $ProjectDir "ralph-prompt.md"
$LogDir = Join-Path $ProjectDir ".ralph-logs"

# -- Banner ----------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RALPH - Wellvo Autonomous Build Loop" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# -- Pre-flight checks -----------------------------------------------------
$missing = @()
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { $missing += "claude" }
if (-not (Get-Command git -ErrorAction SilentlyContinue))    { $missing += "git" }
if ($missing.Count -gt 0) {
    Write-Host "ERROR: Missing required tools: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

foreach ($f in @($PrdFile, $PromptFile)) {
    if (-not (Test-Path $f)) {
        Write-Host "ERROR: Required file missing: $f" -ForegroundColor Red
        exit 1
    }
}

# Create log directory
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# -- Helper functions -------------------------------------------------------

function Get-PrdData {
    Get-Content $PrdFile -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-RemainingCount {
    $data = Get-PrdData
    ($data.userStories | Where-Object { $_.passes -eq $false }).Count
}

function Get-TotalCount {
    $data = Get-PrdData
    $data.userStories.Count
}

function Get-NextStory {
    $data = Get-PrdData
    $next = $data.userStories |
        Where-Object { $_.passes -eq $false } |
        Sort-Object { $_.priority } |
        Select-Object -First 1
    return $next
}

# -- Show configuration ----------------------------------------------------
$total = Get-TotalCount
$remaining = Get-RemainingCount
$completed = $total - $remaining

Write-Host "  Max iterations:  $MaxIterations"
Write-Host "  Max turns/story: $MaxTurns"
Write-Host "  Delay between:   ${Delay}s"
Write-Host "  Stop on fail:    $StopOnFail"
Write-Host ""
Write-Host "  Stories: " -NoNewline
Write-Host "$completed" -ForegroundColor Green -NoNewline
Write-Host " done / " -NoNewline
Write-Host "$remaining" -ForegroundColor Yellow -NoNewline
Write-Host " remaining / $total total"
Write-Host ""

if ($remaining -eq 0) {
    Write-Host "All stories are already complete! Nothing to do." -ForegroundColor Green
    exit 0
}

Write-Host "Starting Ralph loop in 5 seconds... (Ctrl+C to cancel)" -ForegroundColor Yellow
Start-Sleep -Seconds 5
Write-Host ""

# -- Main loop --------------------------------------------------------------
$iteration = 0

Push-Location $ProjectDir
try {
    while ($iteration -lt $MaxIterations) {
        $iteration++
        $story = Get-NextStory

        if ($null -eq $story) {
            Write-Host ""
            Write-Host "============================================" -ForegroundColor Green
            Write-Host "  ALL STORIES COMPLETE!" -ForegroundColor Green
            Write-Host "  Total iterations: $iteration" -ForegroundColor Green
            Write-Host "============================================" -ForegroundColor Green
            break
        }

        $storyId = $story.id
        $storyTitle = $story.title
        $remaining = Get-RemainingCount
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logFile = Join-Path $LogDir "${storyId}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        Write-Host "--------------------------------------------" -ForegroundColor DarkCyan
        Write-Host "  Iteration $iteration | " -NoNewline -ForegroundColor White
        Write-Host "$storyId" -NoNewline -ForegroundColor Cyan
        Write-Host ": $storyTitle" -ForegroundColor White
        Write-Host "  Remaining: $remaining | Started: $timestamp" -ForegroundColor DarkGray
        Write-Host "  Log: $logFile" -ForegroundColor DarkGray
        Write-Host "--------------------------------------------" -ForegroundColor DarkCyan
        Write-Host ""

        # Read the prompt
        $prompt = Get-Content $PromptFile -Raw -Encoding UTF8

        # Run Claude Code in non-interactive mode
        # -p: print mode (non-interactive, exits after completion)
        # --max-turns: limit context usage per story
        # --dangerously-skip-permissions: required for headless/unattended runs
        $claudeArgs = @("-p", $prompt, "--max-turns", $MaxTurns, "--verbose", "--dangerously-skip-permissions")

        try {
            # Capture all output, then write to both log file and console
            $output = claude @claudeArgs 2>&1 | Out-String
            $exitCode = $LASTEXITCODE

            # Write full output to per-story log as UTF-8 (no BOM)
            [System.IO.File]::WriteAllText($logFile, $output, [System.Text.UTF8Encoding]::new($false))

            # Echo to console (which the headless launcher captures to session log)
            Write-Host $output
        }
        catch {
            Write-Host "ERROR: Claude invocation failed: $_" -ForegroundColor Red
            "ERROR: Claude invocation failed: $_" | Out-File -FilePath $logFile -Encoding UTF8
            $exitCode = 1
        }

        # Check result
        if ($exitCode -ne 0) {
            Write-Host ""
            Write-Host "WARNING: Claude exited with code $exitCode for $storyId" -ForegroundColor Yellow
            if ($StopOnFail) {
                Write-Host "Stopping (--StopOnFail is set)." -ForegroundColor Red
                exit 1
            }
            Write-Host "Continuing to next iteration..." -ForegroundColor Yellow
        }

        # Check if story was marked complete
        $nextStory = Get-NextStory
        if ($null -ne $nextStory -and $nextStory.id -eq $storyId) {
            Write-Host ""
            Write-Host "NOTE: $storyId was NOT marked as complete." -ForegroundColor Yellow
            Write-Host "Check log for details. Re-attempting next iteration..." -ForegroundColor Yellow
        }
        else {
            Write-Host ""
            Write-Host "OK $storyId completed successfully." -ForegroundColor Green
        }

        # Pause between iterations
        if ($iteration -lt $MaxIterations) {
            $nextStory = Get-NextStory
            if ($null -ne $nextStory) {
                Write-Host "Next: $($nextStory.id) - $($nextStory.title)" -ForegroundColor DarkGray
                Write-Host "Pausing ${Delay}s..." -ForegroundColor DarkGray
                Start-Sleep -Seconds $Delay
            }
        }

        Write-Host ""
    }
}
finally {
    Pop-Location
}

# -- Summary ----------------------------------------------------------------
$remaining = Get-RemainingCount
$total = Get-TotalCount
$completed = $total - $remaining

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Ralph Session Complete" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Completed: $completed / $total stories" -ForegroundColor White
Write-Host "  Iterations: $iteration" -ForegroundColor White
Write-Host "  Logs: $LogDir" -ForegroundColor DarkGray
Write-Host "============================================" -ForegroundColor Cyan
