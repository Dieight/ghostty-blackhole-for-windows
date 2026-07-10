param(
    [string]$TemplatePath = (Join-Path $PSScriptRoot '..\blackhole.pomodoro.hlsl'),
    [string]$OutputDirectory = (Join-Path $env:USERPROFILE '.terminal'),
    [string]$SettingsPath = '',
    [string]$StatePath = '',
    [int]$WorkMinutes = 45,
    [int]$BreakMinutes = 5,
    [int]$UpdateIntervalSec = 30,
    [switch]$Reset,
    [switch]$Once,
    [switch]$Status,
    [switch]$NoSettingsUpdate,
    [switch]$NoRestoreOnExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Format-HlslFloat([double]$Value) {
    return $Value.ToString('0.0000', [Globalization.CultureInfo]::InvariantCulture)
}

function Set-HlslConstant([string]$Source, [string]$Name, [string]$Value) {
    $pattern = "(static\s+const\s+(?:float|int)\s+$([regex]::Escape($Name))\s*=\s*)([^;]+)(;)"
    if ($Source -notmatch $pattern) {
        throw "Cannot find HLSL constant '$Name' in template."
    }
    return [regex]::Replace($Source, $pattern, "`${1}$Value`${3}", 1)
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Get-WrappedWtTimeSec {
    $freq = [Diagnostics.Stopwatch]::Frequency
    $wrapTicks = [int64]($freq * 1000)
    $ticks = [Diagnostics.Stopwatch]::GetTimestamp()
    return ($ticks % $wrapTicks) / [double]$freq
}

function Find-TerminalSettingsPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw 'Cannot find Windows Terminal settings.json. Pass -SettingsPath, or use -NoSettingsUpdate.'
}

function ConvertTo-JsonPathLiteral([string]$Path) {
    return $Path.Replace('\', '\\')
}

function Get-PixelShaderPath([string]$Path) {
    $raw = [IO.File]::ReadAllText($Path)
    $match = [regex]::Match($raw, '("experimental\.pixelShaderPath"\s*:\s*")([^"]*)(")')
    if (!$match.Success) {
        throw "Cannot find experimental.pixelShaderPath in '$Path'. Add that setting first, or run with -NoSettingsUpdate."
    }
    return $match.Groups[2].Value.Replace('\\', '\')
}

function Set-PixelShaderPath([string]$SettingsJsonPath, [string]$ShaderPath) {
    $raw = [IO.File]::ReadAllText($SettingsJsonPath)
    $jsonPath = ConvertTo-JsonPathLiteral $ShaderPath
    $pattern = '("experimental\.pixelShaderPath"\s*:\s*")([^"]*)(")'
    if ($raw -notmatch $pattern) {
        throw "Cannot find experimental.pixelShaderPath in '$SettingsJsonPath'."
    }
    $updated = [regex]::Replace($raw, $pattern, "`${1}$jsonPath`${3}", 1)
    Write-Utf8NoBom $SettingsJsonPath $updated
}

function Get-StartUtc([string]$Path, [switch]$ResetState) {
    if (!$ResetState -and (Test-Path -LiteralPath $Path)) {
        $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($state.PSObject.Properties.Name -contains 'StartUtc') {
            return [DateTime]::Parse(
                [string]$state.StartUtc,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AdjustToUniversal)
        }
    }

    $start = [DateTime]::UtcNow
    $stateText = @{ StartUtc = $start.ToString('o', [Globalization.CultureInfo]::InvariantCulture) } |
        ConvertTo-Json -Depth 2
    Write-Utf8NoBom $Path $stateText
    return $start
}

function New-ExternalShader(
    [string]$Template,
    [double]$PhaseSec,
    [double]$WtTimeSec,
    [int]$WorkMin,
    [int]$BreakMin,
    [int]$IntervalSec
) {
    $shader = $Template
    $shader = Set-HlslConstant $shader 'POMODORO_TIMER_MODE' 'POMODORO_TIMER_EXTERNAL'
    $shader = Set-HlslConstant $shader 'POMODORO_EXTERNAL_WORK_SEC' (Format-HlslFloat ($WorkMin * 60.0))
    $shader = Set-HlslConstant $shader 'POMODORO_EXTERNAL_BREAK_SEC' (Format-HlslFloat ($BreakMin * 60.0))
    $shader = Set-HlslConstant $shader 'POMODORO_EXTERNAL_PHASE_SEC' (Format-HlslFloat $PhaseSec)
    $shader = Set-HlslConstant $shader 'POMODORO_EXTERNAL_WT_TIME_SEC' (Format-HlslFloat $WtTimeSec)
    $shader = Set-HlslConstant $shader 'POMODORO_EXTERNAL_UPDATE_INTERVAL_SEC' (Format-HlslFloat $IntervalSec)
    return $shader
}

$TemplatePath = (Resolve-Path -LiteralPath $TemplatePath).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $OutputDirectory 'blackhole-pomodoro-state.json'
}

$template = Get-Content -LiteralPath $TemplatePath -Raw
$cycleSec = ($WorkMinutes + $BreakMinutes) * 60.0
$startUtc = Get-StartUtc $StatePath -ResetState:$Reset
$originalShaderPath = $null

if (!$NoSettingsUpdate) {
    if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
        $SettingsPath = Find-TerminalSettingsPath
    }
    $originalShaderPath = Get-PixelShaderPath $SettingsPath
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $SettingsPath -Destination "$SettingsPath.blackhole-helper-$stamp.bak" -Force
}

$slot = 0
if ($Status) {
    Write-Host "Template: $TemplatePath"
    Write-Host "State:    $StatePath"
    if (!$NoSettingsUpdate) {
        Write-Host "Settings: $SettingsPath"
        Write-Host "Original: $originalShaderPath"
    }
    Write-Host "Press Ctrl+C to stop. The original shader path is restored unless -NoRestoreOnExit is set."
}

try {
    while ($true) {
        $slot = 1 - $slot
        $suffix = if ($slot -eq 0) { 'a' } else { 'b' }
        $target = Join-Path $OutputDirectory "blackhole.external-$suffix.hlsl"
        $nowUtc = [DateTime]::UtcNow
        $elapsedSec = ($nowUtc - $startUtc).TotalSeconds
        $phaseSec = $elapsedSec % $cycleSec
        $wtTimeSec = Get-WrappedWtTimeSec

        $shader = New-ExternalShader $template $phaseSec $wtTimeSec $WorkMinutes $BreakMinutes $UpdateIntervalSec
        Write-Utf8NoBom $target $shader

        if (!$NoSettingsUpdate) {
            Set-PixelShaderPath $SettingsPath $target
        }

        $phaseText = ('{0:n1}/{1:n0}s' -f $phaseSec, $cycleSec)
        $wtText = ('{0:n1}s' -f $wtTimeSec)
        if ($Status) {
            Write-Host "$(Get-Date -Format HH:mm:ss) phase=$phaseText wt=$wtText file=$target"
        }
        if ($Once) {
            break
        }
        Start-Sleep -Seconds $UpdateIntervalSec
    }
}
finally {
    if (!$NoSettingsUpdate -and !$NoRestoreOnExit -and $originalShaderPath) {
        Set-PixelShaderPath $SettingsPath $originalShaderPath
        if ($Status) {
            Write-Host "Restored experimental.pixelShaderPath to $originalShaderPath"
        }
    }
}
