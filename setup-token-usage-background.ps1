# Compatibility entry point.
# This helper now uses a real Windows Service instead of Task Scheduler.

$ErrorActionPreference = "Stop"

$serviceSetup = Join-Path $PSScriptRoot "setup-token-usage-service.ps1"

if (-not (Test-Path $serviceSetup)) {
    throw "setup-token-usage-service.ps1 was not found. Run git pull or clone the full repository."
}

Write-Host "This helper now uses a Windows Service."
Write-Host "Forwarding to setup-token-usage-service.ps1..."
& $serviceSetup @args
exit $LASTEXITCODE
