# Pack selected *__UnPacked folders into sibling <Name>_Packed.epf/.erf
# Usage:
#   Pack-ExternalFromFiles.ps1 -RunBatch <dir1> [dir2] ...
#   Pack-ExternalFromFiles.ps1 -Enqueue <dir>   (context menu; coalesces multi-select into one window)
# Requires 1C/BAF platform. Creates a temporary file IB in %TEMP% and deletes it after pack.
# Original .epf / .erf next to the folder is never overwritten.
# 1C messages are shown in this window (no persistent log files).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Paths = @(),

    [Parameter(Mandatory = $false)]
    [string]$PlatformPath = "",

    [Parameter(Mandatory = $false)]
    [string]$Suffix = "__UnPacked",

    # Context-menu collector: hidden processes enqueue folders; one leader opens a single UI window.
    [switch]$Enqueue,

    # Actual pack worker (one visible window for the whole batch).
    [switch]$RunBatch,

    # Optional folder list for long command lines (one path per line).
    [string]$ListFile = ""
)

if ((-not $Paths -or $Paths.Count -eq 0) -and $args.Count -gt 0) {
    $Paths = @($args)
}

$ErrorActionPreference = "Stop"
$ToolDir = $PSScriptRoot
if (-not $ToolDir) {
    $ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$SelfPs1 = Join-Path $ToolDir "Pack-ExternalFromFiles.ps1"

. (Join-Path $ToolDir "PlatformUtils.ps1")

function Invoke-1CCommand {
    param(
        [string]$OneC,
        [string[]]$ArgumentList
    )

    # 1C writes messages to /Out file only; mirror them to this console, then delete.
    $outFile = Join-Path ([System.IO.Path]::GetTempPath()) ("PackEpfErf_out_" + [guid]::NewGuid().ToString("N") + ".txt")
    $argsWithOut = @($ArgumentList) + @("/Out", "`"$outFile`"")

    try {
        $p = Start-Process -FilePath $OneC -ArgumentList $argsWithOut -Wait -PassThru -NoNewWindow
        if (Test-Path -LiteralPath $outFile) {
            $text = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
            if ($text -and $text.Trim().Length -gt 0) {
                Write-Host $text.TrimEnd()
            }
        }
        return $p.ExitCode
    }
    finally {
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    }
}

function New-TempFileInfobase {
    param([string]$OneC)

    $ibPath = Join-Path ([System.IO.Path]::GetTempPath()) ("PackEpfErf_ib_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $ibPath | Out-Null
    Write-Host "Creating temp IB: $ibPath"

    $exitCode = Invoke-1CCommand -OneC $OneC -ArgumentList @(
        "CREATEINFOBASE",
        "File=`"$ibPath`"",
        "/DisableStartupDialogs"
    )
    if ($exitCode -ne 0) {
        Remove-Item -LiteralPath $ibPath -Recurse -Force -ErrorAction SilentlyContinue
        throw "Failed to create IB (exit $exitCode)."
    }
    return $ibPath
}

function Remove-TempFileInfobase {
    param([string]$Path)

    if (-not $Path) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Write-Host "Removing temp IB: $Path"
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-PackedTargetFromFolder {
    param(
        [System.IO.DirectoryInfo]$Folder,
        [string]$Suffix
    )

    $name = $Folder.Name
    if (-not $name.EndsWith($Suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $originalName = $name.Substring(0, $name.Length - $Suffix.Length)
    $ext = [System.IO.Path]::GetExtension($originalName)
    if ($ext -notmatch '(?i)^\.(epf|erf)$') {
        return $null
    }
    $ext = $ext.ToLowerInvariant()

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($originalName)
    $outName = "{0}_Packed{1}" -f $stem, $ext
    return [pscustomobject]@{
        OriginalName = $originalName
        Extension    = $ext
        OutputPath   = Join-Path $Folder.Parent.FullName $outName
    }
}

function Resolve-UnPackedRootXml {
    param(
        [string]$FolderPath,
        [string]$OriginalName
    )

    $xmls = @(Get-ChildItem -LiteralPath $FolderPath -File -Filter "*.xml" -ErrorAction SilentlyContinue)
    if ($xmls.Count -eq 0) {
        return $null
    }
    if ($xmls.Count -eq 1) {
        return $xmls[0].FullName
    }

    $expectedName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalName) + ".xml"
    $byName = @($xmls | Where-Object { $_.Name -ieq $expectedName })
    if ($byName.Count -eq 1) {
        return $byName[0].FullName
    }

    $byMeta = @()
    foreach ($xml in $xmls) {
        $head = Get-Content -LiteralPath $xml.FullName -TotalCount 40 -ErrorAction SilentlyContinue
        if (-not $head) { continue }
        $text = $head -join "`n"
        if ($text -match "ExternalDataProcessor|ExternalReport") {
            $byMeta += $xml
        }
    }
    if ($byMeta.Count -eq 1) {
        return $byMeta[0].FullName
    }

    return $null
}

function Resolve-InputFolders {
    param([string[]]$RawPaths)

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($raw in $RawPaths) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $item = $raw.Trim('"').TrimEnd("\")
        if (-not (Test-Path -LiteralPath $item)) {
            Write-Warning "Skip (not found): $item"
            continue
        }
        $entry = Get-Item -LiteralPath $item
        if (-not $entry.PSIsContainer) {
            Write-Warning "Skip (not a folder): $($entry.FullName)"
            continue
        }
        $target = Get-PackedTargetFromFolder -Folder $entry -Suffix $Suffix
        if (-not $target) {
            Write-Warning ("Skip (not *.epf{0} / *.erf{0}): {1}" -f $Suffix, $entry.FullName)
            continue
        }
        [void]$result.Add($entry.FullName)
    }
    return @($result | Select-Object -Unique)
}

function Invoke-PackBatch {
    param([string[]]$Folders)

    if (-not $Folders -or $Folders.Count -eq 0) {
        Write-Host "No *__UnPacked folders to process."
        exit 1
    }

    $mutex = $null
    $mutexCreated = $false
    $ibPath = $null
    try {
        $mutex = New-Object System.Threading.Mutex($false, "Global\PackEpfErfFromUnPacked")
        Write-Host "Waiting for pack lock..."
        if (-not $mutex.WaitOne(600000)) {
            throw "Timeout waiting for another pack process (10 min)."
        }
        $mutexCreated = $true

        $OneC = $null
        if ($PlatformPath -and (Test-Path -LiteralPath $PlatformPath)) {
            $OneC = (Resolve-Path -LiteralPath $PlatformPath).Path
        } else {
            $OneC = Select-1CPlatformInteractive -Title "Pack: select 1C platform version"
        }
        if (-not $OneC) {
            Write-Host "Cancelled by user."
            exit 0
        }

        Write-Host "Platform: $OneC"
        Write-Host ("Folders : {0}" -f $Folders.Count)
        $ibPath = New-TempFileInfobase -OneC $OneC

        $failed = @()
        $index = 0
        foreach ($folderPath in $Folders) {
            $index++
            $folder = Get-Item -LiteralPath $folderPath
            $target = Get-PackedTargetFromFolder -Folder $folder -Suffix $Suffix
            if (-not $target) {
                Write-Warning ("Skip (not *.epf{0} / *.erf{0}): {1}" -f $Suffix, $folder.FullName)
                $failed += $folder.FullName
                continue
            }

            $rootXml = Resolve-UnPackedRootXml -FolderPath $folder.FullName -OriginalName $target.OriginalName
            if (-not $rootXml) {
                Write-Warning "No root XML in: $($folder.FullName)"
                $failed += $folder.FullName
                continue
            }

            Write-Host ""
            Write-Host ("[{0}/{1}] Pack: {2}" -f $index, $Folders.Count, $folder.FullName)
            Write-Host ("         xml {0}" -f $rootXml)
            Write-Host ("         ->  {0}" -f $target.OutputPath)

            if (Test-Path -LiteralPath $target.OutputPath) {
                $existing = Get-Item -LiteralPath $target.OutputPath
                if ($existing.PSIsContainer) {
                    Write-Warning "Skip (output path is a folder): $($target.OutputPath)"
                    $failed += $folder.FullName
                    continue
                }
                Remove-Item -LiteralPath $target.OutputPath -Force
            }

            $designerMode = "DESIGNER"
            if ($OneC -match '(?i)[\\/]BAF[\\/]') {
                $designerMode = "CONFIG"
            }

            $exitCode = Invoke-1CCommand -OneC $OneC -ArgumentList @(
                $designerMode,
                "/F", "`"$ibPath`"",
                "/DisableStartupDialogs",
                "/LoadExternalDataProcessorOrReportFromFiles",
                "`"$rootXml`"",
                "`"$($target.OutputPath)`""
            )

            if ($exitCode -ne 0) {
                Write-Warning "Error $exitCode : $($folder.Name)"
                $failed += $folder.FullName
            }
        }

        Write-Host ""
        if ($failed.Count) {
            Write-Host "Done with errors ($($failed.Count) / $($Folders.Count))."
            Write-Host "Press Enter to close..."
            [void][System.Console]::ReadLine()
            exit 1
        }

        Write-Host "Done. Processed: $($Folders.Count)"
        Write-Host "Press Enter to close..."
        [void][System.Console]::ReadLine()
    }
    finally {
        Remove-TempFileInfobase -Path $ibPath
        if ($mutexCreated -and $mutex) {
            $mutex.ReleaseMutex() | Out-Null
        }
        if ($mutex) {
            $mutex.Dispose()
        }
    }
}

function Start-EnqueueCollector {
    param([string[]]$IncomingFolders)

    if (-not $IncomingFolders -or $IncomingFolders.Count -eq 0) {
        exit 1
    }

    Add-PackEpfErfQueueFolders -Folders $IncomingFolders

    $leader = $null
    $isLeader = $false
    try {
        $leader = New-Object System.Threading.Mutex($false, "Global\PackEpfErfQueueLeader")
        # Non-blocking: only one process becomes leader and shows UI.
        $isLeader = $leader.WaitOne(0)
        if (-not $isLeader) {
            exit 0
        }

        Wait-PackEpfErfQueueStable
        $allFolders = @(Get-PackEpfErfQueueFoldersAndClear)
        if ($allFolders.Count -eq 0) {
            exit 0
        }

        $listFile = Join-Path $env:TEMP ("PackEpfErf_batch_{0}.txt" -f $PID)
        Set-Content -LiteralPath $listFile -Value $allFolders -Encoding UTF8

        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$SelfPs1`"",
            "-RunBatch",
            "-ListFile", "`"$listFile`""
        )
        if ($PlatformPath) {
            $argList += @("-PlatformPath", "`"$PlatformPath`"")
        }

        $p = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Wait -PassThru
        exit $p.ExitCode
    }
    finally {
        if ($isLeader -and $leader) {
            $leader.ReleaseMutex() | Out-Null
        }
        if ($leader) {
            $leader.Dispose()
        }
    }
}

# --- entry ---

if ($ListFile -and (Test-Path -LiteralPath $ListFile)) {
    $fromList = @(
        Get-Content -LiteralPath $ListFile -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Trim().Trim('"') } |
            Where-Object { $_ }
    )
    $Paths = @($Paths) + $fromList
    Remove-Item -LiteralPath $ListFile -Force -ErrorAction SilentlyContinue
}

$folders = @(Resolve-InputFolders -RawPaths $Paths)

if ($Enqueue) {
    Start-EnqueueCollector -IncomingFolders $folders
    exit 0
}

if (-not $RunBatch) {
    # Default: same as RunBatch (manual launch with one or many folders in one window).
    $RunBatch = $true
}

if (-not $folders -or $folders.Count -eq 0) {
    Write-Host "Usage: Pack-ExternalFromFiles.ps1 [-RunBatch] <folder.epf__UnPacked> [more...]"
    Write-Host "       Pack-ExternalFromFiles.ps1 -Enqueue <folder>   (context menu)"
    exit 1
}

Invoke-PackBatch -Folders $folders
