# GitHub Copilot 中文补丁 —— 卸载脚本
# 用法：双击 uninstall.cmd，或运行：
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1

$ErrorActionPreference = 'Stop'
$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $installDir 'install.json'

Write-Host ''
Write-Host '=== GitHub Copilot 中文补丁 · 卸载 ===' -ForegroundColor Cyan
Write-Host ''

# 1. 结束注入器进程
try {
    $injectors = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -like "*$installDir*inject.ps1*"
    }
    foreach ($proc in $injectors) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host ("已结束注入器进程 PID {0}" -f $proc.ProcessId)
    }
} catch { }

# 2. 还原快捷方式
if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $manifest.shortcuts) {
        $target = [string]$entry.path
        $backup = [string]$entry.backup
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $backup -Destination $target -Force
            Write-Host ("已还原快捷方式：{0}" -f $target)
        } elseif (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Force
            Write-Host ("已删除快捷方式：{0}" -f $target)
        }
    }
    if ($manifest.desktopShortcut -and (Test-Path -LiteralPath $manifest.desktopShortcut)) {
        Remove-Item -LiteralPath $manifest.desktopShortcut -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host '未找到安装记录（install.json），仅清理程序文件。' -ForegroundColor Yellow
}

# 3. 删除程序文件（等待注入器退出，重试几次）
Start-Sleep -Milliseconds 500
Set-Location $env:TEMP
$removed = $false
for ($i = 0; $i -lt 10; $i++) {
    try {
        Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction Stop
        $removed = $true
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}
if ($removed) {
    Write-Host '已删除补丁文件夹。'
} else {
    Write-Host ("清理文件夹失败：仍有进程占用 {0}" -f $installDir) -ForegroundColor Yellow
    Write-Host '请退出 GitHub Copilot 后，手动删除该文件夹。'
}

Write-Host ''
Write-Host '卸载完成。下次启动 GitHub Copilot 时即为英文界面。' -ForegroundColor Green
Write-Host ''
