<#
.SYNOPSIS
    Run a list of spritesheet extraction commands from a text file, one by one.
.DESCRIPTION
    Reads a .txt file where each non-blank, non-comment line is a
    complete extract_spritesheets.ps1 invocation.
    Commands are run sequentially; progress and timing are shown per command.
    The working directory is set to the folder containing the command file so
    that relative paths inside the commands resolve correctly.

.PARAMETER CommandFile
    Path to the .txt file containing one command per line.
    Blank lines and lines starting with # are skipped.

.PARAMETER StopOnError
    Stop immediately after the first failed command.
    Default: continue running remaining commands and report failures at the end.

.EXAMPLE
    .\run_spritesheet_batch.ps1 -CommandFile commands.txt
    .\run_spritesheet_batch.ps1 -CommandFile commands.txt -StopOnError
#>
param(
    [Parameter(Mandatory)][string]$CommandFile,
    [switch]$StopOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolved   = Resolve-Path $CommandFile
$workingDir = Split-Path $resolved -Parent

# Read, strip blanks and comments.
$commands = @(Get-Content -Path $resolved |
    Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*[#<]' })

if ($commands.Count -eq 0) {
    Write-Host "No commands found in $resolved" -ForegroundColor Yellow
    exit 0
}

$total    = $commands.Count
$failures = [System.Collections.Generic.List[int]]::new()
$wallClock = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "Batch: $total command(s) from $(Split-Path $resolved -Leaf)"
Write-Host "Working directory: $workingDir"
Write-Host ""

Push-Location $workingDir
try {
    for ($i = 0; $i -lt $total; $i++) {
        $cmd   = $commands[$i]
        $label = "[$($i + 1)/$total]"
        $sw    = [System.Diagnostics.Stopwatch]::StartNew()

        Write-Host ('-' * 60) -ForegroundColor Cyan
        Write-Host "$label  $cmd" -ForegroundColor DarkCyan
        Write-Host ""

        Invoke-Expression $cmd
        $exit = $LASTEXITCODE

        $sw.Stop()
        $elapsed = '{0}m {1}s' -f [math]::Floor($sw.Elapsed.TotalMinutes), $sw.Elapsed.Seconds

        Write-Host ""
        if ($exit -eq 0 -or $null -eq $exit) {
            Write-Host "$label  OK  ($elapsed)" -ForegroundColor Green
        } else {
            Write-Host "$label  FAILED (exit $exit)  ($elapsed)" -ForegroundColor Red
            $failures.Add($i + 1)
            if ($StopOnError) {
                Write-Host "Stopping due to -StopOnError." -ForegroundColor Red
                exit 1
            }
        }
        Write-Host ""
    }
} finally {
    Pop-Location
}

$wallClock.Stop()
$wallElapsed = '{0}m {1}s' -f [math]::Floor($wallClock.Elapsed.TotalMinutes), $wallClock.Elapsed.Seconds

Write-Host ('=' * 60) -ForegroundColor Cyan
if ($failures.Count -eq 0) {
    Write-Host "All $total command(s) succeeded.  Total: $wallElapsed" -ForegroundColor Green
} else {
    Write-Host "$($failures.Count)/$total failed (commands $($failures -join ', ')).  Total: $wallElapsed" -ForegroundColor Yellow
    exit 1
}
