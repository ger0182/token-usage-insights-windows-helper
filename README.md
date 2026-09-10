# Token Usage Insights Windows Helper

這是一個給 [TokenUsageInsights](https://github.com/doggy8088/TokenUsageInsights) 使用的 **Windows Service 輔助工具**。

主要目的是讓 TokenUsageInsights 真正以 Windows Service 常駐執行，不需要一直開著 CMD 或 PowerShell，也不需要使用 `npx` 前景執行。

> 此 Repository 為非官方輔助工具。TokenUsageInsights 本體由原始專案維護。

## 目前架構

```text
Windows 開機
   ↓
Windows Service Control Manager
   ↓
WinSW
   ↓
token-usage-insights.exe
   ↓
http://127.0.0.1:3003
```

Service 預設使用：

```text
LocalSystem
```

因此：

- 不需要輸入 Windows 帳號密碼
- 不依賴目前 CMD / PowerShell 視窗
- 不需要使用者登入後才啟動
- Windows 開機後可自動啟動
- 程式異常退出時由 Windows Service / WinSW 自動重新啟動

## 為什麼 LocalSystem 還能讀到我的 Codex / Claude 資料？

LocalSystem 本身的使用者目錄不是你的 Windows 使用者目錄。

因此安裝程式會在安裝當下記住目前使用者的路徑，例如：

```text
C:\Users\<你的使用者名稱>
```

並把 TokenUsageInsights 官方支援的資料來源環境變數明確指定到該使用者目錄，例如：

```text
CODEX_DIR
CLAUDE_DIR
COPILOT_DIR
COPILOT_APP_DIR
CURSOR_DIR
CURSOR_STATE_DB
VSCODE_USER_DATA_DIR
GROK_DIR
PI_DIR
OMP_DIR
MUSE_DIR
ANTIGRAVITY_DIR
INSIGHTS_DIR
```

因此即使 Service 身分是 LocalSystem，TokenUsageInsights 仍會掃描原本使用者的 Codex、Claude、Copilot 等資料。

> 建議從你平常使用 Codex / Claude 的那個 Windows 帳號，開啟「系統管理員 PowerShell」執行安裝。安裝程式會以當下的 `USERPROFILE`、`LOCALAPPDATA`、`APPDATA` 作為資料來源路徑。

---

## 系統需求

- Windows 10 / 11
- Windows PowerShell 5.1 或 PowerShell 7
- 系統管理員權限
- 安裝與更新時需要網路
- Git（若使用 clone / pull）

## 初次安裝

建議直接 Clone 完整 Repository，不要從 GitHub 網頁另存單一 `.ps1` 檔案。

```cmd
git clone https://github.com/ger0182/token-usage-insights-windows-helper.git
cd token-usage-insights-windows-helper
```

接著使用 **系統管理員 PowerShell**：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1"
```

安裝程式會：

1. 移除舊版 `TokenUsageInsights` 工作排程器
2. 停止舊的 TokenUsageInsights 程序
3. 若尚未安裝，下載官方 Windows 版 TokenUsageInsights
4. 下載 WinSW
5. 建立真正的 Windows Service
6. 將 Service 設為 LocalSystem
7. 明確設定原本 Windows 使用者的 Codex / Claude 等資料路徑
8. 建立 `token-usage` 管理指令
9. 啟動 Service
10. 檢查 Dashboard

正常完成後會看到類似：

```text
RUNNING - http://127.0.0.1:3003
```

## 從舊版工作排程器升級

如果你之前已經安裝過本 Repository 的舊版：

```cmd
cd token-usage-insights-windows-helper
git pull
```

然後開啟 **系統管理員 PowerShell**：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1"
```

新的安裝腳本會自動移除舊的 Task Scheduler 設定並改成 Windows Service。

舊的相容入口仍然保留：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-background.ps1"
```

它會轉交給新的 Service 安裝程式。

---

## 常用指令

安裝完成後，請重新開一個新的 CMD 或 PowerShell。

```cmd
token-usage status
token-usage open
token-usage start
token-usage stop
token-usage restart
token-usage update
token-usage version
token-usage service
token-usage logs
```

功能：

| 指令 | 功能 |
| --- | --- |
| `token-usage status` | 檢查 Windows Service 與 Dashboard |
| `token-usage open` | 開啟 Dashboard |
| `token-usage start` | 啟動 Windows Service |
| `token-usage stop` | 停止 Windows Service |
| `token-usage restart` | 重新啟動 Windows Service |
| `token-usage update` | 更新官方 TokenUsageInsights |
| `token-usage version` | 顯示目前版本 |
| `token-usage service` | 顯示 Service 詳細資訊 |
| `token-usage logs` | 開啟 WinSW Log 目錄 |

`start`、`stop`、`restart`、`update` 需要系統管理員權限，因此一般 PowerShell 執行時可能跳出 UAC。

## 確認是否真的脫離 PowerShell

執行：

```powershell
token-usage status
```

正常：

```text
RUNNING - http://127.0.0.1:3003
```

然後把 PowerShell 完全關閉。

重新開一個新的 PowerShell：

```powershell
token-usage status
```

如果仍然顯示：

```text
RUNNING - http://127.0.0.1:3003
```

代表 Windows Service 已正常常駐。

---

## Dashboard

```text
http://127.0.0.1:3003
```

Helper 預設把 `HOST` 固定為：

```text
127.0.0.1
```

因此 Dashboard 只允許本機存取，不會直接暴露給區網其他裝置。

---

## Windows Service

Service 名稱：

```text
TokenUsageInsights
```

可使用 Windows 內建工具確認：

```powershell
Get-Service TokenUsageInsights
```

查看詳細資料：

```powershell
Get-CimInstance Win32_Service -Filter "Name='TokenUsageInsights'" |
    Select-Object Name,State,StartMode,StartName,PathName
```

正常的 `StartName` 應該是：

```text
LocalSystem
```

也可以使用：

```cmd
token-usage service
```

---

## 安裝位置

TokenUsageInsights：

```text
%LOCALAPPDATA%\TokenUsageInsights
```

通常是：

```text
C:\Users\<使用者名稱>\AppData\Local\TokenUsageInsights
```

Windows Service 相關檔案：

```text
%LOCALAPPDATA%\TokenUsageInsights\service
```

包含：

```text
TokenUsageInsightsService.exe
TokenUsageInsightsService.xml
helper-config.json
token-usage-control.ps1
token-usage-update.ps1
logs\
```

管理指令：

```text
%USERPROFILE%\bin\token-usage.cmd
```

資料庫：

```text
%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db
```

---

## 更新 TokenUsageInsights 本體

之後官方 TokenUsageInsights 有新版時：

```cmd
token-usage update
```

流程：

```text
停止 Windows Service
   ↓
備份 SQLite
   ↓
下載官方最新版
   ↓
執行官方 Windows installer
   ↓
保留原本資料庫
   ↓
重新啟動 Windows Service
   ↓
檢查 Dashboard
```

備份會放在：

```text
%LOCALAPPDATA%\TokenUsageInsights\backups
```

例如：

```text
token_usage_insights-20260910-163000.db
```

這個更新只更新 **TokenUsageInsights 本體**，不需要重新建立 Service，也不需要 Windows 帳號密碼。

---

## 更新這個 Helper Repository

Helper 本身有修改時：

```cmd
git pull
```

如果只有 README 修改，不必重跑安裝。

如果：

```text
setup-token-usage-service.ps1
setup-token-usage-background.ps1
uninstall-token-usage-service.ps1
```

有更新，建議重新使用系統管理員 PowerShell 執行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1"
```

腳本可以重複執行；它會重新整理 Service 設定。

> `token-usage update` = 更新 TokenUsageInsights 本體  
> `git pull` + 重跑 setup = 更新 Windows Helper

---

## PowerShell 5.1 編碼相容性

Windows PowerShell 5.1 對「UTF-8 無 BOM」腳本的處理與 PowerShell 7 不同。

如果 `.ps1` 直接包含中文字串，可能出現亂碼及 ParserError，例如 `UnexpectedToken`、`MissingExpressionAfterOperator`。

因此本 Repository 的所有 `.ps1` 執行腳本都刻意維持 **ASCII-only**。

繁體中文說明只放在 README。

Repository 也有 GitHub Actions 同時使用：

```text
Windows PowerShell 5.1
PowerShell 7
```

做 Parser 語法檢查。

---

## 如果 GitHub 下載到 HTML 而不是 PowerShell

不要在 GitHub 檔案頁直接「網頁另存新檔」。

最推薦：

```cmd
git clone https://github.com/ger0182/token-usage-insights-windows-helper.git
```

如果一定要單獨下載 Raw：

```cmd
curl.exe -L "https://raw.githubusercontent.com/ger0182/token-usage-insights-windows-helper/main/setup-token-usage-service.ps1" -o setup-token-usage-service.ps1
```

可以先檢查：

```powershell
Get-Content ".\setup-token-usage-service.ps1" -TotalCount 5
```

正常不應看到 `githubassets.com`、`<script>`、`--fontStack-monospace` 等 HTML/CSS 內容。

---

## 疑難排解

### `token-usage` 找不到

重新開一個 CMD / PowerShell，再執行：

```cmd
where token-usage
```

應該找到：

```text
%USERPROFILE%\bin\token-usage.cmd
```

### Service 沒有啟動

```powershell
Get-Service TokenUsageInsights
```

或：

```cmd
token-usage service
```

### 查看 Log

```cmd
token-usage logs
```

Log 目錄：

```text
%LOCALAPPDATA%\TokenUsageInsights\service\logs
```

### Port 3003 被占用

```powershell
Get-NetTCPConnection -LocalPort 3003 -State Listen
```

如果還有舊的：

```cmd
npx -y token-usage-insights
```

請先關閉。

### Service Running，但 Dashboard 打不開

```cmd
token-usage status
token-usage logs
```

也可以查看程序：

```powershell
Get-Process token-usage-insights -ErrorAction SilentlyContinue
```

---

## 移除 Windows Service

使用 **系統管理員 PowerShell**：

```powershell
powershell -ExecutionPolicy Bypass -File ".\uninstall-token-usage-service.ps1"
```

預設只移除：

- Windows Service
- WinSW Service helper
- `token-usage` 管理指令

會保留 TokenUsageInsights 本體與 SQLite 使用紀錄。

如果要連 TokenUsageInsights 與所有 Token 歷史紀錄一起刪掉：

```powershell
powershell -ExecutionPolicy Bypass -File ".\uninstall-token-usage-service.ps1" -RemoveAll
```

> `-RemoveAll` 會刪除 `token_usage_insights.db`，歷史紀錄無法由 Helper 復原。

---

## 原始專案

TokenUsageInsights：

https://github.com/doggy8088/TokenUsageInsights

WinSW：

https://github.com/winsw/winsw

本 Helper 預設使用 WinSW：

```text
v2.12.0
```

---

## Repository 內容

```text
setup-token-usage-service.ps1       Windows Service 安裝與設定
setup-token-usage-background.ps1    舊版相容入口
uninstall-token-usage-service.ps1   移除 Windows Service
README.md                           繁體中文使用說明
.github/workflows/
  powershell-check.yml              PowerShell 5.1 / 7 語法檢查
```

---

## 快速備忘

第一次安裝：

```cmd
git clone https://github.com/ger0182/token-usage-insights-windows-helper.git
cd token-usage-insights-windows-helper
```

系統管理員 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-service.ps1"
```

平常最常用：

```cmd
token-usage status
token-usage open
token-usage update
```

確認 Windows Service 帳號：

```cmd
token-usage service
```

正常應看到：

```text
StartName : LocalSystem
```
