# Token Usage Insights Windows Helper

這是一個給 [TokenUsageInsights](https://github.com/doggy8088/TokenUsageInsights) 使用的 **Windows Service 輔助工具**。

目的是讓 TokenUsageInsights 真正以 Windows Service 常駐執行：

- 不需要一直開著 CMD / PowerShell
- Windows 開機後自動啟動
- 不需要等使用者登入後才啟動
- 可以用 `token-usage` 指令管理服務
- 更新 TokenUsageInsights 時保留原本 SQLite 使用紀錄

> 此 Repository 為**非官方輔助工具**。TokenUsageInsights 本體由原始專案維護。

---

## 架構

目前版本已經從舊的「Windows 工作排程器」改為真正的 Windows Service：

```text
Windows 開機
   ↓
Windows Service Manager
   ↓
WinSW
   ↓
token-usage-insights.exe
   ↓
http://127.0.0.1:3003
```

Service 名稱：

```text
TokenUsageInsights
```

Service 設定為：

```text
Automatic + Delayed Auto Start
```

因此電腦重新開機後，即使沒有保持 CMD / PowerShell 視窗，TokenUsageInsights 仍會在背景執行。

---

## 系統需求

- Windows 10 / 11 x64
- PowerShell
- 系統管理員權限（安裝 / 移除 Windows Service 時需要）
- 安裝與更新時需要網路連線

Service Wrapper 使用：

```text
WinSW v2.12.0
```

目前固定使用 WinSW 2.x stable 版本，避免未來 WinSW major version 行為改變造成 Helper 失效。

---

# 第一次安裝

## 1. Clone Repository

建議不要從 GitHub 頁面直接另存 `.ps1`，避免把 HTML 頁面誤存成 PowerShell 腳本。

請直接 Clone：

```cmd
git clone https://github.com/ger0182/token-usage-insights-windows-helper.git
cd token-usage-insights-windows-helper
```

如果已經 Clone 過：

```cmd
git pull
```

---

## 2. 關閉舊的 TokenUsageInsights

如果目前有 CMD 正在執行：

```cmd
npx -y token-usage-insights
```

請先關閉。

如果先前使用過這個 Repository 的「工作排程器版」，不用手動移除；新版 Service 安裝程式會自動清掉舊的：

```text
TokenUsageInsights 工作排程器
```

避免同時啟動兩份 TokenUsageInsights。

---

## 3. 用系統管理員 PowerShell 安裝

開啟：

```text
PowerShell → 以系統管理員身分執行
```

切到 Repository 目錄後執行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1"
```

腳本會自動：

1. 檢查 / 安裝官方 Windows 版 TokenUsageInsights
2. 下載 WinSW
3. 移除舊版工作排程器設定
4. 建立 Windows Service
5. 設定 `127.0.0.1:3003`
6. 設定 Codex / Claude / Copilot / Cursor 等資料來源路徑
7. 建立 `token-usage` 管理指令
8. 啟動 Service

---

# Windows Service 帳號密碼

第一次建立 Service 時，預設會顯示：

```text
Service 將以目前帳號執行：電腦名稱\使用者名稱
請輸入 Windows 帳號『密碼』，不是 Windows Hello PIN。
```

請輸入你的 **Windows 帳號密碼**。

不能輸入：

```text
Windows Hello PIN
```

如果使用 Microsoft Account 登入 Windows，通常要輸入 Microsoft Account 的帳號密碼。

這個密碼只在第一次向 Windows Service Manager 註冊 Service 時使用。安裝完成後，Helper 會立刻把 WinSW XML 裡的明碼密碼移除，不會寫進 Git Repository。

Windows 會自行保存 Service 登入所需的 credential。

### Windows 密碼之後改過

如果未來修改 Windows 密碼，Service 可能因舊 credential 無法登入。

重新執行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1" -ReinstallService
```

再輸入新的 Windows 密碼即可。

---

# 不想輸入 Windows 密碼：LocalSystem 模式

也可以使用：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1" -UseLocalSystem
```

如果已經裝過 Service，要切換帳號模式：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1" -ReinstallService -UseLocalSystem
```

這樣不需要 Windows 密碼。

不過 **LocalSystem 權限很高**，一般情況仍建議使用自己的 Windows 帳號執行 Service。

Helper 即使在 LocalSystem 模式下，也會明確指定原本使用者的資料路徑，例如：

```text
%USERPROFILE%\.codex
%USERPROFILE%\.claude
%USERPROFILE%\.copilot
%USERPROFILE%\.cursor
```

避免 TokenUsageInsights 跑到 SystemProfile 去找資料。

---

# 安裝完成後

重新開一個新的 CMD / PowerShell，讓 `PATH` 更新生效。

檢查：

```cmd
token-usage status
```

正常會看到：

```text
RUNNING - http://127.0.0.1:3003
```

接著即使把 PowerShell / CMD 全部關掉，Service 還是會繼續執行。

可以直接重新開一個 PowerShell 再確認：

```powershell
token-usage status
```

仍應該顯示：

```text
RUNNING - http://127.0.0.1:3003
```

---

# 常用指令

| 指令 | 功能 |
| --- | --- |
| `token-usage status` | 檢查 Windows Service 與 Dashboard |
| `token-usage open` | 開啟 TokenUsageInsights Dashboard |
| `token-usage start` | 啟動 Windows Service |
| `token-usage stop` | 停止 Windows Service |
| `token-usage restart` | 重新啟動 Windows Service |
| `token-usage update` | 更新官方 TokenUsageInsights |
| `token-usage version` | 查看 TokenUsageInsights 版本 |
| `token-usage service` | 顯示 Windows Service 詳細資料 |
| `token-usage logs` | 開啟 WinSW Service log 目錄 |

直接執行：

```cmd
token-usage
```

會顯示指令列表。

### UAC

以下操作會修改 Windows Service，因此可能跳出 UAC：

```cmd
token-usage start
token-usage stop
token-usage restart
token-usage update
```

一般查看狀態不需要系統管理員權限：

```cmd
token-usage status
token-usage open
token-usage version
token-usage service
token-usage logs
```

---

# Dashboard

網址：

```text
http://127.0.0.1:3003
```

Helper 刻意將：

```text
HOST=127.0.0.1
```

而不是 TokenUsageInsights 預設的：

```text
0.0.0.0
```

因此預設只有這台電腦可以連線，不會直接開放給區網其他裝置。

---

# Service 如何找到 Codex / Claude 資料

Helper 會把 TokenUsageInsights 官方支援的環境變數寫進 WinSW Service 設定：

```text
INSIGHTS_DIR
ANTIGRAVITY_DIR
COPILOT_DIR
COPILOT_APP_DIR
CODEX_DIR
CLAUDE_DIR
CURSOR_DIR
GROK_DIR
PI_DIR
OMP_DIR
MUSE_DIR
```

例如：

```text
CODEX_DIR  = C:\Users\<使用者>\.codex
CLAUDE_DIR = C:\Users\<使用者>\.claude
```

因此即使是在 Windows Service 環境執行，仍會讀取原本帳號底下的 Coding Agent Session。

---

# 安裝位置

TokenUsageInsights 本體：

```text
%LOCALAPPDATA%\TokenUsageInsights
```

通常是：

```text
C:\Users\<使用者>\AppData\Local\TokenUsageInsights
```

主要檔案：

```text
%LOCALAPPDATA%\TokenUsageInsights\token-usage-insights.exe
%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db
```

Windows Service 相關檔案：

```text
%LOCALAPPDATA%\TokenUsageInsights\service\
```

其中包含：

```text
TokenUsageInsightsService.exe   WinSW
TokenUsageInsightsService.xml   Service 設定
token-usage-control.ps1         管理指令
token-usage-update.ps1          更新程式
helper-config.json               Helper 設定
logs\                            Service logs
```

管理指令：

```text
%USERPROFILE%\bin\token-usage.cmd
```

---

# 更新 TokenUsageInsights 本體

官方 TokenUsageInsights 有新版時：

```cmd
token-usage update
```

流程：

```text
停止 Windows Service
        ↓
備份 SQLite
        ↓
執行官方 get.ps1
        ↓
更新 TokenUsageInsights
        ↓
保留 Windows Service 設定
        ↓
重新啟動 Service
```

更新前會把資料庫備份到：

```text
%LOCALAPPDATA%\TokenUsageInsights\backups\
```

例如：

```text
token_usage_insights-20260910-143000.db
```

因此：

```cmd
token-usage update
```

**不會重新安裝 WinSW Service，也不需要重新輸入 Windows 密碼。**

---

# 更新 Windows Helper

這個 Repository 自己有更新時：

```cmd
git pull
```

然後用系統管理員 PowerShell 重新執行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1"
```

如果 Service 已經存在，腳本會保留目前 Windows Service 登入帳號，只更新 Helper / WinSW runtime 設定。

兩種更新不要混淆：

```text
token-usage update
= 更新 TokenUsageInsights 本體

git pull + setup-token-usage-service.ps1
= 更新這個 Windows Helper
```

---

# 從舊版工作排程器升級

如果曾經使用舊版：

```text
setup-token-usage-background.ps1
```

新版仍保留這個檔案作為相容入口。

執行它會轉交到：

```text
setup-token-usage-service.ps1
```

但建議之後直接使用新的檔名。

Service installer 會自動移除舊的 Windows Task Scheduler：

```text
TokenUsageInsights
```

以及舊的：

```text
token-usage-background.cmd
```

---

# 疑難排解

## 1. 檢查 Service

```cmd
token-usage service
```

會看到類似：

```text
Name      : TokenUsageInsights
State     : Running
StartMode : Auto
StartName : 電腦名稱\使用者名稱
```

也可以使用：

```powershell
Get-Service TokenUsageInsights
```

---

## 2. Service 是 Running，但網頁打不開

先執行：

```cmd
token-usage status
```

然後查看 log：

```cmd
token-usage logs
```

WinSW logs 位於：

```text
%LOCALAPPDATA%\TokenUsageInsights\service\logs
```

---

## 3. Port 3003 被占用

```powershell
Get-NetTCPConnection -LocalPort 3003 -State Listen
```

如果之前仍有：

```cmd
npx -y token-usage-insights
```

請把舊 CMD 關掉。

---

## 4. Service 登入失敗

如果最近修改過 Windows 密碼：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1" -ReinstallService
```

再輸入最新 Windows 密碼。

Windows Hello PIN 不能代替 Service Account 密碼。

---

## 5. `token-usage` 找不到

重新開一個 CMD / PowerShell。

確認：

```cmd
where token-usage
```

正常會找到：

```text
%USERPROFILE%\bin\token-usage.cmd
```

---

# 移除 Windows Service

用系統管理員 PowerShell 執行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\uninstall-token-usage-service.ps1"
```

預設只會移除：

- Windows Service
- WinSW
- Helper scripts
- `token-usage` 指令
- 舊版 Task Scheduler 設定（如果還存在）

**不會刪除 TokenUsageInsights 本體與 SQLite 使用紀錄。**

資料仍保留在：

```text
%LOCALAPPDATA%\TokenUsageInsights
```

如果確定連 TokenUsageInsights 與所有歷史資料都不要：

```powershell
powershell -ExecutionPolicy Bypass -File ".\uninstall-token-usage-service.ps1" -RemoveAll
```

> `-RemoveAll` 會刪除 `token_usage_insights.db`，歷史 Token 使用紀錄也會一起消失。

---

# Repository 內容

```text
setup-token-usage-service.ps1       主要 Windows Service 安裝 / 更新設定
uninstall-token-usage-service.ps1   移除 Windows Service
setup-token-usage-background.ps1    舊版相容入口，會轉到 Service installer
README.md                            本說明文件
```

---

# 快速備忘

第一次安裝：

```cmd
git clone https://github.com/ger0182/token-usage-insights-windows-helper.git
cd token-usage-insights-windows-helper
```

接著用 **系統管理員 PowerShell**：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1"
```

平常最常用：

```cmd
token-usage status
token-usage open
token-usage update
```

確認是否真正常駐：

```text
關閉所有 CMD / PowerShell
→ 重新開 PowerShell
→ token-usage status
→ 仍顯示 RUNNING
```

---

## 原始專案

TokenUsageInsights：

https://github.com/doggy8088/TokenUsageInsights

WinSW：

https://github.com/winsw/winsw
