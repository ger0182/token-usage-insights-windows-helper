# Token Usage Insights - Windows Service uninstaller
# ASCII-only source for compatibility with Windows PowerShell 5.1.
#
# Default behavior:
# - Remove the Windows Service
# - Remove helper service files and token-usage.cmd
# - Preserve TokenUsageInsights itself and its SQLite database
#
# Use -RemoveAll to also delete the application directory and all saved usage data.

[CmdletBinding()]
param(
    [switch]$RemoveAll
)

$ErrorActionPreference = "Stop"

$ServiceName = "TokenUsageInsights"
$InstallDir = Join-Path $env:LOCALAPPDATA "TokenUsageInsights"
$ServiceDir = Join-Path $InstallDir "service"
$WinSWExe = Join-Path $ServiceDir "TokenUsageInsightsService.exe"
$ControlCmd = Join-Path (Join-Path $env:USERPROFILE "bin") "token-usage.cmd"

function Test-Admin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
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

if (-not (Test-Admin)) {
    Write-Host "Administrator privileges are required." -ForegroundColor Yellow
    Write-Host "Open PowerShell as Administrator and run:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($RemoveAll) {
        Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -RemoveAll"
    }
    exit 1
}

Write-Host "=== Token Usage Insights Windows Service Uninstall ===" -ForegroundColor Cyan

$oldTask = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
if ($oldTask) {
    Write-Host "Removing old Task Scheduler entry..."
    try {
        Stop-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    }
    catch {}
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false -ErrorAction SilentlyContinue
}

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -ne "Stopped") {
        Write-Host "Stopping Windows Service..."
        Stop-Service -Name $ServiceName -Force
        $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20))
    }

    Write-Host "Removing Windows Service..."
    if (Test-Path $WinSWExe) {
        & $WinSWExe uninstall | Out-Host
        if ($LASTEXITCODE -ne 0) {
            & sc.exe delete $ServiceName | Out-Host
        }
    }
    else {
        & sc.exe delete $ServiceName | Out-Host
    }

    Wait-ServiceDeleted -Name $ServiceName
}

Get-Process "token-usage-insights" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item $ControlCmd -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $InstallDir "token-usage-background.cmd") -Force -ErrorAction SilentlyContinue
Remove-Item $ServiceDir -Recurse -Force -ErrorAction SilentlyContinue

if ($RemoveAll) {
    Write-Host "Removing TokenUsageInsights application and saved data..." -ForegroundColor Yellow
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

    $officialShim = Join-Path (Join-Path $env:USERPROFILE "bin") "token-usage-insights.cmd"
    Remove-Item $officialShim -Force -ErrorAction SilentlyContinue

    Write-Host "Application and SQLite history removed." -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "Service/helper removed." -ForegroundColor Green
    Write-Host "TokenUsageInsights and SQLite history were preserved:"
    Write-Host "  $InstallDir"
    Write-Host ""
    Write-Host "Use -RemoveAll only if you also want to delete all saved usage history."
}
