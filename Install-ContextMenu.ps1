# Registers Explorer context menu for .epf / .erf (HKCU, no admin).
# Platform version is chosen later, on each unpack run (one window for multi-select).
$ErrorActionPreference = "Stop"

$ToolDir = $PSScriptRoot
if (-not $ToolDir) {
    $ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

. (Join-Path $ToolDir "PlatformUtils.ps1")

$vbs = Join-Path $ToolDir "Enqueue-Hidden.vbs"
if (-not (Test-Path -LiteralPath $vbs)) {
    throw "Launcher not found: $vbs"
}

$menu = "1C Unpack To Files"
# wscript //B runs without UI; VBS starts PowerShell fully hidden (no console flash on multi-select).
$command = 'wscript.exe //nologo //B "{0}" "%1"' -f $vbs

$platforms = @(Get-Installed1CPlatforms)
$icon = $null
if ($platforms.Count -gt 0) {
    $icon = '{0},0' -f $platforms[0].Path
}

$keys = @(
    "HKCU:\Software\Classes\SystemFileAssociations\.epf\shell\DumpEpfErfToUnPacked",
    "HKCU:\Software\Classes\SystemFileAssociations\.erf\shell\DumpEpfErfToUnPacked"
)

foreach ($key in $keys) {
    New-Item -Path $key -Force | Out-Null
    New-Item -Path (Join-Path $key "command") -Force | Out-Null
    Set-ItemProperty -LiteralPath $key -Name "(default)" -Value $menu
    Set-ItemProperty -LiteralPath $key -Name "MultiSelectModel" -Value "Player"
    if ($icon) {
        Set-ItemProperty -LiteralPath $key -Name "Icon" -Value $icon
    } else {
        Remove-ItemProperty -LiteralPath $key -Name "Icon" -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -LiteralPath (Join-Path $key "command") -Name "(default)" -Value $command
}

Clear-1CPlatformConfig -ToolDir $ToolDir | Out-Null

Write-Host "Installed: $menu"
Write-Host "Command : $command"
if ($icon) {
    Write-Host "Icon    : $icon"
} else {
    Write-Host "Icon    : 1cv8.exe not found (menu without icon)"
}
Write-Host "Multi-select opens a single unpack window (no flash)."
Write-Host "Platform version is asked on each unpack."
Write-Host "Select one or more .epf/.erf -> right click -> $menu"
Write-Host "Each file dumps to sibling folder <Name.ext>__UnPacked"
