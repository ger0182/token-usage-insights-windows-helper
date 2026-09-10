# Compatibility entry point.
# The helper has migrated from Windows Task Scheduler to a real Windows Service.
# New installations should use setup-token-usage-service.ps1 directly.

$ErrorActionPreference = "Stop"
$serviceSetup = Join-Path $PSScriptRoot "setup-token-usage-service.ps1"

if (!(Test-Path $serviceSetup)) {
    throw "找不到 $serviceSetup。請重新 clone / git pull 完整 Repository，不要只下載這個單一檔案。"
}

Write-Host "此 Helper 已改用 Windows Service。" -ForegroundColor Cyan
Write-Host "轉交給 setup-token-usage-service.ps1..."
& $serviceSetup @args
exit $LASTEXITCODE
