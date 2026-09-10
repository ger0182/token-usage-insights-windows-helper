# Token Usage Insights - Windows Service setup
# Requires an elevated (Administrator) PowerShell.
# Installs TokenUsageInsights if needed and wraps it as a real Windows Service with WinSW.

[CmdletBinding()]
param(
    [int]$Port = 3003,
    [string]$WinSWVersion = "v2.12.0",
    [switch]$UseLocalSystem,
    [switch]$ReinstallService
)

$ErrorActionPreference = "Stop"

$ServiceName = "TokenUsageInsights"
$ServiceDisplayName = "Token Usage Insights"
$UserProfile = $env:USERPROFILE
$LocalAppData = $env:LOCALAPPDATA
$AppData = $env:APPDATA
$InstallDir = Join-Path $LocalAppData "TokenUsageInsights"
$BinDir = Join-Path $UserProfile "bin"
$ServiceDir = Join-Path $InstallDir "service"
$LogDir = Join-Path $ServiceDir "logs"
$WinSWExe = Join-Path $ServiceDir "TokenUsageInsightsService.exe"
$WinSWXml = Join-Path $ServiceDir "TokenUsageInsightsService.xml"
$ConfigPath = Join-Path $ServiceDir "helper-config.json"
$ControllerPs1 = Join-Path $ServiceDir "token-usage-control.ps1"
$UpdaterPs1 = Join-Path $ServiceDir "token-usage-update.ps1"
$ControllerCmd = Join-Path $BinDir "token-usage.cmd"
$AppExe = Join-Path $InstallDir "token-usage-insights.exe"
$DbPath = Join-Path $InstallDir "token_usage_insights.db"
$DashboardUrl = "http://127.0.0.1:$Port"
$CurrentAccount = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$CurrentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Escape-Xml([string]$Value) {
    return [System.Security.SecurityElement]::Escape($Value)
}

function Get-PlainTextPassword([Security.SecureString]$SecurePassword) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Write-ServiceXml {
    param(
        [string]$AccountName,
        [string]$Password,
        [switch]$IncludeServiceAccount,
        [switch]$LocalSystem
    )

    $accountBlock = ""
    if ($IncludeServiceAccount) {
        if ($LocalSystem) {
            $accountBlock = @"
  <serviceaccount>
    <username>LocalSystem</username>
  </serviceaccount>
"@
        }
        else {
            $escapedAccount = Escape-Xml $AccountName
            $escapedPassword = Escape-Xml $Password
            $accountBlock = @"
  <serviceaccount>
    <username>$escapedAccount</username>
    <password>$escapedPassword</password>
    <allowservicelogon>true</allowservicelogon>
  </serviceaccount>
"@
        }
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<service>
  <id>$ServiceName</id>
  <name>$ServiceDisplayName</name>
  <description>TokenUsageInsights local dashboard service.</description>
  <executable>$(Escape-Xml $AppExe)</executable>
  <workingdirectory>$(Escape-Xml $InstallDir)</workingdirectory>
  <startmode>Automatic</startmode>
  <delayedAutoStart>true</delayedAutoStart>
  <hidewindow>true</hidewindow>
  <stoptimeout>15 sec</stoptimeout>
  <onfailure action="restart" delay="10 sec"/>
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
$accountBlock</service>
"@

    Set-Content -Path $WinSWXml -Value $xml -Encoding UTF8
}

if (-not (Test-IsAdministrator)) {
    Write-Host "" 
    Write-Host "此安裝程式需要系統管理員權限。" -ForegroundColor Yellow
    Write-Host "請以『系統管理員身分』開啟 PowerShell，再執行："
    Write-Host ""
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -ForegroundColor Cyan
    exit 1
}

Write-Host "=== Token Usage Insights Windows Service 設定 ===" -ForegroundColor Cyan
Write-Host "Windows 帳號 : $CurrentAccount"
Write-Host "安裝目錄     : $InstallDir"
Write-Host "Dashboard    : $DashboardUrl"
Write-Host ""

New-Item -ItemType Directory -Force -Path $InstallDir, $BinDir, $ServiceDir, $LogDir | Out-Null

# Migrate away from the old Scheduled Task helper if present.
$oldTask = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
if ($oldTask) {
    Write-Host "移除舊版工作排程器設定..."
    try { Stop-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue } catch {}
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path $InstallDir "token-usage-background.cmd") -Force -ErrorAction SilentlyContinue

# Stop an existing service/process before changing files.
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService -and $ReinstallService) {
    Write-Host "重新安裝 Windows Service..."
    if ($existingService.Status -ne "Stopped") {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        $existingService.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
    }
    if (Test-Path $WinSWExe) {
        & $WinSWExe uninstall | Out-Host
    }
    else {
        & sc.exe delete $ServiceName | Out-Host
    }
    Start-Sleep -Seconds 1
    $existingService = $null
}
elseif ($existingService -and $existingService.Status -ne "Stopped") {
    Write-Host "停止目前 Windows Service..."
    Stop-Service -Name $ServiceName -Force
    $existingService.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
}

Get-Process "token-usage-insights" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

# Refuse to install if another application already owns port 3003.
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $owner = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    $ownerName = if ($owner) { $owner.ProcessName } else { "PID $($listener.OwningProcess)" }
    throw "Port $Port 已被 $ownerName 使用。請先關閉舊的 npx TokenUsageInsights 或其他占用程式。"
}

# Install the official native Windows build if necessary.
if (!(Test-Path $AppExe)) {
    Write-Host "尚未找到 TokenUsageInsights，正在安裝官方 Windows 版本..."
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

if (!(Test-Path $AppExe)) {
    throw "找不到 TokenUsageInsights 執行檔：$AppExe"
}

# Download pinned WinSW stable release.
if (!(Test-Path $WinSWExe)) {
    $winSwUrl = "https://github.com/winsw/winsw/releases/download/$WinSWVersion/WinSW-x64.exe"
    Write-Host "下載 WinSW $WinSWVersion..."
    Invoke-WebRequest -Uri $winSwUrl -OutFile $WinSWExe -UseBasicParsing
}

# Save helper metadata. No password is stored here.
$config = [ordered]@{
    ServiceName = $ServiceName
    ServiceDisplayName = $ServiceDisplayName
    Port = $Port
    DashboardUrl = $DashboardUrl
    InstallDir = $InstallDir
    BinDir = $BinDir
    ServiceDir = $ServiceDir
    LogDir = $LogDir
    AppExe = $AppExe
    DbPath = $DbPath
    UserProfile = $UserProfile
    LocalAppData = $LocalAppData
    AppData = $AppData
    ServiceAccount = if ($UseLocalSystem) { "LocalSystem" } else { $CurrentAccount }
    UserSid = $CurrentSid
    WinSWVersion = $WinSWVersion
}
$config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8

# PowerShell control helper used by token-usage.cmd.
$controllerText = @'
param(
    [string]$Command = "help"
)

$ErrorActionPreference = "Stop"
$ServiceDir = Split-Path -Parent $PSCommandPath
$ConfigPath = Join-Path $ServiceDir "helper-config.json"
if (!(Test-Path $ConfigPath)) { throw "找不到 helper-config.json，請重新執行 setup-token-usage-service.ps1。" }
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedSelf([string]$Name) {
    $quotedScript = '"' + $PSCommandPath.Replace('"','\"') + '"'
    $args = "-NoProfile -ExecutionPolicy Bypass -File $quotedScript -Command $Name"
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $args -Wait -PassThru
    exit $p.ExitCode
}

function Show-Status {
    $service = Get-Service -Name $config.ServiceName -ErrorAction SilentlyContinue
    if (!$service) {
        Write-Host "NOT INSTALLED" -ForegroundColor Red
        exit 1
    }
    if ($service.Status -ne "Running") {
        Write-Host "STOPPED - Windows Service: $($service.Status)" -ForegroundColor Yellow
        exit 1
    }
    try {
        $r = Invoke-WebRequest $config.DashboardUrl -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {
            Write-Host "RUNNING - $($config.DashboardUrl)" -ForegroundColor Green
            exit 0
        }
    } catch {}
    Write-Host "SERVICE RUNNING - Dashboard 尚未回應" -ForegroundColor Yellow
    exit 2
}

switch ($Command.ToLowerInvariant()) {
    "start" {
        if (!(Test-IsAdministrator)) { Invoke-ElevatedSelf "start" }
        Start-Service -Name $config.ServiceName
        Start-Sleep -Seconds 1
        Show-Status
    }
    "stop" {
        if (!(Test-IsAdministrator)) { Invoke-ElevatedSelf "stop" }
        $s = Get-Service -Name $config.ServiceName -ErrorAction Stop
        if ($s.Status -eq "Stopped") { Write-Host "Token Usage Insights 已停止。"; exit 0 }
        Stop-Service -Name $config.ServiceName -Force
        $s.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
        Write-Host "Token Usage Insights 已停止。" -ForegroundColor Green
    }
    "restart" {
        if (!(Test-IsAdministrator)) { Invoke-ElevatedSelf "restart" }
        Restart-Service -Name $config.ServiceName -Force
        Start-Sleep -Seconds 1
        Show-Status
    }
    "status" { Show-Status }
    "open" { Start-Process $config.DashboardUrl }
    "version" {
        $versionFile = Join-Path $config.InstallDir "VERSION"
        if (Test-Path $versionFile) { Write-Host "Installed version: $((Get-Content $versionFile -TotalCount 1).Trim())" }
        else { Write-Host "Installed version: unknown" }
    }
    "update" {
        $updater = Join-Path $ServiceDir "token-usage-update.ps1"
        if (!(Test-Path $updater)) { throw "找不到更新程式：$updater" }
        if (Test-IsAdministrator) { & $updater; exit $LASTEXITCODE }
        $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $updater + '"'
        $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $args -Wait -PassThru
        exit $p.ExitCode
    }
    "logs" { Start-Process explorer.exe $config.LogDir }
    "service" {
        Get-CimInstance Win32_Service -Filter "Name='$($config.ServiceName)'" |
            Select-Object Name, State, StartMode, StartName, PathName |
            Format-List
    }
    default {
        Write-Host "Usage:"
        Write-Host "  token-usage status    檢查 Windows Service 與 Dashboard"
        Write-Host "  token-usage open      開啟 Dashboard"
        Write-Host "  token-usage start     啟動 Service（可能跳 UAC）"
        Write-Host "  token-usage stop      停止 Service（可能跳 UAC）"
        Write-Host "  token-usage restart   重新啟動 Service（可能跳 UAC）"
        Write-Host "  token-usage update    更新 TokenUsageInsights（會跳 UAC）"
        Write-Host "  token-usage version   顯示 TokenUsageInsights 版本"
        Write-Host "  token-usage service   顯示 Windows Service 詳細資料"
        Write-Host "  token-usage logs      開啟 Service log 目錄"
    }
}
'@
Set-Content -Path $ControllerPs1 -Value $controllerText -Encoding UTF8

# Updater preserves the service and its account configuration.
$updaterText = @'
$ErrorActionPreference = "Stop"
$ServiceDir = Split-Path -Parent $PSCommandPath
$ConfigPath = Join-Path $ServiceDir "helper-config.json"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (!(Test-IsAdministrator)) {
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $args -Wait -PassThru
    exit $p.ExitCode
}

$versionFile = Join-Path $config.InstallDir "VERSION"
$before = if (Test-Path $versionFile) { (Get-Content $versionFile -TotalCount 1).Trim() } else { "unknown" }
Write-Host "目前版本：$before"

$service = Get-Service -Name $config.ServiceName -ErrorAction Stop
if ($service.Status -ne "Stopped") {
    Write-Host "停止 Windows Service..."
    Stop-Service -Name $config.ServiceName -Force
    $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
}

$backupDir = Join-Path $config.InstallDir "backups"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
if (Test-Path $config.DbPath) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path $backupDir "token_usage_insights-$stamp.db"
    Copy-Item -Force $config.DbPath $backup
    Write-Host "資料庫備份：$backup"
}

$getScript = Join-Path $env:TEMP "token-usage-insights-get.ps1"
try {
    Write-Host "下載並安裝官方最新 TokenUsageInsights..."
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/doggy8088/TokenUsageInsights/main/scripts/get.ps1" -OutFile $getScript -UseBasicParsing
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $getScript -InstallDir $config.InstallDir -BinDir $config.BinDir -Port ([int]$config.Port)
    if ($LASTEXITCODE -ne 0) { throw "官方安裝程式失敗，ExitCode=$LASTEXITCODE" }
}
catch {
    Write-Host "更新失敗：$($_.Exception.Message)" -ForegroundColor Red
    try { Start-Service -Name $config.ServiceName -ErrorAction SilentlyContinue } catch {}
    exit 1
}
finally {
    Remove-Item $getScript -Force -ErrorAction SilentlyContinue
}

Start-Service -Name $config.ServiceName
$deadline = (Get-Date).AddSeconds(20)
$ready = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    try {
        $r = Invoke-WebRequest $config.DashboardUrl -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { $ready = $true; break }
    } catch {}
}

$after = if (Test-Path $versionFile) { (Get-Content $versionFile -TotalCount 1).Trim() } else { "unknown" }
if ($before -eq $after) { Write-Host "已是最新版本：$after" -ForegroundColor Green }
else { Write-Host "更新完成：$before -> $after" -ForegroundColor Green }

if ($ready) {
    Write-Host "RUNNING - $($config.DashboardUrl)" -ForegroundColor Green
    exit 0
}

Write-Host "Service 已啟動，但 Dashboard 尚未回應，請執行 token-usage status 或 token-usage logs。" -ForegroundColor Yellow
exit 2
'@
Set-Content -Path $UpdaterPs1 -Value $updaterText -Encoding UTF8

# Thin CMD shim placed in the user's bin directory.
$cmdText = @"
@echo off
setlocal
set "CMD=%~1"
if "%CMD%"=="" set "CMD=help"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ControllerPs1" -Command "%CMD%"
exit /b %ERRORLEVEL%
"@
Set-Content -Path $ControllerCmd -Value $cmdText -Encoding ASCII

# Ensure ~/bin is available from new shells.
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$parts = @()
if ($userPath) { $parts = $userPath.Split(';') | Where-Object { $_ } }
if ($parts -notcontains $BinDir) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $BinDir } else { "$userPath;$BinDir" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "已將 $BinDir 加入使用者 PATH。"
}

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (!$existingService) {
    if ($UseLocalSystem) {
        Write-Host "使用 LocalSystem 安裝 Service（不需要帳號密碼）。" -ForegroundColor Yellow
        Write-ServiceXml -IncludeServiceAccount -LocalSystem
        & $WinSWExe install | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "WinSW Service 安裝失敗，ExitCode=$LASTEXITCODE" }
        # Runtime config does not need service account credentials.
        Write-ServiceXml
    }
    else {
        Write-Host ""
        Write-Host "Service 將以目前 Windows 帳號執行：$CurrentAccount" -ForegroundColor Cyan
        Write-Host "請輸入 Windows『帳號密碼』，不是 Windows Hello PIN。"
        $secure = Read-Host "Windows 密碼" -AsSecureString
        $plain = Get-PlainTextPassword $secure
        try {
            Write-ServiceXml -AccountName $CurrentAccount -Password $plain -IncludeServiceAccount
            & $WinSWExe install | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "WinSW Service 安裝失敗，ExitCode=$LASTEXITCODE" }
        }
        finally {
            $plain = $null
            # Remove plaintext credentials from the XML immediately after SCM stores them.
            Write-ServiceXml
        }
    }
}
else {
    # Keep the existing SCM service account and only refresh runtime settings.
    Write-ServiceXml
}

Write-Host "啟動 Windows Service..."
Start-Service -Name $ServiceName

$deadline = (Get-Date).AddSeconds(20)
$ready = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    try {
        $response = Invoke-WebRequest $DashboardUrl -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
            $ready = $true
            break
        }
    } catch {}
}

Write-Host ""
Write-Host "=== 設定完成 ===" -ForegroundColor Green
Write-Host "Windows Service : $ServiceName"
Write-Host "執行帳號        : $((Get-CimInstance Win32_Service -Filter \"Name='$ServiceName'\").StartName)"
Write-Host "Dashboard       : $DashboardUrl"
Write-Host "安裝目錄        : $InstallDir"
Write-Host "Service 目錄    : $ServiceDir"
Write-Host "Log 目錄        : $LogDir"
Write-Host ""
Write-Host "請開一個新的 CMD / PowerShell，之後可使用："
Write-Host "  token-usage status"
Write-Host "  token-usage open"
Write-Host "  token-usage update"
Write-Host "  token-usage service"
Write-Host "  token-usage logs"
Write-Host ""
if ($ready) {
    Write-Host "RUNNING - $DashboardUrl" -ForegroundColor Green
}
else {
    Write-Host "Service 已建立，但 Dashboard 尚未回應。請執行 token-usage logs 查看紀錄。" -ForegroundColor Yellow
    exit 2
}
