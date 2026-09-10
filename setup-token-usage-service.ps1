# Token Usage Insights - Windows Service setup
# ASCII-only source for compatibility with Windows PowerShell 5.1.
# Installs TokenUsageInsights as a real Windows Service by using WinSW.
# The Windows Service runs as LocalSystem by default and therefore needs no user password.
# User data folders are passed explicitly to TokenUsageInsights through environment variables.

[CmdletBinding()]
param(
    [int]$Port = 3003,
    [string]$WinSWVersion = "v2.12.0"
)

$ErrorActionPreference = "Stop"

$ServiceName = "TokenUsageInsights"
$DisplayName = "Token Usage Insights"

# Capture the profile of the user who runs this installer.
# Run the installer from an elevated PowerShell opened by the same Windows user
# whose Codex / Claude / Copilot data should be monitored.
$SourceUserProfile = $env:USERPROFILE
$SourceLocalAppData = $env:LOCALAPPDATA
$SourceAppData = $env:APPDATA

$InstallDir = Join-Path $SourceLocalAppData "TokenUsageInsights"
$BinDir = Join-Path $SourceUserProfile "bin"
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

function Test-Admin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Escape-Xml([string]$Value) {
    return [System.Security.SecurityElement]::Escape($Value)
}

function Wait-ServiceDeleted {
    param([string]$Name, [int]$TimeoutSeconds = 15)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Service -Name $Name -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 300
    }
    throw "Timed out waiting for Windows Service '$Name' to be deleted."
}

function Stop-ExistingService {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Stopped") {
        Write-Host "Stopping existing Windows Service..."
        Stop-Service -Name $ServiceName -Force
        $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
    }
}

function Remove-ExistingService {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        return
    }

    Stop-ExistingService

    Write-Host "Removing previous Windows Service registration..."
    if (Test-Path $WinSWExe) {
        & $WinSWExe uninstall | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WinSW uninstall returned ExitCode=$LASTEXITCODE. Falling back to sc.exe delete."
            & sc.exe delete $ServiceName | Out-Host
        }
    }
    else {
        & sc.exe delete $ServiceName | Out-Host
    }

    Wait-ServiceDeleted -Name $ServiceName
}

function Write-WinSWConfig {
    $vscodeDir = Join-Path $SourceAppData "Code"
    $cursorStateDb = Join-Path $SourceAppData "Cursor\User\globalStorage\state.vscdb"

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

  <serviceaccount>
    <username>LocalSystem</username>
  </serviceaccount>

  <env name="HOST" value="127.0.0.1" />
  <env name="PORT" value="$Port" />

  <env name="HOME" value="$(Escape-Xml $SourceUserProfile)" />
  <env name="USERPROFILE" value="$(Escape-Xml $SourceUserProfile)" />
  <env name="LOCALAPPDATA" value="$(Escape-Xml $SourceLocalAppData)" />
  <env name="APPDATA" value="$(Escape-Xml $SourceAppData)" />

  <env name="INSIGHTS_DIR" value="$(Escape-Xml $InstallDir)" />
  <env name="ANTIGRAVITY_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.gemini\antigravity-cli'))" />
  <env name="COPILOT_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.copilot'))" />
  <env name="COPILOT_APP_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.copilot'))" />
  <env name="CODEX_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.codex'))" />
  <env name="CLAUDE_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.claude'))" />
  <env name="CURSOR_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.cursor'))" />
  <env name="CURSOR_STATE_DB" value="$(Escape-Xml $cursorStateDb)" />
  <env name="VSCODE_USER_DATA_DIR" value="$(Escape-Xml $vscodeDir)" />
  <env name="GROK_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.grok'))" />
  <env name="PI_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.pi'))" />
  <env name="OMP_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.omp'))" />
  <env name="MUSE_DIR" value="$(Escape-Xml (Join-Path $SourceUserProfile '.local\share\muse'))" />

  <logpath>$(Escape-Xml $LogDir)</logpath>
  <log mode="roll"></log>
</service>
"@

    Set-Content -Path $WinSWXml -Value $xml -Encoding UTF8
}

if (-not (Test-Admin)) {
    Write-Host ""
    Write-Host "Administrator privileges are required." -ForegroundColor Yellow
    Write-Host "Open PowerShell as Administrator and run:"
    Write-Host ""
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -ForegroundColor Cyan
    exit 1
}

if (-not $SourceUserProfile -or -not $SourceLocalAppData -or -not $SourceAppData) {
    throw "USERPROFILE, LOCALAPPDATA, or APPDATA is missing."
}

Write-Host "=== Token Usage Insights Windows Service Setup ===" -ForegroundColor Cyan
Write-Host "Source profile : $SourceUserProfile"
Write-Host "Install dir    : $InstallDir"
Write-Host "Dashboard      : $DashboardUrl"
Write-Host "Service account: LocalSystem (no Windows password required)"
Write-Host ""

New-Item -ItemType Directory -Force -Path $InstallDir, $BinDir, $ServiceDir, $LogDir | Out-Null

$oldTask = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
if ($oldTask) {
    Write-Host "Removing old Task Scheduler entry..."
    try {
        Stop-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    }
    catch {}
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path $InstallDir "token-usage-background.cmd") -Force -ErrorAction SilentlyContinue

Stop-ExistingService
Get-Process "token-usage-insights" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($listener) {
    $owner = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    $ownerName = if ($owner) { $owner.ProcessName } else { "PID $($listener.OwningProcess)" }
    throw "Port $Port is already used by $ownerName. Stop the old npx instance or other application first."
}

if (-not (Test-Path $AppExe)) {
    Write-Host "Installing the official TokenUsageInsights Windows build..."
    $getScript = Join-Path $env:TEMP "token-usage-insights-get.ps1"
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/doggy8088/TokenUsageInsights/main/scripts/get.ps1" `
        -OutFile $getScript `
        -UseBasicParsing

    try {
        & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $getScript `
            -InstallDir $InstallDir `
            -BinDir $BinDir `
            -Port $Port

        if ($LASTEXITCODE -ne 0) {
            throw "Official installer failed. ExitCode=$LASTEXITCODE"
        }
    }
    finally {
        Remove-Item $getScript -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $AppExe)) {
    throw "TokenUsageInsights executable was not found: $AppExe"
}

if (-not (Test-Path $WinSWExe)) {
    $winSwUrl = "https://github.com/winsw/winsw/releases/download/$WinSWVersion/WinSW-x64.exe"
    Write-Host "Downloading WinSW $WinSWVersion..."
    Invoke-WebRequest -Uri $winSwUrl -OutFile $WinSWExe -UseBasicParsing
}

if (-not (Test-Path $WinSWExe)) {
    throw "WinSW executable was not found: $WinSWExe"
}

$config = [ordered]@{
    ServiceName = $ServiceName
    Port = $Port
    DashboardUrl = $DashboardUrl
    InstallDir = $InstallDir
    BinDir = $BinDir
    ServiceDir = $ServiceDir
    LogDir = $LogDir
    DbPath = $DbPath
    SourceUserProfile = $SourceUserProfile
    SourceLocalAppData = $SourceLocalAppData
    SourceAppData = $SourceAppData
    ServiceAccount = "LocalSystem"
    WinSWVersion = $WinSWVersion
}
$config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8

$controlText = @'
param([string]$Command = "help")

$ErrorActionPreference = "Stop"
$ServiceDir = Split-Path -Parent $PSCommandPath
$ConfigPath = Join-Path $ServiceDir "helper-config.json"

if (-not (Test-Path $ConfigPath)) {
    throw "helper-config.json was not found. Re-run setup-token-usage-service.ps1."
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

function Test-Admin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-AdminCode([string]$Code) {
    if (Test-Admin) {
        Invoke-Expression $Code
        return
    }

    $bytes = [Text.Encoding]::Unicode.GetBytes($Code)
    $encoded = [Convert]::ToBase64String($bytes)
    $process = Start-Process `
        powershell.exe `
        -Verb RunAs `
        -ArgumentList @("-NoProfile", "-EncodedCommand", $encoded) `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Administrator operation failed. ExitCode=$($process.ExitCode)"
    }
}

function Show-Status {
    $service = Get-Service -Name $config.ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "NOT INSTALLED" -ForegroundColor Red
        return 1
    }

    if ($service.Status -ne "Running") {
        Write-Host "STOPPED - Windows Service: $($service.Status)" -ForegroundColor Yellow
        return 1
    }

    try {
        $response = Invoke-WebRequest $config.DashboardUrl -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
            Write-Host "RUNNING - $($config.DashboardUrl)" -ForegroundColor Green
            return 0
        }
    }
    catch {}

    Write-Host "SERVICE RUNNING - Dashboard is not ready yet." -ForegroundColor Yellow
    return 2
}

switch ($Command.ToLowerInvariant()) {
    "status" {
        exit (Show-Status)
    }

    "open" {
        Start-Process $config.DashboardUrl
        exit 0
    }

    "start" {
        Invoke-AdminCode "Start-Service -Name '$($config.ServiceName)'"
        Start-Sleep -Seconds 1
        exit (Show-Status)
    }

    "stop" {
        Invoke-AdminCode "Stop-Service -Name '$($config.ServiceName)' -Force"
        Write-Host "Token Usage Insights stopped." -ForegroundColor Green
        exit 0
    }

    "restart" {
        Invoke-AdminCode "Restart-Service -Name '$($config.ServiceName)' -Force"
        Start-Sleep -Seconds 1
        exit (Show-Status)
    }

    "update" {
        $updater = Join-Path $ServiceDir "token-usage-update.ps1"
        if (-not (Test-Path $updater)) {
            throw "Updater was not found: $updater"
        }
        $escaped = $updater.Replace("'", "''")
        Invoke-AdminCode "& '$escaped'"
        exit 0
    }

    "version" {
        $versionFile = Join-Path $config.InstallDir "VERSION"
        if (Test-Path $versionFile) {
            Write-Host "Installed version: $((Get-Content $versionFile -TotalCount 1).Trim())"
        }
        else {
            Write-Host "Installed version: unknown"
        }
        exit 0
    }

    "service" {
        Get-CimInstance Win32_Service -Filter "Name='$($config.ServiceName)'" |
            Select-Object Name, State, StartMode, StartName, PathName |
            Format-List
        exit 0
    }

    "logs" {
        Start-Process explorer.exe $config.LogDir
        exit 0
    }

    default {
        Write-Host "Usage:"
        Write-Host "  token-usage status    Check Windows Service and Dashboard"
        Write-Host "  token-usage open      Open Dashboard"
        Write-Host "  token-usage start     Start Windows Service (UAC may appear)"
        Write-Host "  token-usage stop      Stop Windows Service (UAC may appear)"
        Write-Host "  token-usage restart   Restart Windows Service (UAC may appear)"
        Write-Host "  token-usage update    Update TokenUsageInsights (UAC may appear)"
        Write-Host "  token-usage version   Show installed TokenUsageInsights version"
        Write-Host "  token-usage service   Show Windows Service details"
        Write-Host "  token-usage logs      Open the WinSW log directory"
        exit 0
    }
}
'@
Set-Content -Path $ControlPs1 -Value $controlText -Encoding ASCII

$updaterText = @'
$ErrorActionPreference = "Stop"

$ServiceDir = Split-Path -Parent $PSCommandPath
$ConfigPath = Join-Path $ServiceDir "helper-config.json"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

function Test-Admin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    $quoted = '"' + $PSCommandPath + '"'
    $args = "-NoProfile -ExecutionPolicy Bypass -File $quoted"
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $args -Wait -PassThru
    exit $process.ExitCode
}

$service = Get-Service -Name $config.ServiceName -ErrorAction Stop
if ($service.Status -ne "Stopped") {
    Write-Host "Stopping Windows Service..."
    Stop-Service -Name $config.ServiceName -Force
    $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
}

$backupDir = Join-Path $config.InstallDir "backups"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

if (Test-Path $config.DbPath) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupDir "token_usage_insights-$stamp.db"
    Copy-Item -Force $config.DbPath $backupPath
    Write-Host "Database backup: $backupPath"
}

$versionFile = Join-Path $config.InstallDir "VERSION"
$before = if (Test-Path $versionFile) {
    (Get-Content $versionFile -TotalCount 1).Trim()
}
else {
    "unknown"
}

$getScript = Join-Path $env:TEMP "token-usage-insights-get.ps1"

try {
    Write-Host "Downloading and installing the latest official TokenUsageInsights..."
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/doggy8088/TokenUsageInsights/main/scripts/get.ps1" `
        -OutFile $getScript `
        -UseBasicParsing

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $getScript `
        -InstallDir $config.InstallDir `
        -BinDir $config.BinDir `
        -Port ([int]$config.Port)

    if ($LASTEXITCODE -ne 0) {
        throw "Official installer failed. ExitCode=$LASTEXITCODE"
    }
}
catch {
    Write-Host "Update failed: $($_.Exception.Message)" -ForegroundColor Red
    try {
        Start-Service -Name $config.ServiceName -ErrorAction SilentlyContinue
    }
    catch {}
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
        $response = Invoke-WebRequest $config.DashboardUrl -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
            $ready = $true
            break
        }
    }
    catch {}
}

$after = if (Test-Path $versionFile) {
    (Get-Content $versionFile -TotalCount 1).Trim()
}
else {
    "unknown"
}

if ($before -eq $after) {
    Write-Host "Already up to date: $after" -ForegroundColor Green
}
else {
    Write-Host "Updated: $before -> $after" -ForegroundColor Green
}

if ($ready) {
    Write-Host "RUNNING - $($config.DashboardUrl)" -ForegroundColor Green
    exit 0
}

Write-Host "Service is running, but the Dashboard is not ready yet." -ForegroundColor Yellow
Write-Host "Run: token-usage status"
Write-Host "Logs: token-usage logs"
exit 2
'@
Set-Content -Path $UpdaterPs1 -Value $updaterText -Encoding ASCII

$cmdText = @'
@echo off
setlocal
set "CONTROL=%LOCALAPPDATA%\TokenUsageInsights\service\token-usage-control.ps1"
if not exist "%CONTROL%" (
  echo Token Usage Insights helper is not installed correctly.
  echo Re-run setup-token-usage-service.ps1 as Administrator.
  exit /b 1
)
set "CMD=%~1"
if "%CMD%"=="" set "CMD=help"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CONTROL%" -Command "%CMD%"
exit /b %ERRORLEVEL%
'@
Set-Content -Path $ControlCmd -Value $cmdText -Encoding ASCII

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if ($userPath) {
    $pathParts = $userPath.Split(";") | Where-Object { $_ }
}

if ($pathParts -notcontains $BinDir) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
        $BinDir
    }
    else {
        "$userPath;$BinDir"
    }

    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "Added $BinDir to the user PATH."
}

Remove-ExistingService
Write-WinSWConfig

Write-Host "Installing Windows Service as LocalSystem..."
& $WinSWExe install | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "WinSW install failed. ExitCode=$LASTEXITCODE"
}

Write-Host "Starting Windows Service..."
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
    }
    catch {}
}

$serviceInfo = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"

Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Green
Write-Host "Windows Service : $ServiceName"
Write-Host "Service account : $($serviceInfo.StartName)"
Write-Host "Source profile  : $SourceUserProfile"
Write-Host "Dashboard       : $DashboardUrl"
Write-Host "Install dir     : $InstallDir"
Write-Host "Service logs    : $LogDir"
Write-Host ""
Write-Host "Open a NEW CMD or PowerShell window and use:"
Write-Host "  token-usage status"
Write-Host "  token-usage open"
Write-Host "  token-usage update"
Write-Host "  token-usage service"
Write-Host "  token-usage logs"
Write-Host ""

if ($ready) {
    Write-Host "RUNNING - $DashboardUrl" -ForegroundColor Green
    exit 0
}

Write-Host "The service was installed, but the Dashboard is not ready yet." -ForegroundColor Yellow
Write-Host "Run 'token-usage status' and 'token-usage logs' for diagnostics."
exit 2
