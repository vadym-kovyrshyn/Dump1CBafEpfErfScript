# Dump selected .epf / .erf next to each file into <Name.ext>__UnPacked\
# Usage:
#   Dump-ExternalToFiles.ps1 -RunBatch <file1> [file2] ...
#   Dump-ExternalToFiles.ps1 -Enqueue <file1>   (context menu; coalesces multi-select into one window)
# Requires 1C/BAF platform. Creates a temporary file IB in %TEMP% and deletes it after unpack.
# 1C messages are shown in this window (no persistent log files).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Paths = @(),

    [Parameter(Mandatory = $false)]
    [ValidateSet("Hierarchical", "Plain")]
    [string]$Format = "Hierarchical",

    [Parameter(Mandatory = $false)]
    [string]$PlatformPath = "",

    [Parameter(Mandatory = $false)]
    [string]$Suffix = "__UnPacked",

    # Context-menu collector: hidden processes enqueue files; one leader opens a single UI window.
    [switch]$Enqueue,

    # Actual unpack worker (one visible window for the whole batch).
    [switch]$RunBatch,

    # Optional file list for long command lines (one path per line).
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

$SelfPs1 = Join-Path $ToolDir "Dump-ExternalToFiles.ps1"

# Legacy folders next to the script - no longer used.
foreach ($legacyName in @("_ib", "_logs")) {
    $legacyPath = Join-Path $ToolDir $legacyName
    if (Test-Path -LiteralPath $legacyPath) {
        Remove-Item -LiteralPath $legacyPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

. (Join-Path $ToolDir "PlatformUtils.ps1")

function Invoke-1CCommand {
    param(
        [string]$OneC,
        [string[]]$ArgumentList
    )

    # 1C writes messages to /Out file only; mirror them to this console, then delete.
    $outFile = Join-Path ([System.IO.Path]::GetTempPath()) ("DumpEpfErf_out_" + [guid]::NewGuid().ToString("N") + ".txt")
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

    $ibPath = Join-Path ([System.IO.Path]::GetTempPath()) ("DumpEpfErf_ib_" + [guid]::NewGuid().ToString("N"))
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

function Resolve-InputFiles {
    param([string[]]$RawPaths)

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($raw in $RawPaths) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $item = $raw.Trim('"')
        if (-not (Test-Path -LiteralPath $item)) {
            Write-Warning "Skip (not found): $item"
            continue
        }
        $file = Get-Item -LiteralPath $item
        if ($file.PSIsContainer) {
            Get-ChildItem -LiteralPath $file.FullName -File |
                Where-Object { $_.Extension -in @(".epf", ".erf") } |
                ForEach-Object { [void]$result.Add($_.FullName) }
        }
        elseif ($file.Extension -in @(".epf", ".erf")) {
            [void]$result.Add($file.FullName)
        }
        else {
            Write-Warning "Skip (not epf/erf): $($file.FullName)"
        }
    }
    return @($result | Select-Object -Unique)
}

function Invoke-UnpackBatch {
    param([string[]]$Files)

    if (-not $Files -or $Files.Count -eq 0) {
        Write-Host "No .epf / .erf to process."
        exit 1
    }

    $mutex = $null
    $mutexCreated = $false
    $ibPath = $null
    try {
        $mutex = New-Object System.Threading.Mutex($false, "Global\DumpEpfErfToUnPacked")
        Write-Host "Waiting for dump lock..."
        if (-not $mutex.WaitOne(600000)) {
            throw "Timeout waiting for another dump process (10 min)."
        }
        $mutexCreated = $true

        $OneC = $null
        if ($PlatformPath -and (Test-Path -LiteralPath $PlatformPath)) {
            $OneC = (Resolve-Path -LiteralPath $PlatformPath).Path
        } else {
            $OneC = Select-1CPlatformInteractive -Title "Unpack: select 1C platform version"
        }
        if (-not $OneC) {
            Write-Host "Cancelled by user."
            exit 0
        }

        Write-Host "Platform: $OneC"
        Write-Host ("Files   : {0}" -f $Files.Count)
        $ibPath = New-TempFileInfobase -OneC $OneC

        $failed = @()
        $index = 0
        foreach ($filePath in $Files) {
            $index++
            $file = Get-Item -LiteralPath $filePath
            $targetDir = Join-Path $file.DirectoryName ($file.Name + $Suffix)

            if (Test-Path -LiteralPath $targetDir) {
                Remove-Item -LiteralPath $targetDir -Recurse -Force
            }
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

            Write-Host ""
            Write-Host ("[{0}/{1}] Dump: {2}" -f $index, $Files.Count, $file.FullName)
            Write-Host ("         -> {0}" -f $targetDir)

            $designerMode = "DESIGNER"
            if ($OneC -match '(?i)[\\/]BAF[\\/]') {
                $designerMode = "CONFIG"
            }

            $exitCode = Invoke-1CCommand -OneC $OneC -ArgumentList @(
                $designerMode,
                "/F", "`"$ibPath`"",
                "/DisableStartupDialogs",
                "/DumpExternalDataProcessorOrReportToFiles",
                "`"$targetDir`"",
                "`"$($file.FullName)`"",
                "-Format", $Format
            )

            if ($exitCode -ne 0) {
                Write-Warning "Error $exitCode : $($file.Name)"
                $failed += $file.FullName
            }
        }

        Write-Host ""
        if ($failed.Count) {
            Write-Host "Done with errors ($($failed.Count) / $($Files.Count))."
            Write-Host "Press Enter to close..."
            [void][System.Console]::ReadLine()
            exit 1
        }

        Write-Host "Done. Processed: $($Files.Count)"
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
    param([string[]]$IncomingFiles)

    if (-not $IncomingFiles -or $IncomingFiles.Count -eq 0) {
        exit 1
    }

    Add-DumpEpfErfQueueFiles -Files $IncomingFiles

    $leader = $null
    $isLeader = $false
    try {
        $leader = New-Object System.Threading.Mutex($false, "Global\DumpEpfErfQueueLeader")
        # Non-blocking: only one process becomes leader and shows UI.
        $isLeader = $leader.WaitOne(0)
        if (-not $isLeader) {
            exit 0
        }

        Wait-DumpEpfErfQueueStable
        $allFiles = @(Get-DumpEpfErfQueueFilesAndClear)
        if ($allFiles.Count -eq 0) {
            exit 0
        }

        $listFile = Join-Path $env:TEMP ("DumpEpfErf_batch_{0}.txt" -f $PID)
        Set-Content -LiteralPath $listFile -Value $allFiles -Encoding UTF8

        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$SelfPs1`"",
            "-RunBatch",
            "-ListFile", "`"$listFile`""
        )
        if ($Format -ne "Hierarchical") {
            $argList += @("-Format", $Format)
        }
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

$files = @(Resolve-InputFiles -RawPaths $Paths)

if ($Enqueue) {
    Start-EnqueueCollector -IncomingFiles $files
    exit 0
}

if (-not $RunBatch) {
    # Default: same as RunBatch (manual launch with one or many files in one window).
    $RunBatch = $true
}

if (-not $files -or $files.Count -eq 0) {
    Write-Host "Usage: Dump-ExternalToFiles.ps1 [-RunBatch] <file.epf|file.erf> [more...]"
    Write-Host "       Dump-ExternalToFiles.ps1 -Enqueue <file>   (context menu)"
    exit 1
}

Invoke-UnpackBatch -Files $files
