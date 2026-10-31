# GitHub Copilot 中文补丁 —— 安装脚本
# 用法（在补丁目录中）：
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1
# 可选参数：
#   -AppPath "D:\GitHub Copilot\github.exe"   指定主程序路径
#   -NoShortcuts                             只安装运行文件，不改快捷方式

param(
    [string]$AppPath = '',
    [switch]$NoShortcuts
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $root
$installDir = Join-Path $env:LOCALAPPDATA 'GitHubCopilotZh'
$backupDir = Join-Path $installDir 'backup'

Write-Host ''
Write-Host '=== GitHub Copilot 中文补丁 · 安装 ===' -ForegroundColor Cyan
Write-Host ''

# ---------- 1. 定位主程序 ----------
if ([string]::IsNullOrWhiteSpace($AppPath)) {
    $candidates = @('D:\GitHub Copilot\github.exe', (Join-Path $env:LOCALAPPDATA 'Programs\GitHub Copilot\github.exe'))
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $AppPath = $c; break } }
}
if ([string]::IsNullOrWhiteSpace($AppPath)) {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'GitHub Copilot.lnk'
    if (Test-Path -LiteralPath $lnk) {
        $shProbe = New-Object -ComObject WScript.Shell
        $scProbe = $shProbe.CreateShortcut($lnk)
        if ($scProbe.TargetPath -and (Test-Path -LiteralPath $scProbe.TargetPath) -and $scProbe.TargetPath -like '*github.exe') {
            $AppPath = $scProbe.TargetPath
        }
    }
}
if ([string]::IsNullOrWhiteSpace($AppPath) -or -not (Test-Path -LiteralPath $AppPath)) {
    throw '找不到 GitHub Copilot 主程序（github.exe）。请用 -AppPath 参数指定。'
}
$AppPath = (Resolve-Path -LiteralPath $AppPath).Path
Write-Host ("主程序：{0}" -f $AppPath)

# ---------- 2. 复制运行文件 ----------
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$utf16 = New-Object System.Text.UnicodeEncoding($false, $true)
$ascii = New-Object System.Text.ASCIIEncoding

function Copy-TextFile([string]$source, [string]$dest, $encoding) {
    if (-not (Test-Path -LiteralPath $source)) { throw "缺少文件：$source" }
    $text = [System.IO.File]::ReadAllText($source, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($dest, $text, $encoding)
}

Copy-TextFile (Join-Path $projectRoot 'src\engine.js') (Join-Path $installDir 'engine.template.js') $utf8
Copy-TextFile (Join-Path $projectRoot 'src\dict.json') (Join-Path $installDir 'dict.json') $utf8
Copy-TextFile (Join-Path $projectRoot 'src\patterns.json') (Join-Path $installDir 'patterns.json') $utf8
Copy-TextFile (Join-Path $root 'inject.ps1') (Join-Path $installDir 'inject.ps1') $utf8Bom
Copy-TextFile (Join-Path $root 'rebuild.ps1') (Join-Path $installDir 'rebuild.ps1') $utf8Bom
Copy-TextFile (Join-Path $root 'uninstall.ps1') (Join-Path $installDir 'uninstall.ps1') $utf8Bom
Copy-TextFile (Join-Path $root 'launch.vbs') (Join-Path $installDir 'launch.vbs') $utf16
Copy-TextFile (Join-Path $root 'rebuild.cmd') (Join-Path $installDir 'rebuild.cmd') $ascii
Copy-TextFile (Join-Path $root 'uninstall.cmd') (Join-Path $installDir 'uninstall.cmd') $ascii
if (Test-Path -LiteralPath (Join-Path $projectRoot 'README.md')) {
    Copy-TextFile (Join-Path $projectRoot 'README.md') (Join-Path $installDir 'README.md') $utf8Bom
}

$config = [ordered]@{
    appPath     = $AppPath
    installedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    version     = '1.0.0'
}
[System.IO.File]::WriteAllText((Join-Path $installDir 'config.json'), ($config | ConvertTo-Json), $utf8)
Write-Host ("已安装到：{0}" -f $installDir)

# ---------- 3. 生成 patch.js ----------
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installDir 'rebuild.ps1') | Out-Host
if (-not (Test-Path -LiteralPath (Join-Path $installDir 'patch.js'))) { throw 'patch.js 生成失败。' }

# ---------- 4. 改写快捷方式 ----------
$entries = @()
if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
    $launchVbs = Join-Path $installDir 'launch.vbs'

    $shortcuts = @()
    $desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'GitHub Copilot.lnk'
    if (Test-Path -LiteralPath $desktopLnk) { $shortcuts += $desktopLnk }

    foreach ($menuRoot in @((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'), (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'))) {
        if (Test-Path -LiteralPath $menuRoot) {
            $shortcuts += @(Get-ChildItem -LiteralPath $menuRoot -Filter 'GitHub Copilot*.lnk' -Recurse -Depth 3 -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }

    foreach ($path in ($shortcuts | Select-Object -Unique)) {
        $sc = $shell.CreateShortcut($path)
        $target = [string]$sc.TargetPath
        $args = [string]$sc.Arguments

        if ($args -like '*launch.vbs*') {
            Write-Host ("跳过（已是中文版）：{0}" -f $path)
            continue
        }
        if ($target -notlike '*github.exe') {
            Write-Host ("跳过（非 GitHub Copilot 快捷方式）：{0}" -f $path)
            continue
        }

        $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $safe = ($name -replace '[^\w\u4e00-\u9fa5\-]', '_')
        $backup = Join-Path $backupDir ("{0}-{1}.lnk" -f $safe, ($entries.Count + 1))
        Copy-Item -LiteralPath $path -Destination $backup -Force

        $sc.TargetPath = $wscript
        $sc.Arguments = '"{0}"' -f $launchVbs
        $sc.WorkingDirectory = (Split-Path -Parent $AppPath)
        $sc.IconLocation = '{0},0' -f $AppPath
        $sc.Description = 'GitHub Copilot（简体中文补丁）'
        $sc.WindowStyle = 1
        $sc.Save()

        $entries += [ordered]@{ path = $path; backup = $backup }
        Write-Host ("已更新快捷方式：{0}" -f $path)
    }
}

# ---------- 5. 写入安装记录 ----------
$manifestPath = Join-Path $installDir 'install.json'
if ($NoShortcuts -and (Test-Path -LiteralPath $manifestPath)) {
    try { $entries = @((Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).shortcuts) } catch { }
}

$manifest = [ordered]@{
    installDir  = $installDir
    appPath     = $AppPath
    installedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    shortcuts   = $entries
}
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), $utf8)

Write-Host ''
Write-Host '安装完成。' -ForegroundColor Green
Write-Host '请先退出正在运行的 GitHub Copilot（托盘图标 → Quit），再双击桌面快捷方式启动。'
Write-Host ''
