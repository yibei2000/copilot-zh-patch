# GitHub Copilot 中文补丁 —— 重新构建 patch.js
# 用法：修改 dict.json / patterns.json 后运行本脚本，注入器会自动热加载新补丁（无需重启应用）。
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File rebuild.ps1

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$enginePath = Join-Path $dir 'engine.template.js'
$dictPath = Join-Path $dir 'dict.json'
$patternsPath = Join-Path $dir 'patterns.json'
$patchPath = Join-Path $dir 'patch.js'

Write-Host ''
Write-Host '=== 重建中文补丁 ===' -ForegroundColor Cyan

foreach ($p in @($enginePath, $dictPath, $patternsPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "缺少文件：$p" }
}

$engine = [System.IO.File]::ReadAllText($enginePath, [System.Text.Encoding]::UTF8)
$dictText = [System.IO.File]::ReadAllText($dictPath, [System.Text.Encoding]::UTF8).Trim()
$patternsText = [System.IO.File]::ReadAllText($patternsPath, [System.Text.Encoding]::UTF8).Trim()

$dict = $dictText | ConvertFrom-Json
$entryCount = @($dict.PSObject.Properties).Count
$patternCount = ($patternsText | ConvertFrom-Json).Length

$sha = [System.Security.Cryptography.SHA1]::Create()
$hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($engine + $dictText + $patternsText))
$buildId = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
$buildId = $buildId.Substring(0, 10)

$patch = $engine.Replace("/*__ZH_BUILD_ID__*/ ''", ('"' + $buildId + '"'))
$patch = $patch.Replace('/*__ZH_DICT__*/ {}', $dictText)
$patch = $patch.Replace('/*__ZH_PATTERNS__*/ []', $patternsText)

$header = "// copilot-zh build $buildId · entries=$entryCount · patterns=$patternCount`r`n"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($patchPath, $header + $patch, $utf8)

Write-Host ("已生成：{0}" -f $patchPath)
Write-Host ("构建 {0}，词典 {1} 条，规则 {2} 条，{3} 字节" -f $buildId, $entryCount, $patternCount, $patch.Length)
Write-Host '如果 GitHub Copilot 正在运行，界面会在约 2 秒内自动更新。' -ForegroundColor Green
Write-Host ''
