<#
.SYNOPSIS
    Install the MAGI amber-CRT look into Windows Terminal.

.DESCRIPTION
    Applies the shaders, the Ark Pixel font, the "Cool Retro Amber" colour scheme,
    the MAGI / MAGI·AMBER profiles, the shader shortcuts and
    compatibility.ambiguousWidth to Windows Terminal's settings.json.

    Idempotent: profiles are matched by GUID and the colour scheme by name, so
    running it again updates in place instead of adding duplicates. Every file it
    modifies is backed up first, and everything else in settings.json is preserved.

.PARAMETER FontSource
    Directory containing the four ark-pixel-12px-monospaced-*.ttf files.
    Optional when the fonts are already registered for the current user.

.PARAMETER Target
    Which installed Windows Terminal package to patch: All (default), Stable, Preview.

.PARAMETER SettingsPath
    Patch this settings.json instead of the installed packages.

.PARAMETER SkipFonts
.PARAMETER SkipShaders
.PARAMETER KeepDefaultProfile
.PARAMETER DryRun

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-magi-terminal.ps1 -DryRun

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-magi-terminal.ps1 `
        -FontSource "$env:TEMP\ark-pixel-font\ark-pixel-font-12px-monospaced-ttf"
#>

[CmdletBinding()]
param(
    [string]$FontSource,
    [ValidateSet('All', 'Stable', 'Preview')]
    [string]$Target = 'All',
    [string]$SettingsPath,
    [switch]$SkipFonts,
    [switch]$SkipShaders,
    [switch]$KeepDefaultProfile,
    [switch]$FullShader,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot

# ---------------------------------------------------------------- constants ----
$SchemeName     = 'Cool Retro Amber'
$NameReadable   = 'MAGI'
$NameAmber      = 'MAGI·AMBER'
$GuidReadable   = '{c50c5efb-383d-4a1e-81fa-e7df259a1399}'
$GuidAmber      = '{64d9f64b-14cf-4548-8056-a86c8cb20f74}'
$FontFace       = 'Ark Pixel 12px Mono zh_cn, Ark Pixel 12px Mono ja, Ark Pixel 12px Mono ko, Ark Pixel 12px Mono latin'
$FontSize       = 18
$ShaderReadable = 'cool-retro-frame-readable.hlsl'
$ShaderAmber    = 'cool-retro-frame-amber.hlsl'
$ShaderLite     = 'cool-retro-frame-lite.hlsl'

$ShaderDir = Join-Path $env:LOCALAPPDATA 'WindowsTerminalShaders'
$FontDir   = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$FontReg   = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

$FontFiles = @(
    @{ Name = 'Ark Pixel 12px Mono latin (TrueType)'; File = 'ark-pixel-12px-monospaced-latin.ttf' }
    @{ Name = 'Ark Pixel 12px Mono zh_cn (TrueType)'; File = 'ark-pixel-12px-monospaced-zh_cn.ttf' }
    @{ Name = 'Ark Pixel 12px Mono ja (TrueType)';    File = 'ark-pixel-12px-monospaced-ja.ttf' }
    @{ Name = 'Ark Pixel 12px Mono ko (TrueType)';    File = 'ark-pixel-12px-monospaced-ko.ttf' }
)

$Scheme = [ordered]@{
    name                = $SchemeName
    background          = '#0B0703'
    foreground          = '#E88918'
    cursorColor         = '#FFAD32'
    selectionBackground = '#4A3318'
    black               = '#0B0703'
    red                 = '#FF3B30'
    green               = '#00FF66'
    yellow              = '#E8A018'
    blue                = '#00AAFF'
    purple              = '#FF66CC'
    cyan                = '#00FFFF'
    white               = '#C9BBA6'
    brightBlack         = '#6B4A24'
    brightRed           = '#FF6B5F'
    brightGreen         = '#6DFF9C'
    brightYellow        = '#FFC04A'
    brightBlue          = '#66CCFF'
    brightPurple        = '#FF99DD'
    brightCyan          = '#80FFFF'
    brightWhite         = '#FFF0D0'
}

# ----------------------------------------------------------------- helpers ----
function Write-Step { param([string]$Message) Write-Host "[magi] $Message" -ForegroundColor Cyan }
function Write-Note { param([string]$Message) Write-Host "[magi] $Message" -ForegroundColor DarkGray }
function Write-Plan { param([string]$Message) if ($DryRun) { Write-Host "[dry-run] $Message" } }
function Write-Warn { param([string]$Message) Write-Host "[warn] $Message" -ForegroundColor Yellow }

function Get-ShaderPath { param([string]$FileName) Join-Path $ShaderDir $FileName }

function New-ProfileTemplate {
    param([string]$Name, [string]$Guid, [string]$ShaderFile, [string]$PwshPath)

    $profile = [ordered]@{
        antialiasingMode                   = 'aliased'
        colorScheme                        = $SchemeName
        cursorHeight                       = 25
        cursorShape                        = 'filledBox'
        'experimental.pixelShaderPath'     = (Get-ShaderPath -FileName $ShaderFile)
        'experimental.retroTerminalEffect' = $false
        font                               = [ordered]@{
            builtinGlyphs = $true
            face          = $FontFace
            size          = $FontSize
            weight        = 'normal'
        }
        guid                               = $Guid
        hidden                             = $false
        icon                               = [string][char]0xE756
        name                               = $Name
        opacity                            = 100
        useAcrylic                         = $false
    }

    # -NoLogo suppresses the engine banner ("PowerShell 7.6.9" + copyright). That
    # banner is printed before $PROFILE runs, so without this it sits above any
    # greeting a profile prints. Only these two profiles are affected.
    if ($PwshPath) { $profile['commandline'] = "$PwshPath -NoLogo" }

    return [pscustomobject]$profile
}

function Set-Property {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Install-Shaders {
    if ($SkipShaders) { Write-Note 'Skipping shaders (-SkipShaders).'; return }

    $needed = @($ShaderAmber, $ShaderReadable, $ShaderLite)
    $missing = @($needed | Where-Object { -not (Test-Path -LiteralPath (Get-ShaderPath -FileName $_)) })

    if ($missing.Count -eq 0) {
        Write-Note "Shaders already present in $ShaderDir."
        return
    }

    Write-Step "Copying shaders to $ShaderDir"
    foreach ($file in $needed) {
        $source = Join-Path $RepoRoot "shaders\$file"
        if (-not (Test-Path -LiteralPath $source)) { throw "Repository is missing shaders\$file" }
        Write-Plan "Would copy $file"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $ShaderDir | Out-Null
            Copy-Item -LiteralPath $source -Destination (Get-ShaderPath -FileName $file) -Force
        }
    }
}

function Install-Fonts {
    if ($SkipFonts) { Write-Note 'Skipping fonts (-SkipFonts).'; return }

    $registered = @($FontFiles | Where-Object {
        $null -ne (Get-ItemProperty -Path $FontReg -Name $_.Name -ErrorAction SilentlyContinue)
    })

    $source = $null
    if ($FontSource) {
        if (-not (Test-Path -LiteralPath $FontSource -PathType Container)) {
            throw "FontSource directory not found: $FontSource"
        }
        $source = $FontSource
    } else {
        $bundled = Join-Path $RepoRoot 'fonts'
        if (Test-Path -LiteralPath $bundled -PathType Container) { $source = $bundled }
    }

    if (-not $source) {
        if ($registered.Count -eq $FontFiles.Count) {
            Write-Note 'Ark Pixel fonts are already registered; nothing to install.'
        } else {
            Write-Warn 'Fonts not found and not all of them are registered.'
            Write-Warn 'Pass -FontSource <dir> with the four ark-pixel-12px-monospaced-*.ttf files,'
            Write-Warn 'or Windows Terminal will report "font not found" for the new profiles.'
        }
        return
    }

    Write-Step "Installing Ark Pixel fonts from $source"
    New-Item -ItemType Directory -Force -Path $FontDir | Out-Null

    foreach ($font in $FontFiles) {
        $file = Join-Path $source $font.File
        if (-not (Test-Path -LiteralPath $file)) {
            Write-Warn "Missing $($font.File) in $source - skipping the font step."
            return
        }

        $target = Join-Path $FontDir $font.File
        Write-Plan "Would install and register $($font.File)"

        if ($DryRun) { continue }

        New-Item -Path $FontReg -Force | Out-Null
        # A font that is already loaded stays memory-mapped and cannot be replaced.
        try {
            Copy-Item -LiteralPath $file -Destination $target -Force
        } catch {
            if (-not (Test-Path -LiteralPath $target)) { throw }
            Write-Warn "Could not replace $target (in use). Keeping the installed copy."
        }
        New-ItemProperty -Path $FontReg -Name $font.Name -Value $font.File -PropertyType String -Force | Out-Null
    }

    if ($DryRun) { return }

    # Writing the HKCU entries alone is not enough: per-user fonts are loaded at
    # logon, so the running session still has none of them.
    try {
        Add-Type -Namespace Magi.Win32 -Name Native -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int AddFontResource(string lpFilename);

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(
    System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
"@
        foreach ($font in $FontFiles) {
            [void][Magi.Win32.Native]::AddFontResource((Join-Path $FontDir $font.File))
        }
        $result = [UIntPtr]::Zero
        [void][Magi.Win32.Native]::SendMessageTimeout([IntPtr]0xFFFF, 0x001D, [UIntPtr]::Zero, $null, 0x0002, 1000, [ref]$result)
        Write-Note 'Fonts loaded into the current session.'
    } catch {
        Write-Warn 'Fonts were copied but loading them into this session failed; sign out and back in.'
    }
}

function Update-SettingsFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Warn "Not found, skipping: $Path"
        return
    }

    Write-Step "Patching $Path"

    $settings = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json

    # --- pwsh path -------------------------------------------------------------
    $pwshPath = $null
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCommand) { $pwshPath = $pwshCommand.Source }
    if (-not $pwshPath) { Write-Warn 'pwsh.exe not on PATH; the profiles will keep their current commandline.' }

    # --- profiles --------------------------------------------------------------
    if (-not $settings.PSObject.Properties['profiles']) {
        Set-Property -Object $settings -Name 'profiles' -Value ([pscustomobject]@{})
    }
    if (-not $settings.profiles.PSObject.Properties['list']) {
        Set-Property -Object $settings.profiles -Name 'list' -Value @()
    }

    # The everyday profile uses the lite shader (~20 texture taps/pixel) unless
    # -FullShader is passed, in which case it keeps the upstream 174-tap original.
    $everydayShader = $ShaderLite
    if ($FullShader) { $everydayShader = $ShaderReadable }

    $wanted = @(
        (New-ProfileTemplate -Name $NameAmber    -Guid $GuidAmber    -ShaderFile $ShaderAmber      -PwshPath $pwshPath)
        (New-ProfileTemplate -Name $NameReadable -Guid $GuidReadable -ShaderFile $everydayShader   -PwshPath $pwshPath)
    )

    $list = @($settings.profiles.list)
    foreach ($template in $wanted) {
        $index = -1
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($list[$i] -and $list[$i].guid -eq $template.guid) { $index = $i; break }
        }
        if ($index -ge 0) {
            Write-Plan "Would update profile '$($template.name)'"
            $list[$index] = $template
        } else {
            Write-Plan "Would add profile '$($template.name)'"
            $list += $template
        }
    }
    Set-Property -Object $settings.profiles -Name 'list' -Value $list

    # --- colour scheme ---------------------------------------------------------
    $schemes = @()
    if ($settings.PSObject.Properties['schemes']) { $schemes = @($settings.schemes) }

    $schemeIndex = -1
    for ($i = 0; $i -lt $schemes.Count; $i++) {
        if ($schemes[$i] -and $schemes[$i].name -eq $SchemeName) { $schemeIndex = $i; break }
    }
    $schemeObject = [pscustomobject]$Scheme
    if ($schemeIndex -ge 0) {
        Write-Plan "Would update scheme '$SchemeName'"
        $schemes[$schemeIndex] = $schemeObject
    } else {
        Write-Plan "Would add scheme '$SchemeName'"
        $schemes += $schemeObject
    }
    Set-Property -Object $settings -Name 'schemes' -Value @($schemes)

    # --- keybindings -----------------------------------------------------------
    $bindingKey = 'actions'
    if ($settings.PSObject.Properties['keybindings']) { $bindingKey = 'keybindings' }
    elseif (-not $settings.PSObject.Properties['actions']) { $bindingKey = 'keybindings' }

    $bindings = @()
    if ($settings.PSObject.Properties[$bindingKey]) { $bindings = @($settings.$bindingKey) }

    foreach ($wantedBinding in @(
        [pscustomobject]@{ id = 'Terminal.ToggleShaderEffects'; keys = 'shift+f10' }
        [pscustomobject]@{ id = 'Terminal.ToggleFocusMode';     keys = 'shift+f11' }
    )) {
        # Windows Terminal rewrites these into the modern "id" form, so match on the
        # key combination rather than on command/id.
        $taken = $null
        foreach ($binding in $bindings) {
            if ($binding.keys -and $binding.keys -eq $wantedBinding.keys) { $taken = $binding; break }
        }
        if ($taken) {
            $takenName = $taken.id
            if (-not $takenName) { $takenName = $taken.command }
            if ($takenName -ne $wantedBinding.id) {
                Write-Warn "$($wantedBinding.keys) is already used by '$takenName'; leaving it alone."
            }
            continue
        }
        Write-Plan "Would bind $($wantedBinding.keys) to $($wantedBinding.id)"
        $bindings += $wantedBinding
    }
    Set-Property -Object $settings -Name $bindingKey -Value @($bindings)

    # --- compatibility.ambiguousWidth -----------------------------------------
    Set-Property -Object $settings -Name 'compatibility.ambiguousWidth' -Value 'wide'
    if ($settings.PSObject.Properties['compatibility']) {
        Set-Property -Object $settings.compatibility -Name 'ambiguousWidth' -Value 'wide'
    }
    Write-Plan 'Would set compatibility.ambiguousWidth = wide'

    # --- default profile -------------------------------------------------------
    if (-not $KeepDefaultProfile) {
        Set-Property -Object $settings -Name 'defaultProfile' -Value $GuidReadable
        Write-Plan "Would set defaultProfile = $NameReadable"
    }

    if ($DryRun) { return }

    $backup = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    Write-Note "Backup: $backup"

    $json = $settings | ConvertTo-Json -Depth 100
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $encoding)

    # Re-read, so we never hand Windows Terminal a file it cannot load.
    $check = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Step ("Written. profiles={0} schemes={1} ambiguousWidth={2}" -f `
        @($check.profiles.list).Count, @($check.schemes).Count, $check.'compatibility.ambiguousWidth')
}

# -------------------------------------------------------------------- main ----
Write-Step "MAGI terminal setup (DryRun=$DryRun, Target=$Target)"

Install-Shaders
Install-Fonts

$targets = @()
if ($SettingsPath) {
    $targets = @($SettingsPath)
} else {
    $candidates = @(
        @{ Name = 'Stable';  Path = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json') }
        @{ Name = 'Preview'; Path = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json') }
    )
    foreach ($candidate in $candidates) {
        if ($Target -ne 'All' -and $Target -ne $candidate.Name) { continue }
        if (Test-Path -LiteralPath $candidate.Path) { $targets += $candidate.Path }
    }
}

if ($targets.Count -eq 0) {
    Write-Warn 'No Windows Terminal settings.json found. Open Windows Terminal once, or pass -SettingsPath.'
    exit 1
}

foreach ($path in $targets) { Update-SettingsFile -Path $path }

Write-Step 'Done. Restart Windows Terminal to pick up the changes.'
Write-Note 'Windows Terminal 1.26+ is required for compatibility.ambiguousWidth; 1.24 and older ignore it.'
