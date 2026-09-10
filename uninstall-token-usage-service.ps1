# Uninstall Token Usage Insights Windows Service helper.
# By default this removes only the helper/service and preserves TokenUsageInsights + SQLite data.

[CmdletBinding()]
param(
    [switch]$RemoveAll
)

$ErrorActionPreference = "Stop"
$ServiceName = "TokenUsageInsights"
$InstallDir = Join-Path $env:LOCALAPPDATA "TokenUsageInsights"
$ServiceDir = Join-Path $InstallDir "service"
$WinSWExe = Join-Path $ServiceDir "TokenUsageInsightsService.exe"
$ControllerCmd = Join-Path (Join-Path $env:USERPROFILE "bin") "token-usage.cmd"

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Host "此移除程式需要系統管理員權限。" -ForegroundColor Yellow
    Write-Host "請以『系統管理員身分』開啟 PowerShell 後重新執行。"
    exit 1
}

Write-Host "=== 移除 Token Usage Insights Windows Service ===" -ForegroundColor Cyan

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -ne "Stopped") {
        Write-Host "停止 Windows Service..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        try { $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(20)) } catch {}
    }

    Write-Host "移除 Windows Service..."
    if (Test-Path $WinSWExe) {
        & $WinSWExe uninstall | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WinSW uninstall 回傳 $LASTEXITCODE，改用 sc.exe delete。" -ForegroundColor Yellow
            & sc.exe delete $ServiceName | Out-Host
        }
    }
    else {
        & sc.exe delete $ServiceName | Out-Host
    }
}
else {
    Write-Host "Windows Service 不存在，略過。"
}

# Also clean up the old Task Scheduler implementation if it still exists.
$oldTask = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
if ($oldTask) {
    Write-Host "移除舊版工作排程器設定..."
    try { Stop-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue } catch {}
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false -ErrorAction SilentlyContinue
}

Remove-Item $ControllerCmd -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $InstallDir "token-usage-background.cmd") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $InstallDir "token-usage-update.ps1") -Force -ErrorAction SilentlyContinue
Remove-Item $ServiceDir -Recurse -Force -ErrorAction SilentlyContinue

if ($RemoveAll) {
    Write-Host ""
    Write-Host "-RemoveAll 已指定，將刪除 TokenUsageInsights 本體與 SQLite 使用紀錄。" -ForegroundColor Yellow
    Get-Process "token-usage-insights" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "已完整移除：$InstallDir" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "Service 與 Helper 已移除。" -ForegroundColor Green
    Write-Host "TokenUsageInsights 本體與資料庫仍保留於："
    Write-Host "  $InstallDir"
    Write-Host ""
    Write-Host "若確定連歷史紀錄都不要，可重新執行："
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -RemoveAll"
}
