# Shared helpers for 1C platform discovery and selection.
# Dot-source: . "$PSScriptRoot\PlatformUtils.ps1"

function Get-1CPlatformConfigPath {
    param([string]$ToolDir)
    return (Join-Path $ToolDir "platform.txt")
}

function Clear-1CPlatformConfig {
    param([string]$ToolDir)

    $cfg = Get-1CPlatformConfigPath -ToolDir $ToolDir
    if (Test-Path -LiteralPath $cfg) {
        Remove-Item -LiteralPath $cfg -Force
        return $true
    }
    return $false
}

function Get-1CPlatformSessionPath {
    return (Join-Path $env:TEMP "DumpEpfErf_platform_session.txt")
}

function Get-1CPlatformSession {
    param([int]$MaxAgeSeconds = 120)

    $path = Get-1CPlatformSessionPath
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    $lines = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue
    if (-not $lines -or $lines.Count -lt 2) {
        return $null
    }

    $ticks = 0L
    if (-not [long]::TryParse([string]$lines[0], [ref]$ticks)) {
        return $null
    }

    $age = ([DateTime]::UtcNow.Ticks - $ticks) / 10000000.0
    if ($age -lt 0 -or $age -gt $MaxAgeSeconds) {
        return $null
    }

    $exe = ([string]$lines[1]).Trim().Trim('"')
    if ($exe -and (Test-Path -LiteralPath $exe)) {
        return $exe
    }
    return $null
}

function Set-1CPlatformSession {
    param([string]$ExePath)

    $path = Get-1CPlatformSessionPath
    $content = @(
        [string][DateTime]::UtcNow.Ticks
        $ExePath
    )
    Set-Content -LiteralPath $path -Value $content -Encoding ASCII
}

function Get-Installed1CPlatforms {
    $roots = @(
        "${env:ProgramFiles}\1cv8",
        "${env:ProgramFiles(x86)}\1cv8",
        "${env:ProgramFiles}\BAF",
        "${env:ProgramFiles(x86)}\BAF"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $list = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($root in $roots) {
        $product = "1C"
        if ($root -match '(?i)\\BAF$') {
            $product = "BAF"
        }

        $exes = Get-ChildItem -LiteralPath $root -Filter "1cv8.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match '\\bin$' }

        foreach ($exe in $exes) {
            $key = $exe.FullName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            $ver = $exe.Directory.Parent.Name
            $bitness = "x64"
            if ($exe.FullName -like "*Program Files (x86)*") {
                $bitness = "x86"
            }

            $list.Add([pscustomobject]@{
                Product = $product
                Version = $ver
                Bitness = $bitness
                Path    = $exe.FullName
                SortKey = $ver
            }) | Out-Null
        }
    }

    return @(
        $list |
            Sort-Object @{ Expression = {
                $p = $_.SortKey -split '\.'
                if ($p.Count -ge 4) {
                    [version]("{0}.{1}.{2}.{3}" -f [int]$p[0], [int]$p[1], [int]$p[2], [int]$p[3])
                } else {
                    [version]"0.0.0.0"
                }
            }; Descending = $true }, Product, Bitness
    )
}

function Select-1CPlatformInteractive {
    param(
        [string]$Title = "Select 1C platform version",
        [string]$DefaultPath = $null
    )

    $platforms = @(Get-Installed1CPlatforms)
    if ($platforms.Count -eq 0) {
        throw "No 1cv8.exe found under Program Files (1cv8 / BAF)."
    }

    $defaultIndex = 0
    if ($DefaultPath) {
        for ($i = 0; $i -lt $platforms.Count; $i++) {
            if ($platforms[$i].Path -eq $DefaultPath) {
                $defaultIndex = $i
                break
            }
        }
    }

    Write-Host ""
    Write-Host $Title
    Write-Host ("-" * [Math]::Min(60, $Title.Length))
    for ($i = 0; $i -lt $platforms.Count; $i++) {
        $p = $platforms[$i]
        $mark = ""
        if ($i -eq $defaultIndex) { $mark = "  [default]" }
        Write-Host ("  [{0}] {1,-4} {2,-14} {3,-4}{4}" -f ($i + 1), $p.Product, $p.Version, $p.Bitness, $mark)
        Write-Host ("       {0}" -f $p.Path)
    }
    Write-Host ""
    Write-Host ("Enter number 1-{0} (Enter = {1}, Esc = cancel):" -f $platforms.Count, ($defaultIndex + 1))
    Write-Host -NoNewline "> "

    $raw = ""
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        # Esc
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            Write-Host "Cancelled."
            return $null
        }

        # Enter
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host ""
            break
        }

        # Backspace
        if ($key.VirtualKeyCode -eq 8) {
            if ($raw.Length -gt 0) {
                $raw = $raw.Substring(0, $raw.Length - 1)
                Write-Host -NoNewline "`b `b"
            }
            continue
        }

        $ch = $key.Character
        if ($ch -match '^[0-9]$') {
            $raw += [string]$ch
            Write-Host -NoNewline ([string]$ch)
        }
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $platforms[$defaultIndex].Path
    }

    $n = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$n)) {
        throw "Invalid input: $raw"
    }
    if ($n -lt 1 -or $n -gt $platforms.Count) {
        throw "Number out of range: $n"
    }
    return $platforms[$n - 1].Path
}

function Resolve-1CPlatformForDump {
    param(
        [string]$Hint = "",
        [int]$SessionMaxAgeSeconds = 120
    )

    if ($Hint -and (Test-Path -LiteralPath $Hint)) {
        $resolved = (Resolve-Path -LiteralPath $Hint).Path
        Set-1CPlatformSession -ExePath $resolved
        return $resolved
    }

    # Multi-select from Explorer starts several processes; reuse choice for a short time.
    $session = Get-1CPlatformSession -MaxAgeSeconds $SessionMaxAgeSeconds
    if ($session) {
        Write-Host "Using platform from current unpack session:"
        Write-Host "  $session"
        return $session
    }

    $selected = Select-1CPlatformInteractive -Title "Unpack: select 1C platform version"
    if (-not $selected) {
        return $null
    }
    Set-1CPlatformSession -ExePath $selected
    return $selected
}

function Get-DumpEpfErfQueuePath {
    return (Join-Path $env:TEMP "DumpEpfErf_file_queue.txt")
}

function Add-DumpEpfErfQueueFiles {
    param([string[]]$Files)

    $mutex = $null
    $acquired = $false
    try {
        $mutex = New-Object System.Threading.Mutex($false, "Global\DumpEpfErfQueueFile")
        if (-not $mutex.WaitOne(30000)) {
            throw "Timeout locking unpack queue."
        }
        $acquired = $true
        $path = Get-DumpEpfErfQueuePath
        foreach ($f in $Files) {
            if ($f) {
                Add-Content -LiteralPath $path -Value $f -Encoding UTF8
            }
        }
    }
    finally {
        if ($acquired -and $mutex) { $mutex.ReleaseMutex() | Out-Null }
        if ($mutex) { $mutex.Dispose() }
    }
}

function Read-DumpEpfErfQueueCount {
    $path = Get-DumpEpfErfQueuePath
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    return @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | Where-Object { $_ -and $_.Trim() }).Count
}

function Get-DumpEpfErfQueueFilesAndClear {
    $mutex = $null
    $acquired = $false
    try {
        $mutex = New-Object System.Threading.Mutex($false, "Global\DumpEpfErfQueueFile")
        if (-not $mutex.WaitOne(30000)) {
            throw "Timeout locking unpack queue."
        }
        $acquired = $true
        $path = Get-DumpEpfErfQueuePath
        $files = @()
        if (Test-Path -LiteralPath $path) {
            $files = @(
                Get-Content -LiteralPath $path -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.Trim().Trim('"') } |
                    Where-Object { $_ } |
                    Select-Object -Unique
            )
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
        return $files
    }
    finally {
        if ($acquired -and $mutex) { $mutex.ReleaseMutex() | Out-Null }
        if ($mutex) { $mutex.Dispose() }
    }
}

function Wait-DumpEpfErfQueueStable {
    param(
        [int]$PollMs = 200,
        [int]$StableRounds = 4
    )

    $last = -1
    $stable = 0
    while ($stable -lt $StableRounds) {
        Start-Sleep -Milliseconds $PollMs
        $count = Read-DumpEpfErfQueueCount
        if ($count -ne $last) {
            $last = $count
            $stable = 0
        } else {
            $stable++
        }
    }
}

