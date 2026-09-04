# Removes Explorer context menu for unpack (.epf/.erf) and pack (*__UnPacked folders).
$ErrorActionPreference = "Continue"

$ToolDir = $PSScriptRoot
if (-not $ToolDir) {
    $ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

. (Join-Path $ToolDir "PlatformUtils.ps1")

$keys = @(
    "HKCU:\Software\Classes\SystemFileAssociations\.epf\shell\DumpEpfErfToUnPacked",
    "HKCU:\Software\Classes\SystemFileAssociations\.erf\shell\DumpEpfErfToUnPacked",
    "HKCU:\Software\Classes\Directory\shell\PackEpfErfFromUnPacked",
    "HKCU:\Software\Classes\Folder\shell\PackEpfErfFromUnPacked",
    "HKCU:\Software\Classes\Directory\Background\shell\PackEpfErfFromUnPacked"
)

foreach ($key in $keys) {
    if (Test-Path -LiteralPath $key) {
        Remove-Item -LiteralPath $key -Recurse -Force
        Write-Host "Removed: $key"
    }
}

Clear-1CPlatformConfig -ToolDir $ToolDir | Out-Null
Write-Host "Done."
