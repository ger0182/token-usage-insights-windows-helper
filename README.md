# Token Usage Insights Windows Helper

這是一個給 [TokenUsageInsights](https://github.com/doggy8088/TokenUsageInsights) 使用的 Windows 輔助工具，讓 TokenUsageInsights 可以在背景執行，不需要一直保留 CMD 或 PowerShell 視窗。

> 此 Repository 為**非官方輔助工具**。TokenUsageInsights 本體由原始專案維護。

## 功能

這個設定腳本會：

- 如果尚未安裝，自動安裝官方 Windows 原生版 TokenUsageInsights。
- 透過 Windows 工作排程器在背景執行 TokenUsageInsights。
- 登入 Windows 後自動啟動。
- 建立方便使用的 `token-usage` 管理指令。
- 將 Dashboard 綁定到 `127.0.0.1:3003`，只允許本機存取。
- 提供更新指令，升級前會先備份 SQLite 資料庫。

## 系統需求

- Windows 10 / 11
- PowerShell
- 安裝與更新時需要網路連線

執行設定腳本前，如果目前有 CMD 正在執行：

```cmd
npx -y token-usage-insights
```

請先將它關閉，否則 `3003` Port 可能已被占用。

## 初次安裝

先 Clone 此 Repository：

```cmd
git clone https://github.com/ger0182/token-usage-insights-windows-helper.git
cd token-usage-insights-windows-helper
```

接著執行設定腳本：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-background.ps1"
```

設定完成後，請重新開啟一個 **新的 CMD 或 PowerShell 視窗**，讓更新後的使用者 `PATH` 生效。

確認服務狀態：

```cmd
token-usage status
```

開啟 Dashboard：

```cmd
token-usage open
```

Dashboard 網址：

```text
http://127.0.0.1:3003
```

## 常用指令

| 指令 | 功能 |
| --- | --- |
| `token-usage start` | 在背景啟動 TokenUsageInsights |
| `token-usage stop` | 停止 TokenUsageInsights |
| `token-usage restart` | 重新啟動 TokenUsageInsights |
| `token-usage status` | 檢查程式與 Dashboard 是否正常執行 |
| `token-usage open` | 使用預設瀏覽器開啟 Dashboard |
| `token-usage update` | 更新到官方最新版本 |
| `token-usage version` | 顯示目前安裝版本 |

直接執行：

```cmd
token-usage
```

也會顯示可使用的指令列表。

## Windows 自動啟動機制

設定腳本會建立一個 Windows 工作排程器工作：

```text
TokenUsageInsights
```

觸發條件為：

```text
目前使用者登入 Windows 時
```

因此之後 Windows 重新開機，只要登入使用者帳號，TokenUsageInsights 就會自動在背景啟動，不需要保留 CMD 視窗。

## 安裝位置

TokenUsageInsights 主要安裝目錄：

```text
%LOCALAPPDATA%\TokenUsageInsights
```

通常實際位置會是：

```text
C:\Users\<使用者名稱>\AppData\Local\TokenUsageInsights
```

重要檔案包括：

```text
%LOCALAPPDATA%\TokenUsageInsights\token-usage-insights.exe
%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db
%LOCALAPPDATA%\TokenUsageInsights\token-usage-background.cmd
%LOCALAPPDATA%\TokenUsageInsights\token-usage-update.ps1
```

本 Repository 建立的管理指令位於：

```text
%USERPROFILE%\bin\token-usage.cmd
```

官方安裝程式也會在 `%USERPROFILE%\bin` 建立自己的：

```text
token-usage-insights.cmd
```

## 更新 TokenUsageInsights

之後官方有新版時，只需要執行：

```cmd
token-usage update
```

更新流程如下：

```text
停止目前執行中的 TokenUsageInsights
        ↓
備份 SQLite 資料庫
        ↓
下載官方最新 Release
        ↓
執行官方 Windows 安裝程式
        ↓
保留原本 Token 使用紀錄
        ↓
重新啟動工作排程器
        ↓
檢查 http://127.0.0.1:3003
```

每次更新前，資料庫會另外備份成：

```text
%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db.pre-update.bak
```

官方 `get.ps1` 本身支援重複執行，因此可用來升級新版。

查看目前安裝版本：

```cmd
token-usage version
```

## Token 使用紀錄與資料庫

Token 使用歷史紀錄儲存在：

```text
%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db
```

如果想保留歷史使用紀錄，**不要刪除這個檔案**。

也可以手動再備份一份到桌面：

```cmd
copy "%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db" "%USERPROFILE%\Desktop\token_usage_insights.db.bak"
```

## 更新這個 Helper Repository

如果此 Repository 未來有修改，可以先更新：

```cmd
git pull
```

然後重新執行設定腳本：

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-background.ps1"
```

重新執行設定腳本是安全的，它會更新：

- `token-usage` 管理指令
- 更新腳本
- 背景啟動腳本
- Windows 工作排程器設定

如果 TokenUsageInsights 已經存在，不會因為重跑 Helper 設定就不必要地重新安裝本體。

> `token-usage update` 是更新 **TokenUsageInsights 本體**；`git pull` + 重新執行設定腳本則是更新 **這個 Windows Helper**。兩者用途不同。

## 疑難排解

### `token-usage` 顯示不是內部或外部命令

執行設定腳本後，重新開啟一個新的 CMD 或 PowerShell 視窗。

腳本會將以下目錄加入使用者 `PATH`：

```text
%USERPROFILE%\bin
```

可以使用以下指令確認：

```cmd
where token-usage
```

正常應該能找到：

```text
C:\Users\<使用者名稱>\bin\token-usage.cmd
```

### Port 3003 已被占用

使用 PowerShell 檢查是哪個程序正在監聽：

```powershell
Get-NetTCPConnection -LocalPort 3003 -State Listen
```

如果舊的：

```cmd
npx -y token-usage-insights
```

還在執行，請先關閉原本的 CMD 視窗，再重新執行設定腳本。

### 程序有執行，但網頁尚未正常開啟

先檢查：

```cmd
token-usage status
```

再嘗試：

```cmd
token-usage restart
```

### 檢查 Windows 工作排程器

PowerShell：

```powershell
Get-ScheduledTask -TaskName "TokenUsageInsights"
```

也可以直接開啟 Windows **工作排程器**，尋找：

```text
TokenUsageInsights
```

## 完整移除

先停止 TokenUsageInsights：

```cmd
token-usage stop
```

移除 Windows 工作排程器：

```powershell
Unregister-ScheduledTask -TaskName "TokenUsageInsights" -Confirm:$false
```

移除 Helper 建立的檔案：

```powershell
Remove-Item "$HOME\bin\token-usage.cmd" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\TokenUsageInsights\token-usage-background.cmd" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\TokenUsageInsights\token-usage-update.ps1" -Force -ErrorAction SilentlyContinue
```

如果連 TokenUsageInsights 本體也要完整刪除，而且**不需要保留 Token 使用歷史紀錄**，可以再執行：

```powershell
Remove-Item "$env:LOCALAPPDATA\TokenUsageInsights" -Recurse -Force
```

> **注意：**上面的最後一個指令也會刪除 `token_usage_insights.db`，因此 Token 使用歷史紀錄也會一起消失。

如果想保留紀錄，請先備份：

```text
%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db
```

## 原始專案

TokenUsageInsights 官方專案：

https://github.com/doggy8088/TokenUsageInsights

此 Helper 更新 TokenUsageInsights 時使用的官方 Windows Bootstrap Installer：

```powershell
irm https://raw.githubusercontent.com/doggy8088/TokenUsageInsights/main/scripts/get.ps1 | iex
```

## Repository 內容

```text
setup-token-usage-background.ps1   Windows 背景執行與管理設定腳本
README.md                           安裝、更新與使用說明
```

## 快速備忘

第一次安裝：

```cmd
git clone https://github.com/ger0182/token-usage-insights-windows-helper.git
cd token-usage-insights-windows-helper
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-background.ps1"
```

平常最常用：

```cmd
token-usage status
token-usage open
token-usage update
```
