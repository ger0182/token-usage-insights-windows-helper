# Token Usage Insights - Windows Service setup
# 將 TokenUsageInsights 安裝成真正的 Windows Service（WinSW）。

[CmdletBinding()]
param(
    [int]$Port = 3003,
    [string]$WinSWVersion = "v2.12.0",
    [switch]$UseLocalSystem,
    [switch]$ReinstallService
)

$ErrorActionPreference = "Stop"

$ServiceName = "TokenUsageInsights"
$DisplayName = "Token Usage Insights"
$UserProfile = $env:USERPROFILE
$InstallDir = Join-Path $env:LOCALAPPDATA "TokenUsageInsights"
$BinDir = Join-Path $UserProfile "bin"
$ServiceDir = Join-Path $InstallDir "service"
$LogDir = Join-Path $ServiceDir "logs"
$WinSWExe = Join-Path $ServiceDir "TokenUsageInsightsService.exe"
$WinSWXml = Join-Path $ServiceDir "TokenUsageInsightsService.xml"
$ConfigPath = Join-Path $ServiceDir "helper-config.json"
$ControlPs1 = Join-Path $ServiceDir "token-usage-control.ps1"
$UpdaterPs1 = Join-Path $ServiceDir "token-usage-update.ps1"
$ControlCmd = Join-Path $BinDir "token-usage.cmd"
$AppExe = Join-Path $InstallDir "token-usage-insights.exe"
$DbPath = Join-Path $InstallDir "token_usage_insights.db"
$DashboardUrl = "http://127.0.0.1:$Port"
$CurrentAccount = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

function Test-Admin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Escape-Xml([string]$Value) {
    [System.Security.SecurityElement]::Escape($Value)
}

function SecureString-ToPlainText([Security.SecureString]$SecureString) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Write-WinSWConfig {
    param(
        [string]$Account,
        [string]$Password,
        [switch]$IncludeAccount,
        [switch]$LocalSystem
    )

    $accountXml = ""
    if ($IncludeAccount) {
        if ($LocalSystem) {
            $accountXml = @"
  <serviceaccount>
    <username>LocalSystem</username>
  </serviceaccount>
"@
        }
        else {
            $accountXml = @"
  <serviceaccount>
    <username>$(Escape-Xml $Account)</username>
    <password>$(Escape-Xml $Password)</password>
    <allowservicelogon>true</allowservicelogon>
  </serviceaccount>
"@
        }
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<service>
  <id>$ServiceName</id>
  <name>$DisplayName</name>
  <description>TokenUsageInsights local dashboard service.</description>
  <executable>$(Escape-Xml $AppExe)</executable>
  <workingdirectory>$(Escape-Xml $InstallDir)</workingdirectory>
  <startmode>Automatic</startmode>
  <delayedAutoStart>true</delayedAutoStart>
  <hidewindow>true</hidewindow>
  <stoptimeout>15 sec</stoptimeout>
  <onfailure action="restart" delay="10 sec" />
  <resetfailure>1 hour</resetfailure>

  <env name="HOST" value="127.0.0.1" />
  <env name="PORT" value="$Port" />
  <env name="INSIGHTS_DIR" value="$(Escape-Xml $InstallDir)" />
  <env name="ANTIGRAVITY_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.gemini\antigravity-cli'))" />
  <env name="COPILOT_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.copilot'))" />
  <env name="COPILOT_APP_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.copilot'))" />
  <env name="CODEX_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.codex'))" />
  <env name="CLAUDE_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.claude'))" />
  <env name="CURSOR_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.cursor'))" />
  <env name="GROK_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.grok'))" />
  <env name="PI_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.pi'))" />
  <env name="OMP_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.omp'))" />
  <env name="MUSE_DIR" value="$(Escape-Xml (Join-Path $UserProfile '.local\share\muse'))" />

  <logpath>$(Escape-Xml $LogDir)</logpath>
  <log mode="roll"></log>
$accountXml</service>
"@

    Set-Content -Path $WinSWXml -Value $xml -Encoding UTF8
}

if (-not (Test-Admin)) {
    Write-Host "此腳本需要系統管理員權限。" -ForegroundColor Yellow
    Write-Host "請以『系統管理員身分』開啟 PowerShell，再執行："
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -ForegroundColor Cyan
    exit 1
}

Write-Host "=== Token Usage Insights Windows Service ===" -ForegroundColor Cyan
Write-Host "帳號      : $CurrentAccount"
Write-Host "安裝位置  : $InstallDir"
Write-Host "Dashboard : $DashboardUrl"
Write-Host ""

New-Item -ItemType Directory -Force -Path $InstallDir, $BinDir, $ServiceDir, $LogDir | Out-Null

# 移除舊版 Task Scheduler 設定，避免同時啟動兩份。
$oldTask = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
if ($oldTask) {
    Write-Host "移除舊版工作排程器設定..."
    try { Stop-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue } catch {}
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path $InstallDir "token-usage-background.cmd") -Force -ErrorAction SilentlyContinue

# 停止既有 Service / 程序。
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -ne "Stopped") {
    Stop-Service -Name $ServiceName -Force
    $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
}
Get-Process "token-usage-insights" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

if ($service -and $ReinstallService) {
    Write-Host "重新安裝 Windows Service..."
    if (Test-Path $WinSWExe) { & $WinSWExe uninstall | Out-Host }
    else { & sc.exe delete $ServiceName | Out-Host }
    Start-Sleep -Seconds 1
    $service = $null
}

# 確認 Port 沒被其他程式占用。
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $owner = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    $ownerName = if ($owner) { $owner.ProcessName } else { "PID $($listener.OwningProcess)" }
    throw "Port $Port 已被 $ownerName 使用。請先關閉舊的 npx TokenUsageInsights 或其他占用程式。"
}

# 尚未安裝 TokenUsageInsights 時，使用官方 Windows installer。
if (!(Test-Path $AppExe)) {
    Write-Host "安裝官方 TokenUsageInsights Windows 版本..."
    $getScript = Join-Path $env:TEMP "token-usage-insights-get.ps1"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/doggy8088/TokenUsageInsights/main/scripts/get.ps1" -OutFile $getScript -UseBasicParsing
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $getScript -InstallDir $InstallDir -BinDir $BinDir -Port $Port
        if ($LASTEXITCODE -ne 0) { throw "官方安裝程式失敗，ExitCode=$LASTEXITCODE" }
    }
    finally {
        Remove-Item $getScript -Force -ErrorAction SilentlyContinue
    }
}
if (!(Test-Path $AppExe)) { throw "找不到 $AppExe" }

# 安裝 WinSW stable 版。
if (!(Test-Path $WinSWExe)) {
    $url = "https://github.com/winsw/winsw/releases/download/$WinSWVersion/WinSW-x64.exe"
    Write-Host "下載 WinSW $WinSWVersion..."
    Invoke-WebRequest -Uri $url -OutFile $WinSWExe -UseBasicParsing
}

# Helper 設定；不儲存 Windows 密碼。
$config = [ordered]@{
    ServiceName = $ServiceName
    Port = $Port
    DashboardUrl = $DashboardUrl
    InstallDir = $InstallDir
    BinDir = $BinDir
    ServiceDir = $ServiceDir
    LogDir = $LogDir
    DbPath = $DbPath
    UserProfile = $UserProfile
    ServiceAccount = if ($UseLocalSystem) { "LocalSystem" } else { $CurrentAccount }
    WinSWVersion = $WinSWVersion
}
$config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8

# token-usage 的 PowerShell 控制器。
$controlText = @'
param([string]$Command = "help")
$ErrorActionPreference = "Stop"

$ServiceDir = Split-Path -Parent $PSCommandPath
$config = Get-Content (Join-Path $ServiceDir "helper-config.json") -Raw | ConvertFrom-Json

function Test-Admin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Admin([string]$Code) {
    if (Test-Admin) {
        Invoke-Expression $Code
        return
    }
    $bytes = [Text.Encoding]::Unicode.GetBytes($Code)
    $encoded = [Convert]::ToBase64String($bytes)
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -EncodedCommand $encoded" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "系統管理員操作失敗，ExitCode=$($p.ExitCode)" }
}

function Show-Status {
    $s = Get-Service -Name $config.ServiceName -ErrorAction SilentlyContinue
    if (!$s) { Write-Host "NOT INSTALLED" -ForegroundColor Red; return }
    if ($s.Status -ne "Running") { Write-Host "STOPPED - Service: $($s.Status)" -ForegroundColor Yellow; return }
    try {
        $r = Invoke-WebRequest $config.DashboardUrl -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {
            Write-Host "RUNNING - $($config.DashboardUrl)" -ForegroundColor Green
            return
        }
    } catch {}
    Write-Host "SERVICE RUNNING - Dashboard 尚未回應" -ForegroundColor Yellow
}

switch ($Command.ToLowerInvariant()) {
    "status"  { Show-Status }
    "open"    { Start-Process $config.DashboardUrl }
    "start"   { Invoke-Admin "Start-Service -Name '$($config.ServiceName)'"; Start-Sleep -Seconds 1; Show-Status }
    "stop"    { Invoke-Admin "Stop-Service -Name '$($config.ServiceName)' -Force"; Write-Host "Token Usage Insights 已停止。" -ForegroundColor Green }
    "restart" { Invoke-Admin "Restart-Service -Name '$($config.ServiceName)' -Force"; Start-Sleep -Seconds 1; Show-Status }
    "update"  {
        $updater = Join-Path $ServiceDir "token-usage-update.ps1"
        $code = "& '" + $updater.Replace("'", "''") + "'"
        Invoke-Admin $code
    }
    "version" {
        $vf = Join-Path $config.InstallDir "VERSION"
        if (Test-Path $vf) { Write-Host "Installed version: $((Get-Content $vf -TotalCount 1).Trim())" }
        else { Write-Host "Installed version: unknown" }
    }
    "service" {
        Get-CimInstance Win32_Service -Filter "Name='$($config.ServiceName)'" |
            Select-Object Name, State, StartMode, StartName, PathName | Format-List
    }
    "logs" { Start-Process explorer.exe $config.LogDir }
    default {
        Write-Host "Usage:"
        Write-Host "  token-usage status    檢查 Service 與 Dashboard"
        Write-Host "  token-usage open      開啟 Dashboard"
        Write-Host "  token-usage start     啟動 Service（會要求 UAC）"
        Write-Host "  token-usage stop      停止 Service（會要求 UAC）"
        Write-Host "  token-usage restart   重新啟動 Service（會要求 UAC）"
        Write-Host "  token-usage update    更新 TokenUsageInsights（會要求 UAC）"
        Write-Host "  token-usage version   顯示版本"
        Write-Host "  token-usage service   顯示 Service 詳細資料"
        Write-Host "  token-usage logs      開啟 Service log 目錄"
    }
}
'@
Set-Content -Path $ControlPs1 -Value $controlText -Encoding UTF8

# TokenUsageInsights 本體更新器；Service 設定不會被官方 installer 覆蓋。
$updaterText = @'
$ErrorActionPreference = "Stop"
$ServiceDir = Split-Path -Parent $PSCommandPath
$config = Get-Content (Join-Path $ServiceDir "helper-config.json") -Raw | ConvertFrom-Json

$service = Get-Service -Name $config.ServiceName -ErrorAction Stop
if ($service.Status -ne "Stopped") {
    Write-Host "停止 Windows Service..."
    Stop-Service -Name $config.ServiceName -Force
    $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
}

$backupDir = Join-Path $config.InstallDir "backups"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
if (Test-Path $config.DbPath) {
    $backup = Join-Path $backupDir ("token_usage_insights-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".db")
    Copy-Item -Force $config.DbPath $backup
    Write-Host "資料庫備份：$backup"
}

$vf = Join-Path $config.InstallDir "VERSION"
$before = if (Test-Path $vf) { (Get-Content $vf -TotalCount 1).Trim() } else { "unknown" }
$getScript = Join-Path $env:TEMP "token-usage-insights-get.ps1"

try {
    Write-Host "更新官方 TokenUsageInsights..."
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/doggy8088/TokenUsageInsights/main/scripts/get.ps1" -OutFile $getScript -UseBasicParsing
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $getScript -InstallDir $config.InstallDir -BinDir $config.BinDir -Port ([int]$config.Port)
    if ($LASTEXITCODE -ne 0) { throw "官方安裝程式失敗，ExitCode=$LASTEXITCODE" }
}
catch {
    Write-Host "更新失敗：$($_.Exception.Message)" -ForegroundColor Red
    try { Start-Service -Name $config.ServiceName } catch {}
    throw
}
finally {
    Remove-Item $getScript -Force -ErrorAction SilentlyContinue
}

Start-Service -Name $config.ServiceName
$after = if (Test-Path $vf) { (Get-Content $vf -TotalCount 1).Trim() } else { "unknown" }
if ($before -eq $after) { Write-Host "已是最新版本：$after" -ForegroundColor Green }
else { Write-Host "更新完成：$before -> $after" -ForegroundColor Green }
Write-Host "Service 已重新啟動：$($config.DashboardUrl)" -ForegroundColor Green
'@
Set-Content -Path $UpdaterPs1 -Value $updaterText -Encoding UTF8

# CMD shim。
$cmdText = @"
@echo off
setlocal
set "CMD=%~1"
if "%CMD%"=="" set "CMD=help"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ControlPs1" -Command "%CMD%"
exit /b %ERRORLEVEL%
"@
Set-Content -Path $ControlCmd -Value $cmdText -Encoding ASCII

# 將 ~/bin 加入使用者 PATH。
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathItems = if ($userPath) { @($userPath.Split(';') | Where-Object { $_ }) } else { @() }
if ($pathItems -notcontains $BinDir) {
    $newPath = if ($userPath) { "$userPath;$BinDir" } else { $BinDir }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
}

# 第一次建立 Service 時設定登入帳號。
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (!$service) {
    if ($UseLocalSystem) {
        Write-Host "使用 LocalSystem 安裝 Service。" -ForegroundColor Yellow
        Write-WinSWConfig -IncludeAccount -LocalSystem
        & $WinSWExe install | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "WinSW 安裝失敗，ExitCode=$LASTEXITCODE" }
        Write-WinSWConfig
    }
    else {
        Write-Host "Service 將以目前帳號執行：$CurrentAccount" -ForegroundColor Cyan
        Write-Host "請輸入 Windows 帳號『密碼』，不是 Windows Hello PIN。"
        $securePassword = Read-Host "Windows 密碼" -AsSecureString
        $plainPassword = SecureString-ToPlainText $securePassword
        try {
            Write-WinSWConfig -Account $CurrentAccount -Password $plainPassword -IncludeAccount
            & $WinSWExe install | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "WinSW 安裝失敗，ExitCode=$LASTEXITCODE" }
        }
        finally {
            $plainPassword = $null
            # SCM 已保存 Service credential 後，立刻移除 XML 裡的明碼密碼。
            Write-WinSWConfig
        }
    }
}
else {
    # 已存在時保留 SCM 裡的 Service account，只更新 runtime config。
    Write-WinSWConfig
}

Start-Service -Name $ServiceName
Start-Sleep -Seconds 2
$serviceInfo = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"

Write-Host ""
Write-Host "=== 設定完成 ===" -ForegroundColor Green
Write-Host "Windows Service : $ServiceName"
Write-Host "執行帳號        : $($serviceInfo.StartName)"
Write-Host "Dashboard       : $DashboardUrl"
Write-Host "Service logs    : $LogDir"
Write-Host ""
Write-Host "請重新開一個 CMD / PowerShell，然後執行："
Write-Host "  token-usage status"
Write-Host "  token-usage open"
Write-Host "  token-usage update"
