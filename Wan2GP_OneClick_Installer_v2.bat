@echo off
rem ============================================================================
rem  Wan2GP One-Click Installer / Launcher
rem ----------------------------------------------------------------------------
rem  THIS FILE IS A POLYGLOT. It is named .bat so Windows will run it on a
rem  double-click, but only the launcher line below is batch. Everything after
rem  the payload marker is PowerShell, and cmd.exe never parses it because the
rem  exit command terminates the batch interpreter first. (Batch parses
rem  line-by-line at execution time, so unreached lines are never parsed --
rem  which is why the $ { } ( ) ! % characters below are harmless.)
rem
rem  The launcher rebuilds the marker from [char] codes so that the marker
rem  string never appears literally anywhere except on its own line. DO NOT
rem  write the marker literally in these comments -- IndexOf would match the
rem  comment instead and PowerShell would start executing mid-sentence.
rem
rem  Your editor will syntax-highlight this file as batch and get it wrong.
rem  Save as UTF-8 WITHOUT BOM -- a BOM breaks the batch parser on line 1.
rem ============================================================================
set "W2G_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=[IO.File]::ReadAllText($env:W2G_SELF);$m=[char]35+'@WAN2GP_PAYLOAD@'+[char]35;$i=$f.IndexOf($m);if($i -eq -1){Write-Host 'ERROR: payload marker not found.' -ForegroundColor Red;Read-Host 'Press Enter';exit 1};iex $f.Substring($i+$m.Length)"
exit /b %ERRORLEVEL%

#@WAN2GP_PAYLOAD@#
# =============================================================================
#  PowerShell payload begins here.
#  Targets Windows PowerShell 5.1 (guaranteed present). No PS7-only syntax.
# =============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # makes Invoke-WebRequest ~10x faster

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$InstallDir = Join-Path $env:USERPROFILE 'Wan2GP'
$SourceDir  = Join-Path $InstallDir 'source'
$VenvDir    = Join-Path $InstallDir 'venv'          # sibling of source, not inside it
$FlagFile   = Join-Path $InstallDir '.installed'
$LogDir     = Join-Path $InstallDir 'logs'
$RepoUrl    = 'https://github.com/deepbeepmeep/Wan2GP.git'

$PythonVersion   = '3.10.11'                        # last 3.10 with a Windows installer
$PythonUrl       = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
$GitFallbackUrl  = 'https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.2/Git-2.42.0.2-64-bit.exe'
$MinFreeGB       = 50                               # model weights are large

# Build matrix. Keyed by GPU generation. Add a row when a new torch lands --
# this is the ONLY place version pairings live.
#
# torchvision/torchaudio MUST be pinned alongside torch. They ship compiled C
# extensions linked against a specific torch ABI; leaving them floating lets
# pip resolve e.g. torchaudio 2.11 against torch 2.6, which installs cleanly
# and then dies at import with "OSError: [WinError 127] The specified
# procedure could not be found".
$Matrix = @(
    [pscustomobject]@{
        Name        = 'Blackwell (RTX 50xx)'
        MinComputeCap = [version]'12.0'
        Torch       = '2.7.0'
        Vision      = '0.22.0'
        Audio       = '2.7.0'
        CudaTag     = 'cu128'
        Triton      = 'triton-windows<3.4'
        SageWheel   = 'https://github.com/woct0rdho/SageAttention/releases/download/v2.1.1-windows/sageattention-2.1.1+cu128torch2.7.0-cp310-cp310-win_amd64.whl'
    }
    [pscustomobject]@{
        Name        = 'Ada / Ampere / Turing and older'
        MinComputeCap = [version]'0.0'
        Torch       = '2.6.0'
        Vision      = '0.21.0'
        Audio       = '2.6.0'
        CudaTag     = 'cu126'
        Triton      = 'triton-windows<3.3'
        SageWheel   = 'https://github.com/woct0rdho/SageAttention/releases/download/v2.1.1-windows/sageattention-2.1.1+cu126torch2.6.0-cp310-cp310-win_amd64.whl'
    }
)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

$script:StepNum = 0
function Write-Banner {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host "   $Text" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host ''
}
function Write-Step {
    param([string]$Text)
    $script:StepNum++
    Write-Host ''
    Write-Host "[$script:StepNum] $Text" -ForegroundColor Green
}
function Write-Info { param([string]$T) Write-Host "    $T" -ForegroundColor Gray }
function Write-Warn { param([string]$T) Write-Host "    ! $T" -ForegroundColor Yellow }
function Write-Err  { param([string]$T) Write-Host "    X $T" -ForegroundColor Red }

# Windows shows the UAC consent dialog on a separate secure desktop and often
# does NOT bring it to the foreground -- it just flashes in the taskbar. Users
# sit staring at a frozen-looking installer. Say so, loudly, before we launch
# anything that can elevate.
function Show-UacNotice {
    param([string]$What)
    Write-Host ''
    Write-Host '  +--------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host '  |          LOOK AT YOUR TASKBAR IN A MOMENT              |' -ForegroundColor Yellow
    Write-Host '  +--------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "  Windows will ask permission to install $What." -ForegroundColor White
    Write-Host ''
    Write-Host '  That prompt often opens MINIMIZED. Look for a flashing' -ForegroundColor White
    Write-Host '  blue-and-yellow shield icon in your taskbar and click it,' -ForegroundColor White
    Write-Host '  then choose Yes.' -ForegroundColor White
    Write-Host ''
    Write-Host '  Nothing will happen until you do -- this window will just' -ForegroundColor White
    Write-Host '  sit there waiting. It is not frozen.' -ForegroundColor White
    Write-Host ''
    Write-Host '  (If you do not see it, press Alt+Tab or check for a new' -ForegroundColor Gray
    Write-Host '   taskbar item.)' -ForegroundColor Gray
    Write-Host ''
    Read-Host '  Press Enter when you are ready, then watch the taskbar' | Out-Null
    Write-Host '  Waiting for you to approve the Windows prompt...' -ForegroundColor Cyan
    Write-Host ''
}

# Run a native exe and honour its exit code. Native commands do NOT respect
# $ErrorActionPreference, which is the single biggest footgun in PS scripting.
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]   $Exe,
        [Parameter(Mandatory)][string[]] $Arguments,
        [string] $What,
        [switch] $AllowFailure
    )
    if (-not $What) { $What = "$Exe $($Arguments -join ' ')" }
    Write-Info "> $Exe $($Arguments -join ' ')"
    # Out-Host keeps the child process's output on screen. Without it, the
    # caller's "| Out-Null" would discard pip's output along with our boolean.
    # EAP is relaxed because tools like git write normal progress to stderr.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments | Out-Host
    } finally {
        $ErrorActionPreference = $prev
    }
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) {
            Write-Warn "$What failed (exit $LASTEXITCODE) -- continuing."
            return $false
        }
        throw "$What failed with exit code $LASTEXITCODE."
    }
    return $true
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Merge freshly-registered Machine/User PATH entries into this session WITHOUT
# discarding what the session already had. A plain replace would drop anything
# present only in the live process environment.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($env:Path, $machine, $user) | Where-Object { $_ }) -join ';'
}

# CRITICAL: in PowerShell 5.1, redirecting a native command's stderr (2>$null,
# *>$null, 2>&1) turns each stderr line into an ErrorRecord -- and with
# $ErrorActionPreference='Stop' that THROWS. Probes like "does py -3.10 exist"
# or "does this module import" legitimately write to stderr when the answer is
# no, so they must never run under Stop. Every native call that we redirect
# goes through this helper.
function Invoke-Capture {
    param(
        [Parameter(Mandatory)][string]   $Exe,
        [Parameter(Mandatory)][string[]] $Arguments
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw  = & $Exe @Arguments 2>&1
        $code = $LASTEXITCODE
        $out  = @()
        $err  = @()
        foreach ($item in $raw) {
            if ($item -is [System.Management.Automation.ErrorRecord]) { $err += "$item" }
            else { $out += "$item" }
        }
        $first = ''
        if ($out.Count -gt 0) { $first = $out[0] }
        return [pscustomobject]@{
            ExitCode = $code
            Out      = $out
            Err      = $err
            Text     = ($out -join "`n")
            First    = $first
        }
    } finally {
        $ErrorActionPreference = $prev
    }
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

function Test-DiskSpace {
    # A profile on an unusual drive or UNC path can make this lookup fail;
    # a skipped advisory check must never abort the install.
    try {
        $drive = (Split-Path -Qualifier $InstallDir)      # e.g. "C:"
        $free  = (Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction Stop).Free / 1GB
    } catch {
        Write-Warn 'Could not determine free disk space -- skipping this check.'
        return
    }
    Write-Info ("Free space on {0} {1:N1} GB" -f $drive, $free)
    if ($free -lt $MinFreeGB) {
        Write-Warn "Wan2GP downloads tens of GB of model weights. $MinFreeGB GB+ recommended."
        if ((Read-Host '    Continue anyway? (y/N)') -notmatch '^[Yy]') { throw 'Aborted: insufficient disk space.' }
    }
}

# ---------------------------------------------------------------------------
# GPU detection
# ---------------------------------------------------------------------------

function Get-GpuInfo {
    $smi = $null
    if (Test-CommandExists 'nvidia-smi') {
        $smi = 'nvidia-smi'
    } else {
        $candidates = @(
            (Join-Path $env:ProgramFiles      'NVIDIA Corporation\NVSMI\nvidia-smi.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'),
            (Join-Path $env:SystemRoot        'System32\nvidia-smi.exe')
        )
        foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { $smi = $c; break } }
    }

    $result = [pscustomobject]@{ Found = $false; Name = 'Unknown'; ComputeCap = $null }

    if (-not $smi) {
        # Explicit boolean test -- unlike the batch version, this genuinely
        # distinguishes "no NVIDIA card" from "drivers missing".
        $hasNvidia = [bool](Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -like '*NVIDIA*' })
        if ($hasNvidia) {
            Write-Warn 'NVIDIA GPU present but nvidia-smi not found -- your drivers are missing or outdated.'
            Write-Warn 'Install the latest driver from nvidia.com/drivers, reboot, and re-run this script.'
            $result.Found = $true
            $result.Name  = 'NVIDIA GPU (driver tools missing)'
        } else {
            Write-Err 'No NVIDIA GPU detected. Wan2GP requires an NVIDIA card with CUDA support.'
        }
        return $result
    }

    # Older drivers reject --query-gpu=compute_cap and print to stderr, so
    # these go through Invoke-Capture rather than a bare 2>$null redirect.
    $nameR = Invoke-Capture $smi @('--query-gpu=name', '--format=csv,noheader')
    $capR  = Invoke-Capture $smi @('--query-gpu=compute_cap', '--format=csv,noheader')
    $name  = $nameR.First
    $cap   = $capR.First

    if ($nameR.ExitCode -eq 0 -and $name) { $result.Found = $true; $result.Name = $name.Trim() }

    if ($capR.ExitCode -eq 0 -and $cap -and $cap.Trim() -match '^\d+\.\d+$') {
        $result.ComputeCap = [version]$cap.Trim()
    } elseif ($result.Name -match 'RTX\s*50\d0') {
        # Fallback for older drivers with no compute_cap query. Note this
        # pattern does NOT match 3050 / 4050 / 2050.
        Write-Info 'compute_cap unavailable; inferring generation from model name.'
        $result.ComputeCap = [version]'12.0'
    }
    return $result
}

function Resolve-BuildMatrix {
    param($Gpu)
    $cap = $Gpu.ComputeCap
    if (-not $cap) {
        Write-Warn 'Could not determine compute capability -- defaulting to the conservative build.'
        $cap = [version]'0.0'
    }
    foreach ($row in $Matrix) {
        if ($cap -ge $row.MinComputeCap) { return $row }
    }
    return $Matrix[-1]
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

# Returns the path/args used to invoke Python 3.10 specifically. Using the py
# launcher avoids the classic bug where a pre-existing 3.12 shadows "python".
function Get-Python310 {
    # py.exe writes "Installed Pythons found by ..." to STDERR when the
    # requested version is missing. Probing it must not be fatal.
    if (Test-CommandExists 'py') {
        $r = Invoke-Capture 'py' @('-3.10', '--version')
        if ($r.ExitCode -eq 0 -and "$($r.Text)" -match '3\.10\.') {
            return @{ Exe = 'py'; Pre = @('-3.10') }
        }
    }
    $direct = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python310\python.exe'
    if (Test-Path $direct) {
        $r = Invoke-Capture $direct @('--version')
        if ($r.ExitCode -eq 0 -and "$($r.Text)" -match '3\.10\.') {
            return @{ Exe = $direct; Pre = @() }
        }
    }
    if (Test-CommandExists 'python') {
        $r = Invoke-Capture 'python' @('--version')
        # Python 3.4 and earlier print the version to stderr, so check both.
        if ($r.ExitCode -eq 0 -and ("$($r.Text)$($r.Err)" -match '3\.10\.')) {
            return @{ Exe = 'python'; Pre = @() }
        }
    }
    return $null
}

function Install-Python310 {
    Write-Info "Downloading Python $PythonVersion ..."
    $installer = Join-Path $env:TEMP "python-$PythonVersion-amd64.exe"
    Invoke-WebRequest -Uri $PythonUrl -OutFile $installer -UseBasicParsing

    Write-Info 'Installing (per-user, no admin required). This takes a minute...'
    $target = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python310'

    # InstallLauncherAllUsers=0 is the important one: the py launcher defaults
    # to a machine-wide install, which triggers a UAC prompt even though the
    # interpreter itself is per-user. With this set, no elevation is needed.
    # TargetDir is quoted because PS 5.1 joins ArgumentList with spaces and
    # does NOT quote -- a username like "Ray Smith" would split the argument.
    $p = Start-Process -FilePath $installer -Wait -PassThru -ArgumentList @(
        '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1',
        'InstallLauncherAllUsers=0', 'Include_test=0', ('TargetDir="{0}"' -f $target)
    )
    Remove-Item $installer -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { throw "Python installer failed with exit code $($p.ExitCode)." }

    # Refresh PATH in-process so we don't need the user to re-run the script.
    Update-SessionPath
}

function Install-Git {
    if (Test-CommandExists 'winget') {
        Write-Info 'Installing Git via winget...'
        Show-UacNotice 'Git'
        $ok = Invoke-Native 'winget' @(
            'install', '--id', 'Git.Git', '-e', '--source', 'winget',
            '--accept-package-agreements', '--accept-source-agreements'
        ) -What 'winget install Git' -AllowFailure
        if ($ok) {
            Update-SessionPath
            if (Test-CommandExists 'git') { return }
        }
    }
    Write-Info 'Falling back to direct Git download...'
    Write-Warn "This URL is pinned to an old release; bump `$GitFallbackUrl periodically."
    $installer = Join-Path $env:TEMP 'git-installer.exe'
    Invoke-WebRequest -Uri $GitFallbackUrl -OutFile $installer -UseBasicParsing
    Show-UacNotice 'Git'
    $p = Start-Process -FilePath $installer -Wait -PassThru -ArgumentList @(
        '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-'
    )
    Remove-Item $installer -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { throw "Git installer failed with exit code $($p.ExitCode)." }
    Update-SessionPath
}

# ---------------------------------------------------------------------------
# Virtual environment
# ---------------------------------------------------------------------------

# Everything after venv creation runs through these absolute paths. We never
# call activate.bat, so there is no activation state to verify or get wrong.
function Get-VenvPython { return (Join-Path $VenvDir 'Scripts\python.exe') }

function New-Venv {
    param($Py)
    if (Test-Path (Get-VenvPython)) {
        Write-Info 'Virtual environment already exists.'
        return
    }
    Write-Info "Creating virtual environment at $VenvDir"
    Invoke-Native $Py.Exe ($Py.Pre + @('-m', 'venv', $VenvDir)) -What 'venv creation' | Out-Null
    if (-not (Test-Path (Get-VenvPython))) { throw 'Virtual environment was not created.' }
}

function Invoke-Pip {
    param([string[]]$Arguments, [switch]$AllowFailure, [string]$What)
    return Invoke-Native (Get-VenvPython) (@('-m', 'pip') + $Arguments) -What $What -AllowFailure:$AllowFailure
}

# --- progress tracking -----------------------------------------------------
# pip only draws its own progress bar when stdout is a real terminal. Under
# Start-Transcript it is not, so a multi-GB PyTorch download would otherwise
# print nothing for ten minutes and look hung. We run pip with its output
# redirected to a file, poll that file, and render our own status line.

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} kB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function ConvertTo-Bytes {
    param([double]$Value, [string]$Unit)
    switch ($Unit.ToLower()) {
        'gb'    { return $Value * 1GB }
        'mb'    { return $Value * 1MB }
        'kb'    { return $Value * 1KB }
        default { return $Value }
    }
}

# Read a file another process is actively writing to.
function Read-SharedText {
    param([string]$Path)
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $sr = New-Object IO.StreamReader($fs)
        $text = $sr.ReadToEnd()
        $sr.Dispose(); $fs.Dispose()
        return $text
    } catch { return '' }
}

# Best-effort byte count for the file pip is currently downloading. pip stages
# downloads in %TEMP%\pip-unpack-*, so the newest file there approximates
# progress. Entirely optional -- if this finds nothing we just omit the
# percentage rather than showing something wrong.
function Get-PipStagedBytes {
    try {
        $newest = Get-ChildItem -Path $env:TEMP -Directory -Filter 'pip-*' -ErrorAction SilentlyContinue |
                  ForEach-Object { Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue } |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($newest) { return [double]$newest.Length }
    } catch { }
    return 0
}

function Invoke-PipTracked {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [string] $What = 'pip',
        [switch] $AllowFailure
    )

    $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile = Join-Path $LogDir "pip-$stamp.out.log"
    $errFile = Join-Path $LogDir "pip-$stamp.err.log"

    # -u unbuffers Python so lines reach the log promptly.
    # --progress-bar off suppresses pip's own bar, which is useless when
    # redirected and would fill the log with control characters.
    $pipArgs = @('-u', '-m', 'pip') + $Arguments + @('--progress-bar', 'off')

    Write-Info "> pip $($Arguments -join ' ')"
    Write-Host ''

    # PS 5.1 joins ArgumentList with spaces without quoting, so any argument
    # containing a space (like a requirements.txt path under "C:\Users\Ray
    # Smith\...") must be quoted by hand.
    $quotedArgs = @()
    foreach ($a in $pipArgs) {
        if ($a -match '[\s"]') { $quotedArgs += ('"' + ($a -replace '"', '\"') + '"') }
        else { $quotedArgs += $a }
    }

    $proc = Start-Process -FilePath (Get-VenvPython) -ArgumentList $quotedArgs `
                          -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
                          -NoNewWindow -PassThru

    # PS 5.1 gotcha: without -Wait, the exit code is only retrievable later if
    # the process HANDLE was touched while the process was still alive.
    # Skipping this made $proc.ExitCode come back $null after a SUCCESSFUL
    # install, which we then reported as "failed with exit code ''".
    $null = $proc.Handle

    # Console width, computed once. Also used to clear the status line at the
    # end -- clearing with a fixed 100 chars would wrap on narrow windows.
    $width = 100
    try { $width = [Math]::Max(40, $Host.UI.RawUI.WindowSize.Width - 4) } catch { }

    $sw       = [Diagnostics.Stopwatch]::StartNew()
    $frames   = @('|', '/', '-', '\')
    $frame    = 0
    $pos      = 0
    $phase    = 'Resolving dependencies'
    $current  = ''
    $expected = 0.0
    $doneBytes = 0.0
    $pkgCount = 0

    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 400

        $text = Read-SharedText $outFile
        if ($text.Length -gt $pos) {
            $new = $text.Substring($pos)
            $pos = $text.Length
            foreach ($line in ($new -split "`r?`n")) {
                if ($line -match '^\s*Collecting\s+(\S+)') {
                    $phase = 'Resolving'; $current = $Matches[1]
                }
                elseif ($line -match '^\s*Downloading\s+(\S+)\s+\(([\d.]+)\s*([kKmMgG]?B)\)') {
                    $phase = 'Downloading'
                    $current = $Matches[1]
                    if ($expected -gt 0) { $doneBytes += $expected }
                    $expected = ConvertTo-Bytes ([double]$Matches[2]) $Matches[3]
                    $pkgCount++
                }
                elseif ($line -match '^\s*Using cached\s+(\S+)') {
                    $phase = 'Using cache'; $current = $Matches[1]; $expected = 0; $pkgCount++
                }
                elseif ($line -match '^\s*Installing collected packages') {
                    $phase = 'Installing'; $current = 'unpacking wheels'; $expected = 0
                }
                elseif ($line -match '^\s*Successfully installed') {
                    $phase = 'Finishing'; $current = ''
                }
            }
        }

        # Build the status line.
        $elapsed = '{0:hh\:mm\:ss}' -f $sw.Elapsed
        $status  = "{0} {1}  {2}" -f $frames[$frame % 4], $elapsed, $phase
        $frame++

        if ($current) {
            $short = $current
            if ($short.Length -gt 34) { $short = $short.Substring(0, 31) + '...' }
            $status += "  $short"
        }

        if ($expected -gt 0) {
            $staged = Get-PipStagedBytes
            if ($staged -gt 0 -and $staged -le ($expected * 1.05)) {
                $pct = [Math]::Min(100, [int](($staged / $expected) * 100))
                $bar = ('#' * [int]($pct / 5)).PadRight(20, '.')
                $status += "  [$bar] $pct%  $(Format-Bytes $staged) / $(Format-Bytes $expected)"
            } else {
                $status += "  ($(Format-Bytes $expected))"
            }
        }
        elseif ($doneBytes -gt 0) {
            $status += "  ($(Format-Bytes $doneBytes) so far)"
        }

        if ($pkgCount -gt 0) { $status += "  [$pkgCount pkg]" }

        # Trim so the line never wraps and smears.
        if ($status.Length -gt $width) { $status = $status.Substring(0, $width) }

        Write-Host ("`r  " + $status.PadRight($width)) -NoNewline -ForegroundColor Cyan
    }

    $proc.WaitForExit()
    Write-Host ("`r" + (' ' * ($width + 2)) + "`r") -NoNewline
    $sw.Stop()

    $exitCode = $proc.ExitCode
    if ($null -eq $exitCode) {
        # Should not happen now that the handle is cached, but never punish a
        # successful install: fall back to pip's own verdict in the log.
        $logText = Read-SharedText $outFile
        if ($logText -match '(?m)^Successfully installed') { $exitCode = 0 } else { $exitCode = 1 }
        Write-Warn "Could not read pip's exit code; judged $exitCode from the log."
    }

    if ($exitCode -eq 0) {
        Write-Host ("  Done in {0:hh\:mm\:ss}." -f $sw.Elapsed) -ForegroundColor Green
        Write-Info "pip log: $outFile"
        return $true
    }

    # On failure the log is the only diagnostic, so surface the tail of it.
    Write-Err "$What failed (exit $exitCode). Last lines of output:"
    Write-Host ''
    $tail = @()
    foreach ($f in @($errFile, $outFile)) {
        if (Test-Path $f) { $tail += (Get-Content $f -Tail 25 -ErrorAction SilentlyContinue) }
    }
    $tail | Select-Object -Last 30 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Info "Full log: $outFile"

    if ($AllowFailure) { return $false }
    throw "$What failed with exit code $exitCode."
}

# Probe whether a module imports inside the venv. A failed import prints a
# traceback to stderr, so this MUST go through Invoke-Capture.
function Test-PyImport {
    param([string]$Module)
    $r = Invoke-Capture (Get-VenvPython) @('-c', "import $Module")
    return ($r.ExitCode -eq 0)
}

function Get-PyValue {
    param([string]$Code)
    $r = Invoke-Capture (Get-VenvPython) @('-c', $Code)
    if ($r.ExitCode -ne 0) { return $null }
    return $r.First
}

# Read an installed package's version from its metadata.
# NOTE: never embed double quotes in a -c one-liner. PS 5.1 mangles them when
# building the native command line, so 'print(getattr(s, "__version__", "1"))'
# arrives at Python with the quotes stripped and raises NameError -- which is
# why the SageAttention probe silently returned nothing and picked the wrong
# backend. Single quotes inside a double-quoted PS string are safe.
function Get-PyPackageVersion {
    param([string]$Package)
    return Get-PyValue "import importlib.metadata as m; print(m.version('$Package'))"
}

# torch, torchvision and torchaudio ship compiled extensions linked to a
# specific torch ABI. A mismatched trio installs without complaint and only
# explodes at import, so check explicitly after anything that can move them.
function Assert-TorchStack {
    Write-Info 'Verifying torch / torchvision / torchaudio load together...'
    foreach ($mod in @('torch', 'torchvision', 'torchaudio')) {
        if (-not (Test-PyImport $mod)) {
            $r = Invoke-Capture (Get-VenvPython) @('-c', "import $mod")
            Write-Err "$mod is installed but fails to import:"
            @($r.Err + $r.Out) | Select-Object -Last 6 |
                ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
            Write-Host ''
            Write-Warn 'WinError 127 here means a torch / torchvision / torchaudio version mismatch.'
            throw "$mod could not be imported. Re-run this script and choose Repair."
        }
    }
    $tv = Get-PyPackageVersion 'torch'
    $vv = Get-PyPackageVersion 'torchvision'
    $av = Get-PyPackageVersion 'torchaudio'
    Write-Info "torch $tv / torchvision $vv / torchaudio $av"
}

# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------

function Sync-Source {
    param([switch]$Update)
    if (-not (Test-Path (Join-Path $SourceDir '.git'))) {
        Write-Info 'Cloning Wan2GP...'
        Invoke-Native 'git' @('clone', '--depth', '1', $RepoUrl, $SourceDir) -What 'git clone' | Out-Null
    } elseif ($Update) {
        Write-Info 'Updating Wan2GP...'
        Invoke-Native 'git' @('-C', $SourceDir, 'pull', '--ff-only') -What 'git pull' -AllowFailure | Out-Null
    } else {
        Write-Info 'Source already present.'
    }
}

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

function Install-Dependencies {
    param($Build)

    Write-Step 'Upgrading pip'
    Invoke-Pip @('install', '--upgrade', 'pip', 'setuptools', 'wheel') -What 'pip upgrade' -AllowFailure | Out-Null

    Write-Step "Installing PyTorch $($Build.Torch) ($($Build.CudaTag))"
    Write-Info 'This is the big one: roughly 2-3 GB. Progress is shown below.'
    # All three pinned together. Unpinned companions caused pip to backtrack
    # through dozens of candidates and then pick an ABI-incompatible pair.
    Invoke-PipTracked @(
        'install',
        "torch==$($Build.Torch)",
        "torchvision==$($Build.Vision)",
        "torchaudio==$($Build.Audio)",
        '--index-url', "https://download.pytorch.org/whl/$($Build.CudaTag)"
    ) -What 'PyTorch install' | Out-Null

    # Verify the GPU build actually works before spending time on the rest.
    $cudaOk = Get-PyValue 'import torch; print(torch.cuda.is_available())'
    if ($cudaOk -eq 'True') {
        $dev = Get-PyValue 'import torch; print(torch.cuda.get_device_name(0))'
        Write-Info "CUDA is available. Torch sees: $dev"
    } else {
        Write-Warn 'torch.cuda.is_available() returned False. Generation will be extremely slow or fail.'
        Write-Warn 'This usually means the NVIDIA driver is older than the CUDA runtime. Update your driver.'
    }

    # Import the compiled extensions NOW. An ABI mismatch installs perfectly
    # and only fails at import time -- catching it here rather than at launch
    # turns a cryptic WinError 127 traceback into an actionable message.
    Assert-TorchStack

    Write-Step 'Installing project requirements'
    $req = Join-Path $SourceDir 'requirements.txt'
    if (Test-Path $req) {
        Invoke-PipTracked @('install', '-r', $req) -What 'requirements install' | Out-Null
        # requirements.txt can pull in a package that upgrades torch or its
        # companions, so re-check rather than trusting the earlier pass.
        Assert-TorchStack
    } else {
        Write-Warn 'requirements.txt not found -- repository layout may have changed.'
    }

    Write-Step 'Installing Triton (optional, enables --compile)'
    # One constraint, from the matrix. No cascade of downgrades, and NO
    # AttrsDescriptor check: that symbol was removed in Triton 3.1+, so testing
    # for it made correct installs look broken and triggered a downgrade to
    # versions incompatible with torch 2.6/2.7.
    Invoke-Pip @('uninstall', '-y', 'triton', 'triton-windows') -What 'triton cleanup' -AllowFailure | Out-Null
    Invoke-Pip @('install', $Build.Triton) -What 'triton install' -AllowFailure | Out-Null
    if (Test-PyImport 'triton') {
        Write-Info "Triton OK: $(Get-PyPackageVersion 'triton-windows')"
    } else {
        Write-Warn 'Triton unavailable. The app will run without torch.compile (slower, but fine).'
    }

    Write-Step 'Installing SageAttention (optional, faster attention)'
    $sage2 = Invoke-Pip @('install', $Build.SageWheel) -What 'SageAttention 2' -AllowFailure
    if (-not $sage2) {
        Write-Warn 'Prebuilt SageAttention 2 wheel unavailable; falling back to 1.0.6.'
        Invoke-Pip @('install', 'sageattention==1.0.6') -What 'SageAttention 1' -AllowFailure | Out-Null
    }

    # flash-attn deliberately omitted: no Windows wheel exists, so pip attempts
    # a source build that needs the CUDA toolkit and 30-60 minutes, then fails.
}

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

function Start-Wan2GP {
    if (-not (Test-Path (Get-VenvPython))) { throw "Virtual environment missing at $VenvDir. Choose Repair." }
    $entry = Join-Path $SourceDir 'wgp.py'
    if (-not (Test-Path $entry))          { throw "wgp.py not found in $SourceDir. Choose Repair." }

    # Probe capabilities ONCE and build the arg list from what actually
    # imported. The old retry-cascade treated Ctrl+C and port conflicts as
    # "backend failed" and silently relaunched with degraded flags.
    $appArgs = @('--open-browser')

    if (Test-PyImport 'sageattention') {
        # Read from package metadata, not s.__version__ -- SageAttention does
        # not always define it, and the old getattr one-liner contained double
        # quotes that PS 5.1 stripped, so this always came back empty and
        # silently downgraded a working SageAttention 2 to "sage".
        $sv = Get-PyPackageVersion 'sageattention'
        $major = 0
        if ("$sv" -match '^\s*(\d+)') { $major = [int]$Matches[1] }
        if ($major -ge 2) {
            $appArgs += @('--attention', 'sage2'); Write-Info "SageAttention $sv -> --attention sage2"
        } else {
            $appArgs += @('--attention', 'sage');  Write-Info "SageAttention $sv -> --attention sage"
        }
    } else {
        Write-Info 'SageAttention not available -> default attention backend.'
    }

    if (Test-PyImport 'triton') { $appArgs += '--compile'; Write-Info 'Triton available -> --compile enabled.' }

    Write-Banner 'Starting Wan2GP'
    Write-Host '  The UI will open at http://localhost:7860' -ForegroundColor Cyan
    Write-Host '  Close this window or press Ctrl+C to stop.' -ForegroundColor Cyan
    Write-Host ''

    Push-Location $SourceDir
    try {
        # No 2>nul anywhere: if this fails the user needs to see the traceback.
        & (Get-VenvPython) $entry @appArgs
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if ($code -ne 0) {
        Write-Banner 'Wan2GP exited with an error'
        Write-Host '  The traceback above is the real error. Common causes:' -ForegroundColor Yellow
        Write-Host '   - OSError WinError 127 -> torch/torchvision/torchaudio version' -ForegroundColor Yellow
        Write-Host '     mismatch; re-run this script and choose Repair' -ForegroundColor Yellow
        Write-Host '   - Port 7860 already in use (another instance running?)' -ForegroundColor Yellow
        Write-Host '   - Outdated NVIDIA driver' -ForegroundColor Yellow
        Write-Host "  Full log: $LogDir" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Install / repair flow
# ---------------------------------------------------------------------------

function Invoke-Install {
    param([switch]$Update)
    $script:StepNum = 0

    Write-Step 'Checking disk space'
    Test-DiskSpace

    Write-Step 'Checking Python 3.10'
    $py = Get-Python310
    if (-not $py) {
        Write-Info 'Python 3.10 not found.'
        Install-Python310
        $py = Get-Python310
        if (-not $py) { throw 'Python 3.10 still not found after install. Reboot and re-run this script.' }
    }
    $verArgs = $py.Pre + @('--version')
    $verR = Invoke-Capture $py.Exe $verArgs
    Write-Info "Using: $(($verR.Text + $($verR.Err -join ' ')).Trim())"

    Write-Step 'Checking Git'
    if (-not (Test-CommandExists 'git')) { Install-Git }
    if (-not (Test-CommandExists 'git')) { throw 'Git still not found after install. Reboot and re-run this script.' }
    Write-Info (git --version)

    Write-Step 'Detecting GPU'
    $gpu = Get-GpuInfo
    if (-not $gpu.Found) {
        if ((Read-Host '    Continue without a supported GPU? (y/N)') -notmatch '^[Yy]') { throw 'Aborted: no NVIDIA GPU.' }
    }
    Write-Info "GPU: $($gpu.Name)"
    if ($gpu.ComputeCap) { Write-Info "Compute capability: $($gpu.ComputeCap)" }

    $build = Resolve-BuildMatrix $gpu
    Write-Info "Build profile: $($build.Name) -> torch $($build.Torch) / $($build.CudaTag)"

    Write-Step 'Fetching source'
    Sync-Source -Update:$Update

    Write-Step 'Creating virtual environment'
    New-Venv $py

    Install-Dependencies $build

    Set-Content -Path $FlagFile -Value @"
installed=$(Get-Date -Format o)
gpu=$($gpu.Name)
profile=$($build.Name)
torch=$($build.Torch)
cuda=$($build.CudaTag)
"@
    Write-Banner 'Installation complete'
}

function Invoke-Repair {
    Write-Warn 'Repair removes the virtual environment and reinstalls all Python packages.'
    Write-Warn 'Downloaded model weights are NOT deleted.'
    if ((Read-Host '    Proceed? (y/N)') -notmatch '^[Yy]') {
        Write-Info 'Repair cancelled. Nothing was changed.'
        return $false
    }
    if (Test-Path $VenvDir) {
        Write-Info 'Removing virtual environment...'
        Remove-Item $VenvDir -Recurse -Force
    }
    Remove-Item $FlagFile -Force -ErrorAction SilentlyContinue
    Invoke-Install -Update
    return $true
}

function Show-Menu {
    Write-Host '  1) Launch Wan2GP        (default)'
    Write-Host '  2) Update and launch    (git pull + refresh dependencies)'
    Write-Host '  3) Repair               (rebuild the virtual environment)'
    Write-Host '  4) Exit'
    Write-Host ''
    switch ((Read-Host '  Choice [1]')) {
        '2'     { Invoke-Install -Update; Start-Wan2GP }
        '3'     { if (Invoke-Repair) { Start-Wan2GP } }
        '4'     { return }
        default { Start-Wan2GP }
    }
}

# ---------------------------------------------------------------------------
# Welcome / consent
# ---------------------------------------------------------------------------

function Show-Welcome {
    param([switch]$Existing)
    Clear-Host
    Write-Banner 'Wan2GP One-Click Script v2 by TechMitten'

    Write-Host '  Wan2GP lets you generate video and images with AI models that run' -ForegroundColor White
    Write-Host '  entirely on your own computer, using your NVIDIA graphics card.' -ForegroundColor White
    Write-Host '  Nothing you create is uploaded anywhere.' -ForegroundColor White
    Write-Host ''

    if (-not $Existing) {
        Write-Host '  This installer will set everything up for you. Here is exactly' -ForegroundColor White
        Write-Host '  what it does:' -ForegroundColor White
        Write-Host ''
    }

    if ($Existing) {
        Write-Host '  WHAT IS INSTALLED' -ForegroundColor Cyan
        Write-Host '    - Python 3.10 and Git'
        Write-Host '    - The Wan2GP program, from its official GitHub page'
        Write-Host '    - The AI libraries it needs (PyTorch and friends)'
    } else {
        Write-Host '  WHAT GETS INSTALLED' -ForegroundColor Cyan
        Write-Host '    - Python 3.10 and Git, if you do not already have them'
        Write-Host '    - The Wan2GP program itself, downloaded from its official'
        Write-Host '      GitHub page'
        Write-Host '    - The AI libraries it needs (PyTorch and friends)'
    }
    Write-Host ''

    Write-Host '  WHERE IT LIVES' -ForegroundColor Cyan
    Write-Host "    $InstallDir"
    Write-Host '    Everything lives in that one folder, inside your own user'
    Write-Host '    account. To uninstall, just delete it.'
    Write-Host ''

    if (-not $Existing) {
        Write-Host '  ONE THING TO WATCH FOR' -ForegroundColor Cyan
        Write-Host '    If Git is not already on this PC, Windows will pop up a'
        Write-Host '    permission prompt to install it. That prompt often opens'
        Write-Host '    MINIMISED, so watch your taskbar for a flashing shield'
        Write-Host '    icon. The installer will wait, and will tell you when to'
        Write-Host '    look for it.'
        Write-Host ''
    }

    Write-Host '  REQUIREMENTS' -ForegroundColor Cyan
    Write-Host '    - Windows 10 or 11, 64-bit'
    Write-Host '    - An NVIDIA graphics card with up-to-date drivers'
    Write-Host '      (AMD and Intel graphics will not work)'

    Write-Host ('  ' + ('-' * 56)) -ForegroundColor DarkGray
    Write-Host ''
    if ($Existing) {
        Write-Host '  Type YES to continue, or press Enter to close.' -ForegroundColor Yellow
    } else {
        Write-Host '  Type YES to begin, or press Enter to cancel.' -ForegroundColor Yellow
    }
    Write-Host ''
    $answer = Read-Host '  Your choice'

    if ($answer -notmatch '^\s*(yes|y)\s*$') {
        Write-Host ''
        if ($Existing) {
            Write-Host '  Cancelled. Nothing was changed.' -ForegroundColor Gray
        } else {
            Write-Host '  Cancelled. Nothing was installed and nothing was changed.' -ForegroundColor Gray
        }
        return $false
    }
    return $true
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

$transcriptStarted = $false
try {
    New-Item -ItemType Directory -Force -Path $InstallDir, $LogDir | Out-Null
    try {
        Start-Transcript -Path (Join-Path $LogDir ("wan2gp-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))) | Out-Null
        $transcriptStarted = $true
    } catch { Write-Warn 'Could not start logging; continuing without a transcript.' }

    if (Test-Path $FlagFile) {
        if (-not (Show-Welcome -Existing)) { return }
        Write-Host ''
        Show-Menu
    } else {
        if (-not (Show-Welcome)) { return }
        Invoke-Install
        Start-Wan2GP
    }
}
catch {
    Write-Banner 'Something went wrong'
    Write-Err $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host "  Log saved to: $LogDir" -ForegroundColor Yellow
    Write-Host '  Re-run this script and choose Repair, or delete' -ForegroundColor Yellow
    Write-Host "  $InstallDir to start over." -ForegroundColor Yellow
}
finally {
    if ($transcriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
    Write-Host ''
    Read-Host 'Press Enter to close'
}
