# Removes Explorer context menu for .epf / .erf.
$ErrorActionPreference = "Continue"

$ToolDir = $PSScriptRoot
if (-not $ToolDir) {
    $ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

. (Join-Path $ToolDir "PlatformUtils.ps1")

$keys = @(
    "HKCU:\Software\Classes\SystemFileAssociations\.epf\shell\DumpEpfErfToUnPacked",
    "HKCU:\Software\Classes\SystemFileAssociations\.erf\shell\DumpEpfErfToUnPacked"
)

foreach ($key in $keys) {
    if (Test-Path -LiteralPath $key) {
        Remove-Item -LiteralPath $key -Recurse -Force
        Write-Host "Removed: $key"
    }
}

Clear-1CPlatformConfig -ToolDir $ToolDir | Out-Null
Write-Host "Done."
