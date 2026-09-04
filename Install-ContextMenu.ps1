# Registers Explorer context menu for unpack (.epf/.erf) and pack (*__UnPacked folders).
# HKCU, no admin. Platform version is chosen later, on each run (one window for multi-select).
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

$packPs1 = Join-Path $ToolDir "Pack-ExternalFromFiles.ps1"
if (-not (Test-Path -LiteralPath $packPs1)) {
    throw "Pack script not found: $packPs1"
}

$unpackMenu = "1C Unpack To Files"
$packMenu = "1C Pack To File"
# wscript //B runs without UI; VBS starts PowerShell fully hidden (no console flash on multi-select).
$unpackCommand = 'wscript.exe //nologo //B "{0}" "%1"' -f $vbs
$packCommand = 'wscript.exe //nologo //B "{0}" pack "%1"' -f $vbs
$packBackgroundCommand = 'wscript.exe //nologo //B "{0}" pack "%V"' -f $vbs
# "~<" (ends with) is ignored/invalid for Directory verbs and hides the item.
# "~=" (contains) is the documented AQS form. Script still requires *.epf|erf__UnPacked.
$packAppliesTo = 'System.FileName:~="__UnPacked"'

$platforms = @(Get-Installed1CPlatforms)
$icon = $null
if ($platforms.Count -gt 0) {
    $icon = '{0},0' -f $platforms[0].Path
}

function Set-ExplorerShellVerb {
    param(
        [string]$Key,
        [string]$Menu,
        [string]$Command,
        [string]$Icon,
        [string]$AppliesTo = "",
        [string]$MultiSelectModel = ""
    )

    New-Item -Path $Key -Force | Out-Null
    New-Item -Path (Join-Path $Key "command") -Force | Out-Null
    Set-ItemProperty -LiteralPath $Key -Name "(default)" -Value $Menu
    Set-ItemProperty -LiteralPath $Key -Name "MUIVerb" -Value $Menu
    if ($MultiSelectModel) {
        Set-ItemProperty -LiteralPath $Key -Name "MultiSelectModel" -Value $MultiSelectModel
    } else {
        Remove-ItemProperty -LiteralPath $Key -Name "MultiSelectModel" -ErrorAction SilentlyContinue
    }
    if ($AppliesTo) {
        Set-ItemProperty -LiteralPath $Key -Name "AppliesTo" -Value $AppliesTo
    } else {
        Remove-ItemProperty -LiteralPath $Key -Name "AppliesTo" -ErrorAction SilentlyContinue
    }
    if ($Icon) {
        Set-ItemProperty -LiteralPath $Key -Name "Icon" -Value $Icon
    } else {
        Remove-ItemProperty -LiteralPath $Key -Name "Icon" -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -LiteralPath (Join-Path $Key "command") -Name "(default)" -Value $Command
}

$unpackKeys = @(
    "HKCU:\Software\Classes\SystemFileAssociations\.epf\shell\DumpEpfErfToUnPacked",
    "HKCU:\Software\Classes\SystemFileAssociations\.erf\shell\DumpEpfErfToUnPacked"
)

foreach ($key in $unpackKeys) {
    Set-ExplorerShellVerb -Key $key -Menu $unpackMenu -Command $unpackCommand -Icon $icon -MultiSelectModel "Player"
}

Set-ExplorerShellVerb `
    -Key "HKCU:\Software\Classes\Directory\shell\PackEpfErfFromUnPacked" `
    -Menu $packMenu `
    -Command $packCommand `
    -Icon $icon `
    -AppliesTo $packAppliesTo `
    -MultiSelectModel "Player"

Set-ExplorerShellVerb `
    -Key "HKCU:\Software\Classes\Folder\shell\PackEpfErfFromUnPacked" `
    -Menu $packMenu `
    -Command $packCommand `
    -Icon $icon `
    -AppliesTo $packAppliesTo `
    -MultiSelectModel "Player"

# AppliesTo on Directory\Background hides the verb unconditionally; filter in the script instead.
Set-ExplorerShellVerb `
    -Key "HKCU:\Software\Classes\Directory\Background\shell\PackEpfErfFromUnPacked" `
    -Menu $packMenu `
    -Command $packBackgroundCommand `
    -Icon $icon

Clear-1CPlatformConfig -ToolDir $ToolDir | Out-Null

if (-not ("DumpEpfErf.ShellNotify" -as [type])) {
    Add-Type -Namespace DumpEpfErf -Name ShellNotify -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr dwItem1, System.IntPtr dwItem2);
"@
}
# SHCNE_ASSOCCHANGED: Explorer reloads file/folder verbs without a full restart.
[DumpEpfErf.ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Host "Installed: $unpackMenu"
Write-Host "Command : $unpackCommand"
Write-Host "Installed: $packMenu"
Write-Host "Command : $packCommand"
Write-Host "Background: $packBackgroundCommand"
if ($icon) {
    Write-Host "Icon    : $icon"
} else {
    Write-Host "Icon    : 1cv8.exe not found (menu without icon)"
}
Write-Host "Multi-select opens a single unpack/pack window (no flash)."
Write-Host "Platform version is asked on each run."
Write-Host "Select .epf/.erf -> right click -> $unpackMenu"
Write-Host "Each file dumps to sibling folder <Name.ext>__UnPacked"
Write-Host "Select <Name.ext>__UnPacked folder (or empty space inside) -> $packMenu"
Write-Host "Creates sibling <Name>_Packed.epf/.erf (original file is not overwritten)"
