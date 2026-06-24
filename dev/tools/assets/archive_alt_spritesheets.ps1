<#
.SYNOPSIS
    Move all _altN spritesheet variants out of Spritesheets into SpritesheetsAlts.
.DESCRIPTION
    Scans the source folder recursively for files matching *_alt*_spritesheet.png
    and moves them to a sibling folder (SpritesheetsAlts by default), preserving
    the subdirectory structure.

    Source:      resources\img\spritesheets\camera\coopallbehind_alt2_spritesheet.png
    Destination: resources\img\spritesheets alts\camera\coopallbehind_alt2_spritesheet.png

.PARAMETER Source
    The Spritesheets folder to read from.  Defaults to .\resources\img\Spritesheets
.PARAMETER Dest
    The folder to move alts into.  Defaults to .\resources\img\SpritesheetsAlts
.PARAMETER WhatIf
    Preview only — show what would be moved without changing anything.

.EXAMPLE
    .\archive_alt_spritesheets.ps1 -WhatIf
    .\archive_alt_spritesheets.ps1
#>
param(
    [string]$Source = (Join-Path $PSScriptRoot '..\..\..\resources\img\spritesheets'),
    [string]$Dest   = (Join-Path $PSScriptRoot '..\..\..\resources\img\spritesheets alts'),
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedSrc  = (Resolve-Path $Source).Path
$resolvedDest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Dest)

$alts = @(Get-ChildItem -Path $resolvedSrc -Recurse -Filter '*_spritesheet.*' |
    Where-Object { $_.Extension -in @('.png', '.jpg') -and
                   $_.Name -match '_alt\d+(?:_f\d+)?_spritesheet\.(png|jpg)$|_near(?:_f\d+)?_spritesheet\.(png|jpg)$' })

if ($alts.Count -eq 0) {
    Write-Host 'No alt spritesheet files found.' -ForegroundColor Yellow
    exit 0
}

$totalMoved = 0

foreach ($file in ($alts | Sort-Object FullName)) {
    # Derive the relative path under Source and mirror it under Dest.
    $rel     = $file.FullName.Substring($resolvedSrc.Length).TrimStart('\/')
    $dstPath = Join-Path $resolvedDest $rel
    $dstDir  = Split-Path $dstPath -Parent

    if ($WhatIf) {
        Write-Host ("  {0}" -f $rel)
    } else {
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Move-Item -Path $file.FullName -Destination $dstPath
        Write-Host ("  {0}" -f $rel)
    }
    $totalMoved++
}

Write-Host ''
if ($WhatIf) {
    Write-Host "$totalMoved file(s) would be moved to $resolvedDest  (re-run without -WhatIf to apply)." -ForegroundColor Yellow
} else {
    Write-Host "$totalMoved file(s) moved to $resolvedDest" -ForegroundColor Green
}
