' ============================================================
'  GitHub Copilot 中文补丁 —— 启动器
'  作用：带 WebView2 调试端口启动 GitHub Copilot，并启动隐藏的注入器。
'  说明：仅监听本机 127.0.0.1 的随机端口，退出程序后端口即关闭。
' ============================================================
Option Explicit

Dim sh, fso, scriptDir, configFile, configText, appPath, appDir
Dim wmi, procs, p, running, msg, portFile, injectorPath

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
configFile = fso.BuildPath(scriptDir, "config.json")

If Not fso.FileExists(configFile) Then
    MsgBox "缺少配置文件：" & configFile, 16, "GitHub Copilot 中文补丁"
    WScript.Quit 1
End If

configText = ReadUtf8(configFile)
appPath = ExtractJsonString(configText, "appPath")

If Len(appPath) = 0 Then
    MsgBox "配置中缺少 appPath。", 16, "GitHub Copilot 中文补丁"
    WScript.Quit 1
End If

If Not fso.FileExists(appPath) Then
    MsgBox "找不到 GitHub Copilot：" & appPath & vbCrLf & vbCrLf & _
           "应用可能已更新或移动，请重新运行安装脚本。", 16, "GitHub Copilot 中文补丁"
    WScript.Quit 1
End If

' —— 已经运行时，提示用户先退出（否则拿不到新的调试端口）——
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
Set procs = wmi.ExecQuery("SELECT ProcessId, ExecutablePath FROM Win32_Process WHERE Name='github.exe'")
running = False
For Each p In procs
    On Error Resume Next
    If StrComp(CStr(p.ExecutablePath), appPath, vbTextCompare) = 0 Then running = True
    On Error GoTo 0
Next

If running Then
    sh.AppActivate "GitHub Copilot"
    MsgBox "GitHub Copilot 已在运行，中文补丁未生效。" & vbCrLf & vbCrLf & _
           "请先从系统托盘退出 GitHub Copilot，再从本快捷方式重新打开。", 48, "GitHub Copilot 中文补丁"
    WScript.Quit 0
End If

appDir = fso.GetParentFolderName(appPath)
sh.CurrentDirectory = appDir

' —— 清理上一次残留的端口文件 ——
portFile = fso.BuildPath(sh.ExpandEnvironmentStrings("%LOCALAPPDATA%"), "com.github.githubapp\EBWebView\DevToolsActivePort")
If fso.FileExists(portFile) Then
    On Error Resume Next
    fso.DeleteFile portFile, True
    On Error GoTo 0
End If

' —— 只对本次启动的进程设置调试端口（不影响其他 WebView2 应用）——
sh.Environment("PROCESS")("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS") = "--remote-debugging-port=0"

' —— 启动主程序 ——
sh.Run """" & appPath & """", 1, False

' —— 启动隐藏的注入器（注入器自带单实例保护）——
injectorPath = fso.BuildPath(scriptDir, "inject.ps1")
WScript.Sleep 500
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & injectorPath & """", 0, False

WScript.Quit 0

' ============================ 辅助函数 ============================
Function ReadUtf8(path)
    Dim stream
    Set stream = CreateObject("ADODB.Stream")
    stream.Type = 2
    stream.Charset = "utf-8"
    stream.Open
    stream.LoadFromFile path
    ReadUtf8 = stream.ReadText
    stream.Close
End Function

Function ExtractJsonString(text, key)
    Dim re, matches
    Set re = New RegExp
    re.Pattern = """" & key & """\s*:\s*""((?:[^""\\]|\\.)*)"""
    re.IgnoreCase = True
    re.Global = False
    ExtractJsonString = ""
    If re.Test(text) Then
        Set matches = re.Execute(text)
        ExtractJsonString = Replace(Replace(matches(0).SubMatches(0), "\\", "\"), "\/", "/")
    End If
End Function
