param(
    [string]$TemplatePath = (Join-Path $PSScriptRoot '..\blackhole.hlsl'),
    [string]$OutputDirectory = (Join-Path $env:USERPROFILE '.terminal'),
    [string]$SettingsPath = '',
    [string]$HistoryPath = (Join-Path $env:USERPROFILE '.codex\history.jsonl'),
    [string]$SessionRoot = (Join-Path $env:USERPROFILE '.codex\sessions'),
    [switch]$Once,
    [switch]$NoSettingsUpdate,
    [switch]$NoRestoreOnExit,
    [switch]$Status
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Toggle = 0
$script:LastFill = -1.0
$script:LastSessionPath = ''
$script:SettingsPath = $null
$script:OriginalShaderPath = $null
$watchers = $null

function Format-HlslFloat([double]$Value) {
    return $Value.ToString('0.0000', [Globalization.CultureInfo]::InvariantCulture)
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Set-HlslConstant([string]$Source, [string]$Name, [string]$Value) {
    $pattern = "(static\s+const\s+(?:float|int)\s+$([regex]::Escape($Name))\s*=\s*)([^;]+)(;)"
    if ($Source -notmatch $pattern) {
        throw "Cannot find HLSL constant '$Name' in template."
    }
    return [regex]::Replace($Source, $pattern, "`${1}$Value`${3}", 1)
}

function ConvertTo-JsonPathLiteral([string]$Path) {
    return $Path.Replace('\', '\\')
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
    throw 'Cannot find Windows Terminal settings.json. Pass -SettingsPath or use -NoSettingsUpdate.'
}

function Get-PixelShaderPath([string]$Path) {
    $raw = [IO.File]::ReadAllText($Path)
    $match = [regex]::Match($raw, '("experimental\.pixelShaderPath"\s*:\s*")([^"]*)(")')
    if (!$match.Success) {
        throw "Cannot find experimental.pixelShaderPath in '$Path'."
    }
    return $match.Groups[2].Value.Replace('\\', '\')
}

function Set-PixelShaderPath([string]$SettingsJsonPath, [string]$ShaderPath) {
    $raw = [IO.File]::ReadAllText($SettingsJsonPath)
    $pattern = '("experimental\.pixelShaderPath"\s*:\s*")([^"]*)(")'
    if ($raw -notmatch $pattern) {
        throw "Cannot find experimental.pixelShaderPath in '$SettingsJsonPath'."
    }
    $updated = [regex]::Replace($raw, $pattern, "`${1}$(ConvertTo-JsonPathLiteral $ShaderPath)`${3}", 1)
    Write-Utf8NoBom $SettingsJsonPath $updated
}

function Get-LatestSessionId([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) {
        return $null
    }
    $tail = Get-Content -LiteralPath $Path -Tail 8 -ErrorAction Stop
    for ($i = $tail.Count - 1; $i -ge 0; $i--) {
        $line = $tail[$i].Trim()
        if (!$line) {
            continue
        }
        if ($line -match '"session_id"\s*:\s*"([^"]+)"') {
            return $Matches[1]
        }
        if ($line -match '"payload"\s*:\s*\{.*?"session_id"\s*:\s*"([^"]+)"') {
            return $Matches[1]
        }
    }
    return $null
}

function Find-SessionFile([string]$Root, [string]$SessionId) {
    if (!(Test-Path -LiteralPath $Root)) {
        return $null
    }
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.jsonl -ErrorAction SilentlyContinue
    if ($SessionId) {
        $match = $files | Where-Object { $_.Name -like "*$SessionId*" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }
    $latest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        return $latest.FullName
    }
    return $null
}

function Get-TokenCount([object]$Usage) {
    if (!$Usage) {
        return $null
    }
    if ($Usage.PSObject.Properties.Name -contains 'total_tokens' -and $Usage.total_tokens -ne $null) {
        $total = [double]$Usage.total_tokens
    # cached_input_tokens is a subset of input_tokens in Codex token_count
    # events. Adding both would double-count cached context.
    } elseif ($Usage.PSObject.Properties.Name -contains 'input_tokens' -and $Usage.input_tokens -ne $null) {
        $total = [double]$Usage.input_tokens
        if ($Usage.PSObject.Properties.Name -contains 'output_tokens' -and $Usage.output_tokens -ne $null) {
            $total += [double]$Usage.output_tokens
        }
    } else {
        $total = 0.0
    }
    if ($total -le 0.0) {
        return $null
    }
    return $total
}

function Get-SessionContextStats([string]$SessionPath) {
    $sessionId = ''
    $windowTokens = 0.0
    $usedTokens = 0.0
    $haveUsage = $false
    $tokenObj = $null
    $current = $null

    if ($SessionPath -and (Test-Path -LiteralPath $SessionPath)) {
        $firstLine = Get-Content -LiteralPath $SessionPath -TotalCount 1 -ErrorAction Stop
        if ($firstLine) {
            $line = $firstLine.Trim()
            if ($line -match '"session_id"\s*:\s*"([^"]+)"') {
                $sessionId = $Matches[1]
            } else {
                try {
                    $firstObj = $line | ConvertFrom-Json
                    if ($firstObj.type -eq 'session_meta' -and $firstObj.payload.session_id) {
                        $sessionId = [string]$firstObj.payload.session_id
                    }
                } catch {
                }
            }
        }

        # The session file is appended while this helper runs, so scan the tail
        # backwards and skip any line that is still being written.
        $tail = @(Get-Content -LiteralPath $SessionPath -Tail 4096 -ErrorAction Stop)
        for ($i = $tail.Count - 1; $i -ge 0; $i--) {
            $raw = $tail[$i].Trim()
            if ($raw -notmatch '^[{]"timestamp":"[^"]+","type":"event_msg","payload":[{]"type":"token_count"') {
                continue
            }
            try {
                $candidate = $raw | ConvertFrom-Json
            } catch {
                continue
            }
            if ($candidate.type -eq 'event_msg' -and $candidate.payload.type -eq 'token_count') {
                $tokenObj = $candidate
                break
            }
        }
        if ($tokenObj) {
            if ($tokenObj.payload.info.model_context_window) {
                $windowTokens = [double]$tokenObj.payload.info.model_context_window
            }
            $current = Get-TokenCount $tokenObj.payload.info.last_token_usage
            if ($current -eq $null) {
                $current = Get-TokenCount $tokenObj.payload.info.total_token_usage
            }
            if ($current -ne $null) {
                $usedTokens = [double]$current
                $haveUsage = $true
            }
        }
    }

    if ($windowTokens -le 0.0) {
        $windowTokens = 258400.0
    }
    if ($usedTokens -lt 0.0) {
        $usedTokens = 0.0
    }

    $fill = 0.0
    if ($haveUsage -and $windowTokens -gt 0.0) {
        $fill = [Math]::Min(1.0, [Math]::Max(0.0, $usedTokens / $windowTokens))
    }

    [pscustomobject]@{
        SessionId    = $sessionId
        SessionPath  = $SessionPath
        UsedTokens   = [int][Math]::Round($usedTokens)
        WindowTokens = [int][Math]::Round($windowTokens)
        Fill         = $fill
    }
}

function Initialize-Settings {
    if ($NoSettingsUpdate) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($script:SettingsPath)) {
        $script:SettingsPath = Find-TerminalSettingsPath
    }
    $script:OriginalShaderPath = Get-PixelShaderPath $script:SettingsPath
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $script:SettingsPath -Destination "$($script:SettingsPath).context-$stamp.bak" -Force
}

function Update-ContextShader {
    $sessionId = Get-LatestSessionId $HistoryPath
    $sessionPath = Find-SessionFile $SessionRoot $sessionId
    $stats = Get-SessionContextStats $sessionPath
    $level = [Math]::Round($stats.Fill, 4)

    if ([Math]::Abs($level - $script:LastFill) -lt 0.0001 -and $sessionPath -eq $script:LastSessionPath) {
        return
    }

    $templatePathResolved = (Resolve-Path -LiteralPath $TemplatePath).Path
    $template = Get-Content -LiteralPath $templatePathResolved -Raw
    $shader = Set-HlslConstant $template 'CONTEXT_LEVEL' (Format-HlslFloat $level)

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $script:Toggle = 1 - $script:Toggle
    $suffix = if ($script:Toggle -eq 0) { 'a' } else { 'b' }
    $target = Join-Path $OutputDirectory "blackhole.context-$suffix.hlsl"
    Write-Utf8NoBom $target $shader

    if (!$NoSettingsUpdate) {
        Set-PixelShaderPath $script:SettingsPath $target
    }

    $script:LastFill = $level
    $script:LastSessionPath = $sessionPath

    if ($Status) {
        $sessionLabel = if ($stats.SessionId) { $stats.SessionId } else { 'unknown' }
        $pathLabel = if ($sessionPath) { $sessionPath } else { 'none' }
        $idLabel = if ($sessionId) { $sessionId } else { 'none' }
        Write-Host ("{0} sid={1} path={2} session={3} fill={4:P1} used={5:n0}/{6:n0} file={7}" -f `
            (Get-Date -Format HH:mm:ss), $idLabel, $pathLabel, $sessionLabel, $level, $stats.UsedTokens, $stats.WindowTokens, $target)
    }
}

function Register-ContextWatchers {
    $watchers = @()
    $source = 'CodexContextChanged'

    if (Test-Path -LiteralPath $HistoryPath) {
        $historyDir = [IO.Path]::GetDirectoryName($HistoryPath)
        $historyLeaf = [IO.Path]::GetFileName($HistoryPath)
        $historyWatcher = New-Object System.IO.FileSystemWatcher($historyDir, $historyLeaf)
        $historyWatcher.IncludeSubdirectories = $false
        $historyWatcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
        $historyWatcher.EnableRaisingEvents = $true
        foreach ($eventName in @('Changed', 'Created', 'Renamed', 'Deleted')) {
            Register-ObjectEvent -InputObject $historyWatcher -EventName $eventName `
                -SourceIdentifier "$source.History.$eventName" | Out-Null
        }
        $watchers += $historyWatcher
    }

    if (Test-Path -LiteralPath $SessionRoot) {
        $sessionWatcher = New-Object System.IO.FileSystemWatcher($SessionRoot, '*.jsonl')
        $sessionWatcher.IncludeSubdirectories = $true
        $sessionWatcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
        $sessionWatcher.EnableRaisingEvents = $true
        foreach ($eventName in @('Changed', 'Created', 'Renamed', 'Deleted')) {
            Register-ObjectEvent -InputObject $sessionWatcher -EventName $eventName `
                -SourceIdentifier "$source.Session.$eventName" | Out-Null
        }
        $watchers += $sessionWatcher
    }

    return $watchers
}

function Cleanup-ContextWatchers([System.Collections.Generic.List[System.IDisposable]]$Watchers) {
    foreach ($subscriber in Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like 'CodexContextChanged.*' }) {
        try { Unregister-Event -SubscriptionId $subscriber.SubscriptionId -ErrorAction SilentlyContinue } catch {}
    }
    foreach ($watcher in $Watchers) {
        try { $watcher.Dispose() } catch {}
    }
}

try {
    if (!$NoSettingsUpdate) {
        Initialize-Settings
    }

    Update-ContextShader
    if ($Once) {
        return
    }

    $watchers = [System.Collections.Generic.List[System.IDisposable]]::new()
    foreach ($watcher in (Register-ContextWatchers)) {
        [void]$watchers.Add($watcher)
    }

    while ($true) {
        $event = Wait-Event
        if ($null -ne $event) {
            Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 100
            Update-ContextShader
        }
    }
}
finally {
    if ($watchers) {
        Cleanup-ContextWatchers $watchers
    }
    if (!$NoSettingsUpdate -and !$NoRestoreOnExit -and $script:OriginalShaderPath) {
        try {
            Set-PixelShaderPath $script:SettingsPath $script:OriginalShaderPath
        } catch {
            if ($Status) {
                Write-Host "Failed to restore experimental.pixelShaderPath: $($_.Exception.Message)"
            }
        }
    }
}
