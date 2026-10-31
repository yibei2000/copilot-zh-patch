# GitHub Copilot 中文补丁 —— 注入器（Windows PowerShell 5.1）
# 作用：监听主程序的 WebView2 调试端口，把 patch.js 注入页面并保持生效。
# 由 launch.vbs 以隐藏窗口方式启动，主程序退出后自动结束。

param(
    [string]$PatchPath = '',
    [string]$LogPath = '',
    [int]$IdleExitMinutes = 480
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($PatchPath)) { $PatchPath = Join-Path $scriptDir 'patch.js' }
if ([string]::IsNullOrWhiteSpace($LogPath)) { $LogPath = Join-Path $scriptDir 'injector.log' }

$portFile = Join-Path $env:LOCALAPPDATA 'com.github.githubapp\EBWebView\DevToolsActivePort'
$appPath = 'D:\GitHub Copilot\github.exe'
$configPath = Join-Path $scriptDir 'config.json'
if (Test-Path -LiteralPath $configPath) {
    try {
        $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.appPath) { $appPath = [string]$cfg.appPath }
    } catch { }
}

# 单实例保护：同一时间只运行一个注入器
$mutex = New-Object System.Threading.Mutex($false, 'Local\GitHubCopilotZhInjector')
try {
    if (-not $mutex.WaitOne(0)) { exit 0 }
} catch {
    exit 0
}

function Write-Log([string]$message) {
    try {
        $line = '[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $message
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch { }
}

function Get-Port {
    if (-not (Test-Path -LiteralPath $portFile)) { return 0 }
    try {
        $line = (Get-Content -LiteralPath $portFile -TotalCount 1 -ErrorAction Stop).Trim()
        $n = 0
        if ([int]::TryParse($line, [ref]$n) -and $n -gt 0 -and $n -lt 65536) { return $n }
    } catch { }
    return 0
}

function Get-Targets([int]$port) {
    try {
        return @(Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/json/list" -f $port) -TimeoutSec 3 -ErrorAction Stop)
    } catch {
        return @()
    }
}

function Invoke-Cdp([string]$wsUrl, [string]$method, [hashtable]$params, [int]$timeoutMs = 20000) {
    $ws = $null
    $cts = $null
    try {
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $cts = New-Object System.Threading.CancellationTokenSource
        $cts.CancelAfter($timeoutMs)
        $ws.ConnectAsync([Uri]$wsUrl, $cts.Token).GetAwaiter().GetResult()

        $payload = @{ id = 1; method = $method; params = $params } | ConvertTo-Json -Depth 8 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $seg = [System.ArraySegment[byte]]::new($bytes)
        $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()

        $buffer = New-Object byte[] 65536
        $sb = New-Object System.Text.StringBuilder
        while ($true) {
            $recvSeg = [System.ArraySegment[byte]]::new($buffer)
            $res = $ws.ReceiveAsync($recvSeg, $cts.Token).GetAwaiter().GetResult()
            if ($res.Count -gt 0) { [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $res.Count)) }
            if ($res.EndOfMessage) {
                $text = $sb.ToString()
                [void]$sb.Clear()
                if ([string]::IsNullOrWhiteSpace($text)) { continue }
                $obj = $text | ConvertFrom-Json
                if ($null -ne $obj.id -and [int]$obj.id -eq 1) { return $obj }
            }
        }
    } catch {
        return $null
    } finally {
        if ($cts) { $cts.Dispose() }
        if ($ws) {
            try { $ws.Dispose() } catch { }
        }
    }
}

if (-not (Test-Path -LiteralPath $PatchPath)) {
    Write-Log "patch.js 不存在：$PatchPath"
    exit 1
}

$patch = [System.IO.File]::ReadAllText($PatchPath, [System.Text.Encoding]::UTF8)
$buildMatch = [regex]::Match($patch, 'copilot-zh build ([0-9a-f]+)')
$buildId = ''
if ($buildMatch.Success) { $buildId = $buildMatch.Groups[1].Value }
Write-Log ("启动注入器，构建 {0}，补丁 {1} 字节，主程序 {2}" -f $buildId, $patch.Length, $appPath)

$deadline = (Get-Date).AddMinutes($IdleExitMinutes)
$emptyCycles = 0
$lastPatchWrite = (Get-Item -LiteralPath $PatchPath).LastWriteTimeUtc

while ((Get-Date) -lt $deadline) {
    $running = @(Get-Process -Name 'github' -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -eq $appPath } catch { $false }
        })
    if ($running.Count -eq 0) {
        $emptyCycles++
        if ($emptyCycles -ge 15) {
            Write-Log '主程序已退出，注入器结束。'
            break
        }
        Start-Sleep -Seconds 2
        continue
    }
    $emptyCycles = 0

    # 补丁更新后自动重新加载（无需重启注入器）
    try {
        $stamp = (Get-Item -LiteralPath $PatchPath).LastWriteTimeUtc
        if ($stamp -ne $lastPatchWrite) {
            $lastPatchWrite = $stamp
            $patch = [System.IO.File]::ReadAllText($PatchPath, [System.Text.Encoding]::UTF8)
            $buildMatch = [regex]::Match($patch, 'copilot-zh build ([0-9a-f]+)')
            if ($buildMatch.Success) { $buildId = $buildMatch.Groups[1].Value }
            Write-Log ("检测到补丁更新，重新加载构建 {0}" -f $buildId)
        }
    } catch { }

    $port = Get-Port
    if ($port -le 0) { Start-Sleep -Seconds 1; continue }

    $targets = Get-Targets $port
    if ($targets.Count -eq 0) { Start-Sleep -Seconds 1; continue }

    foreach ($t in $targets) {
        if ($t.type -ne 'page') { continue }
        if ([string]$t.url -notmatch '^https?://tauri\.localhost') { continue }

        $check = Invoke-Cdp -wsUrl $t.webSocketDebuggerUrl -method 'Runtime.evaluate' -params @{
            expression    = 'window.__copilotZh && window.__copilotZh.version ? window.__copilotZh.version : null'
            returnByValue = $true
        }
        $installedVersion = $null
        if ($null -ne $check -and $null -ne $check.result -and $null -ne $check.result.result) {
            $installedVersion = $check.result.result.value
        }

        if ($installedVersion -ne $buildId -or [string]::IsNullOrEmpty($installedVersion)) {
            $result = Invoke-Cdp -wsUrl $t.webSocketDebuggerUrl -method 'Runtime.evaluate' -params @{
                expression    = $patch
                returnByValue = $true
                awaitPromise  = $true
            }
            if ($null -ne $result -and $null -ne $result.result) {
                if ($null -ne $result.result.exceptionDetails) {
                    Write-Log ("注入失败：{0}" -f ($result.result.exceptionDetails | ConvertTo-Json -Depth 4 -Compress))
                } else {
                    Write-Log ("已注入 {0} -> 构建 {1}，{2}" -f $t.url, $buildId, $result.result.result.value)
                }
            }
        }
    }

    Start-Sleep -Seconds 2
}

exit 0
