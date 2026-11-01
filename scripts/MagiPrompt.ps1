# ===========================================================================
# MAGI prompt + output helper
#
# Shared by Windows PowerShell 5.1 and PowerShell 7. Dot-source it from
#   Documents\PowerShell\Microsoft.PowerShell_profile.ps1          (7)
#   Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1   (.NET / 5.1)
#
# Colours are plain ANSI escapes so the same file works on both editions.
# ===========================================================================

# Windows PowerShell 5.1 does not switch the console into VT mode by itself;
# without this the escape sequences below would be printed literally.
if (-not (Get-Variable -Name PSStyle -ErrorAction SilentlyContinue)) {
    try {
        $signature = @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
'@
        $console = Add-Type -Name Console -Namespace Magi -MemberDefinition $signature -PassThru -ErrorAction Stop
        $handle = $console::GetStdHandle(-11)   # STD_OUTPUT_HANDLE
        $mode = [uint32]0
        if ($console::GetConsoleMode($handle, [ref]$mode)) {
            [void]$console::SetConsoleMode($handle, $mode -bor 0x0004)   # ENABLE_VIRTUAL_TERMINAL_PROCESSING
        }
    } catch {
        # No VT available (very old host); prompt falls back to plain text below.
    }
}

# --------------------------------------------------------------- encoding ----
# Windows starts these consoles on the ANSI code page (936 / GBK on a Chinese
# system). Most tooling - MSBuild, clang, cargo, git - writes UTF-8, so every
# Chinese message came out as mojibake (鎵句笉鍒 instead of 找不到). Switch the
# console page itself, not just the .NET encodings, so child processes inherit it.
try {
    $utf8 = [System.Text.Encoding]::UTF8
    if ([Console]::InputEncoding.CodePage  -ne 65001) { [Console]::InputEncoding  = $utf8 }
    if ([Console]::OutputEncoding.CodePage -ne 65001) { [Console]::OutputEncoding = $utf8 }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell 7: used when piping strings into native executables.
        $OutputEncoding = $utf8
    } else {
        # Windows PowerShell 5.1: only 'chcp' changes what native children get.
        if ([Console]::OutputEncoding.CodePage -ne 65001) { chcp 65001 > $null }
        $OutputEncoding = $utf8
    }
} catch {
    # Encoding juggling is best-effort: never let it break the prompt.
}

function prompt {
    $ok = $?          # read first: refers to the previous command

    $ansi  = [char]27
    $amber = "$ansi[93m"
    $red   = "$ansi[91m"
    $green = "$ansi[92m"
    $reset = "$ansi[0m"

    $tag = if ($ok) { "$amber[MAGI]$reset" } else { "$red[MAGI]$reset" }

    $location = $ExecutionContext.SessionState.Path.CurrentLocation
    $path = $location.Path
    if ($path.StartsWith($HOME, [System.StringComparison]::OrdinalIgnoreCase)) {
        $path = '~' + $path.Substring($HOME.Length)
    }

    $branch = ''
    if (Test-Path -LiteralPath (Join-Path $location '.git')) {
        $name = git rev-parse --abbrev-ref HEAD 2>$null
        if ($name) { $branch = " $green$name$reset" }
    }

    $indicator = if ($ok) { "$amber>$reset" } else { "$red>$reset" }
    "$tag $path$branch`n$indicator "
}

# ---------------------------------------------------------------------------
# magi — opt-in output prefixer.
#
#   Get-ChildItem | magi
#   Get-Content .\log.txt | magi
#
# It turns each object into a "[magi] <text>" string, so it is for reading on
# screen only. Piping data through it converts everything to text — that is the
# point (it is a display helper), not a bug.
# ---------------------------------------------------------------------------
filter magi {
    "[magi] $_"
}

# ---------------------------------------------------------------------------
# Greeting. Two lines, both carrying the [magi] prefix:
#
#   [magi] MAGI
#   [magi] 2026-11-01 00:05 · XuZhunzhi
#
# Windows Terminal exports WT_PROFILE_ID for every session, so the profile name
# is looked up from its settings.json instead of being hardcoded. The PowerShell
# banner that normally sits above this is suppressed with -NoLogo on the profile
# commandline in settings.json.
#
# Skipped for non-interactive invocations (pwsh -Command / -EncodedCommand …),
# otherwise it would pollute the stdout of scripts that call pwsh.
# Delete this block for a silent shell.
# ---------------------------------------------------------------------------

function Get-MagiProfileName {
    $id = $env:WT_PROFILE_ID
    if (-not $id) { return $null }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
    )

    foreach ($path in $candidates) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $match = @($settings.profiles.list) | Where-Object { $_.guid -eq $id } | Select-Object -First 1
            if ($match -and $match.name) { return $match.name }
        } catch {
            # Unreadable or mid-edit settings.json: fall through to the plain greeting.
        }
    }
    return $null
}

$MagiArgs = [System.Environment]::GetCommandLineArgs()
$MagiInteractive = -not ($MagiArgs | Where-Object { $_ -in '-Command', '-c', '-EncodedCommand', '-ec' })

if ($MagiInteractive) {
    $MagiProfileName = Get-MagiProfileName
    if ($MagiProfileName) {
        Write-Host "[magi] $MagiProfileName" -ForegroundColor DarkGray
    }
    Write-Host ("[magi] {0} · {1}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm'), [System.Environment]::UserName) -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# uu — start / stop NetEase UU (GameViewer) remote streaming.
#
#   uu            same as uu on
#   uu on         enable the virtual display, start the service, launch the app
#   uu off        kill the app, stop the service, disable the virtual display
#   uu status     what is running right now
#
# Two things have to go away for the GPU to be released, and they are separate:
#   1. GameViewerService + the app processes
#   2. the "GameViewer Virtual Display Adapter" (ROOT\DISPLAY\0000), which stays
#      attached even after the service stops and keeps dwm compositing for a
#      second 144Hz screen (~27% GPU at idle).
# Stopping the service and disabling the device both need administrator rights,
# so off/on raise one UAC prompt each.
# ---------------------------------------------------------------------------

function uu {
    param(
        [ValidateSet('on', 'off', 'status')]
        [string]$Action = 'on'
    )

    $service = 'GameViewerService'
    $exe = 'C:\Program Files\Netease\GameViewer\bin\GameViewer.exe'
    $procFilter = 'GameViewer*'
    $displayMatch = '*GameViewer*'

    function Get-UuState {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        $procs = @(Get-Process -Name $procFilter -ErrorAction SilentlyContinue)
        # The UI (GameViewer.exe) is what the user means by "running"; the helper
        # processes can outlive it and must not count as "already running".
        $app = [bool](Get-Process -Name 'GameViewer' -ErrorAction SilentlyContinue)
        $disp = @()
        # A disabled adapter still shows up in Win32_VideoController, so ask the
        # PnP layer whether the device is actually OK before calling it attached.
        $dispDevice = @(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
                        Where-Object { $_.FriendlyName -like $displayMatch -and $_.Status -eq 'OK' })
        if ($dispDevice.Count -gt 0) {
            $disp = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -like $displayMatch })
        }
        [pscustomobject]@{
            Service = if ($svc) { $svc.Status } else { 'absent' }
            Procs   = $procs.Count
            App     = $app
            Display = $disp
        }
    }

    function Invoke-UuElevated {
        param([string]$Script)
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) {
            & powershell.exe -NoProfile -Command $Script
            return
        }
        Write-Host '[uu] administrator rights needed - accept the UAC prompt...' -ForegroundColor Yellow
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList @('-NoProfile', '-Command', $Script)
        } catch {
            Write-Host '[uu] elevation was declined' -ForegroundColor Red
        }
    }

    switch ($Action) {
        'on' {
            $state = Get-UuState

            # No elevation here on purpose: launching the app is enough, and the app
            # re-enables its own virtual display adapter (verified: a disabled
            # ROOT\DISPLAY\0000 comes back to OK just by starting GameViewer.exe).
            # Keep this path dependency-free so it can run from any session.

            if ($state.Service -ne 'Running') {
                Start-Service -Name $service -ErrorAction SilentlyContinue
            }

            if (-not $state.App) {
                if (-not (Test-Path -LiteralPath $exe)) {
                    Write-Host "[uu] not found: $exe" -ForegroundColor Red
                    return
                }
                Start-Process -FilePath $exe
            }

            Write-Host '[uu] starting...' -ForegroundColor Yellow
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Milliseconds 500
                $s = Get-UuState
                if ($s.Display.Count -gt 0 -and $s.Service -eq 'Running') { break }
            }

            $s = Get-UuState
            Write-Host "[uu] service=$($s.Service) processes=$($s.Procs)" -ForegroundColor DarkGray
            if ($s.Display.Count -gt 0) {
                $d = $s.Display[0]
                Write-Host "[uu] virtual display up: $($d.CurrentHorizontalResolution)x$($d.CurrentVerticalResolution) @ $($d.CurrentRefreshRate)Hz" -ForegroundColor DarkGray
            } else {
                Write-Host '[uu] virtual display not attached yet - open the app and check its settings' -ForegroundColor Yellow
            }
        }

        'off' {
            $state = Get-UuState
            if (-not $state.App -and $state.Service -ne 'Running' -and $state.Display.Count -eq 0) {
                Write-Host '[uu] already stopped' -ForegroundColor DarkGray
                return
            }

            Get-Process -Name $procFilter -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

            Invoke-UuElevated @"
Stop-Service -Name '$service' -Force -ErrorAction SilentlyContinue
Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
    Where-Object { `$_.FriendlyName -like '$displayMatch' } |
    Disable-PnpDevice -Confirm:`$false -ErrorAction SilentlyContinue
"@

            Start-Sleep -Milliseconds 1200
            $s = Get-UuState

            Write-Host "[uu] service=$($s.Service) processes=$($s.Procs)" -ForegroundColor DarkGray
            if ($s.Display.Count -eq 0) {
                Write-Host '[uu] virtual display disabled, GPU released' -ForegroundColor Green
            } else {
                Write-Host "[uu] virtual display still attached ($($s.Display[0].CurrentHorizontalResolution)x$($s.Display[0].CurrentVerticalResolution))" -ForegroundColor Yellow
                Write-Host '[uu] sign out or reboot to release it' -ForegroundColor Yellow
            }
        }

        'status' {
            $s = Get-UuState
            $appState = if ($s.App) { 'running' } else { 'not running' }
            $dispState = if ($s.Display.Count -gt 0) { 'attached' } else { 'disabled' }
            Write-Host "[uu] service=$($s.Service) app=$appState display=$dispState processes=$($s.Procs)" -ForegroundColor DarkGray
            Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $mark = ''
                    if ($_.Name -like $displayMatch) { $mark = '  <- UU virtual display' }
                    if ($_.CurrentHorizontalResolution) {
                        Write-Host ("     {0} {1}x{2} @ {3}Hz{4}" -f $_.Name, $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution, $_.CurrentRefreshRate, $mark)
                    } else {
                        Write-Host ("     {0} (disabled){1}" -f $_.Name, $mark)
                    }
                }
        }
    }
}
