# GitHub Copilot 中文补丁（Windows）

给 **GitHub Copilot 桌面应用**（`github.exe`，Tauri + WebView2 架构）加上简体中文界面的非官方补丁。

> 本项目与 GitHub 官方无关，只是个人制作的界面本地化工具。不修改应用本体、不修改账号数据、不联网。

![demo](https://img.shields.io/badge/status-working-brightgreen) ![platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue) ![version](https://img.shields.io/badge/Copilot-1.1.34-lightgrey)

## 特点

- ✅ 不改动 `GitHub Copilot` 安装目录里的任何文件，应用可正常更新；
- ✅ 不读取、不上传账号或对话数据，全程离线；
- ✅ 代码块、聊天正文、文件名等**用户内容不会被翻译**；
- ✅ 一键安装 / 一键卸载，快捷方式自动备份还原；
- ✅ 词典可自行扩充，改完热更新，无需重启应用。

## 效果

主界面、侧边栏、对话输入区、设置页（常规 / 账户 / 会话 / 主题 / 无障碍 / 语音听写 / 计算机操作 / 模型服务商 / 实验性 / 环境）、自动化、自定义、搜索等均已中文化，共 **900+ 条**词典条目。

## 原理

应用本身没有多语言资源（程序里不存在 `zh-CN`），所以采用「运行时界面中文化」：

1. `launch.vbs` 只对**本次启动的进程**设置 WebView2 调试端口（`--remote-debugging-port=0`，随机端口、仅监听 `127.0.0.1`）；
2. 隐藏运行的 `inject.ps1` 读取 `DevToolsActivePort`，通过本机 WebSocket 把 `patch.js` 注入页面；
3. `patch.js` 精确匹配词典替换界面文字，并用 `MutationObserver` 持续处理 React 后续渲染；
4. 程序退出后端口关闭、注入器自动结束。

## 安装

要求：Windows 10/11，已安装 GitHub Copilot 桌面版。

1. 先**退出**正在运行的 GitHub Copilot（托盘图标 → 退出）；
2. 在仓库目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\runtime\install.ps1
```

脚本会：

- 把运行文件安装到 `%LOCALAPPDATA%\GitHubCopilotZh`；
- 备份并改写桌面、开始菜单的 GitHub Copilot 快捷方式（原快捷方式备份在 `backup\`）；
- 由 `src/engine.js` + `src/dict.json` + `src/patterns.json` 生成 `patch.js`。

3. 双击桌面图标启动，界面即为中文。

如果自动定位不到程序：

```powershell
.\runtime\install.ps1 -AppPath "D:\GitHub Copilot\github.exe"
```

## 使用

- 从桌面/开始菜单的 **GitHub Copilot** 图标启动（图标、名称不变）；
- 程序若已在运行，请先托盘退出再打开——补丁只在启动时注入；
- 应用自动更新后若界面变回英文，重新运行一次 `install.ps1`。

## 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\GitHubCopilotZh\uninstall.ps1"
```

或直接运行 `%LOCALAPPDATA%\GitHubCopilotZh\uninstall.cmd`。

## 自定义词典

安装目录中：

| 文件 | 说明 |
| --- | --- |
| `dict.json` | 词典，`"英文原文": "中文"`，键必须与界面完整文本完全一致 |
| `patterns.json` | 动态文案规则 `[正则, 标志, 替换文本]`（数量、相对时间等） |
| `engine.template.js` | 翻译引擎模板 |
| `rebuild.cmd` | 修改词典后重新生成 `patch.js` |

改完双击 `rebuild.cmd`，运行中的应用约 2 秒自动热更新。

引擎会跳过 `pre` / `code` / 输入框 / 编辑器 / Markdown 聊天区域，只有精确命中词典的文本才会被替换。

## 目录结构

```
src/engine.js       翻译引擎（含 __ZH_DICT__ 等占位符）
src/dict.json       词典
src/patterns.json   动态文案规则
runtime/install.ps1 安装（定位程序、生成 patch.js、改写快捷方式）
runtime/inject.ps1  注入器（隐藏运行，负责注入与热更新）
runtime/launch.vbs  启动器（带调试端口启动应用）
runtime/rebuild.ps1 重新生成 patch.js
runtime/uninstall.ps1 卸载
```

## 已知限制

- 原生部分无法覆盖：**系统托盘菜单、Windows 原生通知、标题栏原生菜单**；
- 未访问过的页面/对话框里可能还有英文，可按上文补充词典；
- 极少数由多段文本拼接的句子，译文语序可能略生硬；
- 适配版本：**GitHub Copilot 1.1.34（2026-10）**，其他版本可能部分失效，通常重跑安装即可。

## 安全说明

- 调试端口不写入系统环境变量，不影响 Edge、VS Code 等其他 WebView2 程序；
- 端口随机、仅绑定 `127.0.0.1`、随进程退出关闭；
- 全部为明文脚本（`.vbs` / `.ps1` / `.js`）,可自行审阅；
- 个别安全软件可能对“隐藏运行的 PowerShell”敏感，属正常现象。

## License

[MIT](LICENSE)
