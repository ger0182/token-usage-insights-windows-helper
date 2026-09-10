# Token Usage Insights - Windows background setup
# Installs the official Windows build if necessary, creates an auto-start Scheduled Task,
# and installs a `token-usage` command with:
#   start / stop / restart / status / open / update / version
#
# Update behavior:
# - Stops Token Usage Insights
# - Backs up the SQLite DB to token_usage_insights.db.pre-update.bak
# - Re-runs the official get.ps1 installer against the same install directory
# - Keeps the existing SQLite DB
# - Restarts the Scheduled Task
# - Reports the installed version

$ErrorActionPreference = "Stop"

$TaskName   = "TokenUsageInsights"
$InstallDir = Join-Path $env:LOCALAPPDATA "TokenUsageInsights"
$Exe        = Join-Path $InstallDir "token-usage-insights.exe"
$BinDir     = Join-Path $HOME "bin"
$Controller = Join-Path $BinDir "token-usage.cmd"
$Launcher   = Join-Path $InstallDir "token-usage-background.cmd"
$Updater    = Join-Path $InstallDir "token-usage-update.ps1"
$Port       = 3003

Write-Host "=== Token Usage Insights background setup ===" -ForegroundColor Cyan

# Avoid colliding with an existing npx instance on port 3003.
$existingListener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existingListener -and -not (Get-Process "token-usage-insights" -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "Port $Port is already in use." -ForegroundColor Yellow
    Write-Host "If npx token-usage-insights is currently running, close that CMD first, then run this setup again."
    exit 2
}

# Install official native Windows build if it is not already present.
if (!(Test-Path $Exe)) {
    Write-Host "Official Windows build not found. Installing..."
    $GetScript = Join-Path $env:TEMP "token-usage-insights-get.ps1"
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/doggy8088/TokenUsageInsights/main/scripts/get.ps1" `
        -OutFile $GetScript
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GetScript `
        -InstallDir $InstallDir `
        -BinDir $BinDir `
        -Port $Port
}

if (!(Test-Path $Exe)) {
    throw "Installation finished but executable was not found: $Exe"
}

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

# Launcher used by Task Scheduler. The task stays alive while the executable is running.
# HOST is intentionally bound to localhost only.
$launcherText = @"
@echo off
setlocal
set "HOST=127.0.0.1"
set "PORT=$Port"
cd /d "$InstallDir"
"$Exe"
"@
Set-Content -Path $Launcher -Value $launcherText -Encoding ASCII

# Separate PowerShell updater keeps CMD quoting simple and makes failures easier to handle.
$updaterText = @'
param(
    [int]$Port = 3003
)

$ErrorActionPreference = "Stop"

$TaskName   = "TokenUsageInsights"
$InstallDir = Join-Path $env:LOCALAPPDATA "TokenUsageInsights"
$BinDir     = Join-Path $HOME "bin"
$Exe        = Join-Path $InstallDir "token-usage-insights.exe"
$DbPath     = Join-Path $InstallDir "token_usage_insights.db"
$BackupPath = Join-Path $InstallDir "token_usage_insights.db.pre-update.bak"
$VersionFile = Join-Path $InstallDir "VERSION"
$GetScript  = Join-Path $env:TEMP "token-usage-insights-get.ps1"
$Url        = "http://127.0.0.1:$Port"

function Get-InstalledVersion {
    if (Test-Path $VersionFile) {
        return (Get-Content $VersionFile -TotalCount 1).Trim()
    }
    return "unknown"
}

$before = Get-InstalledVersion

Write-Host "Token Usage Insights update" -ForegroundColor Cyan
Write-Host "Current version: $before"

try {
    # Stop current instance before replacing the executable/static assets.
    $running = Get-Process "token-usage-insights" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "Stopping current instance..."
        $running | Stop-Process -Force
        $running | Wait-Process -ErrorAction SilentlyContinue
    }

    # Keep one safety backup of the local SQLite database.
    # The official installer itself does not remove this DB.
    if (Test-Path $DbPath) {
        Write-Host "Backing up database..."
        Copy-Item -Force $DbPath $BackupPath
        Write-Host "Backup: $BackupPath"
    }

    Write-Host "Downloading official updater..."
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/doggy8088/TokenUsageInsights/main/scripts/get.ps1" `
        -OutFile $GetScript `
        -UseBasicParsing

    Write-Host "Installing latest release..."
    & $GetScript -InstallDir $InstallDir -BinDir $BinDir -Port $Port

    if (!(Test-Path $Exe)) {
        throw "Update completed but executable is missing: $Exe"
    }

    $after = Get-InstalledVersion
    Write-Host "Installed version: $after" -ForegroundColor Green

    Write-Host "Starting background service..."
    Start-ScheduledTask -TaskName $TaskName

    # Wait briefly for the web endpoint to become ready.
    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $r = Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 1
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {
                $ready = $true
                break
            }
        } catch {
            # Keep waiting while the process starts.
        }
    }

    if ($ready) {
        Write-Host ""
        if ($before -eq $after) {
            Write-Host "Already up to date: $after" -ForegroundColor Green
        } else {
            Write-Host "Updated: $before -> $after" -ForegroundColor Green
        }
        Write-Host "RUNNING - $Url" -ForegroundColor Green
        exit 0
    }

    if (Get-Process "token-usage-insights" -ErrorAction SilentlyContinue) {
        Write-Host "Update succeeded, process is running, but the web endpoint is not ready yet." -ForegroundColor Yellow
        exit 0
    }

    throw "Update installed successfully, but Token Usage Insights did not restart."
}
catch {
    Write-Host ""
    Write-Host "UPDATE FAILED: $($_.Exception.Message)" -ForegroundColor Red

    # Best effort: restart whatever executable remains after a failed update.
    if (Test-Path $Exe) {
        try {
            Write-Host "Attempting to restart the installed version..."
            Start-ScheduledTask -TaskName $TaskName
        } catch {
            Write-Host "Automatic restart also failed." -ForegroundColor Red
        }
    }

    exit 1
}
finally {
    Remove-Item $GetScript -Force -ErrorAction SilentlyContinue
}
'@
Set-Content -Path $Updater -Value $updaterText -Encoding UTF8

# Controller command.
$controllerText = @'
@echo off
setlocal
set "TASK=TokenUsageInsights"
set "URL=http://127.0.0.1:3003"
set "INSTALLDIR=%LOCALAPPDATA%\TokenUsageInsights"
set "UPDATER=%LOCALAPPDATA%\TokenUsageInsights\token-usage-update.ps1"
set "VERSIONFILE=%LOCALAPPDATA%\TokenUsageInsights\VERSION"

if /I "%~1"=="start" goto START
if /I "%~1"=="stop" goto STOP
if /I "%~1"=="restart" goto RESTART
if /I "%~1"=="status" goto STATUS
if /I "%~1"=="open" goto OPEN
if /I "%~1"=="update" goto UPDATE
if /I "%~1"=="version" goto VERSION
goto HELP

:START
tasklist /FI "IMAGENAME eq token-usage-insights.exe" 2>NUL | find /I "token-usage-insights.exe" >NUL
if not errorlevel 1 (
    echo Token Usage Insights is already running.
    echo %URL%
    exit /b 0
)
schtasks /Run /TN "%TASK%" >NUL 2>&1
if errorlevel 1 (
    echo Failed to start scheduled task "%TASK%".
    exit /b 1
)
timeout /t 1 /nobreak >NUL
call "%~f0" status
exit /b %ERRORLEVEL%

:STOP
taskkill /IM token-usage-insights.exe /F >NUL 2>&1
if errorlevel 1 (
    echo Token Usage Insights is not running.
) else (
    echo Token Usage Insights stopped.
)
exit /b 0

:RESTART
call "%~f0" stop
timeout /t 1 /nobreak >NUL
call "%~f0" start
exit /b %ERRORLEVEL%

:STATUS
tasklist /FI "IMAGENAME eq token-usage-insights.exe" 2>NUL | find /I "token-usage-insights.exe" >NUL
if errorlevel 1 (
    echo STOPPED
    exit /b 1
)
powershell.exe -NoProfile -Command ^
  "try { $r=Invoke-WebRequest '%URL%' -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -ge 200 -and $r.StatusCode -lt 500){Write-Host 'RUNNING - %URL%'; exit 0} } catch {}; Write-Host 'PROCESS RUNNING - web endpoint not ready'; exit 2"
exit /b %ERRORLEVEL%

:OPEN
start "" "%URL%"
exit /b 0

:UPDATE
if not exist "%UPDATER%" (
    echo Updater not found:
    echo   %UPDATER%
    echo Re-run setup-token-usage-background.ps1 first.
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPDATER%"
exit /b %ERRORLEVEL%

:VERSION
if exist "%VERSIONFILE%" (
    set /p TUI_VERSION=<"%VERSIONFILE%"
    echo Installed version: %TUI_VERSION%
) else (
    echo Installed version: unknown
)
exit /b 0

:HELP
echo Usage:
echo   token-usage start     Start background service
echo   token-usage stop      Stop background service
echo   token-usage restart   Restart background service
echo   token-usage status    Check service and dashboard
echo   token-usage open      Open dashboard
echo   token-usage update    Update to the latest official release
echo   token-usage version   Show installed version
exit /b 0
'@
Set-Content -Path $Controller -Value $controllerText -Encoding ASCII

# Add ~/bin to the user's PATH if needed.
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if ($userPath) { $pathParts = $userPath.Split(";") | Where-Object { $_ } }
if ($pathParts -notcontains $BinDir) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $BinDir } else { "$userPath;$BinDir" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "Added $BinDir to your user PATH."
}

# Register an auto-start task for the current user.
$action = New-ScheduledTaskAction `
    -Execute $env:ComSpec `
    -Argument "/d /c `"$Launcher`"" `
    -WorkingDirectory $InstallDir

$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Run Token Usage Insights in the background at user logon." `
    -Force | Out-Null

# Start now if not already running.
if (!(Get-Process "token-usage-insights" -ErrorAction SilentlyContinue)) {
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Green
Write-Host "Dashboard: http://127.0.0.1:$Port"
Write-Host "Install directory: $InstallDir"
Write-Host "Auto-start task: $TaskName"
Write-Host "Controller: $Controller"
Write-Host "Updater: $Updater"
Write-Host ""
Write-Host "Open a NEW CMD window, then use:"
Write-Host "  token-usage start"
Write-Host "  token-usage stop"
Write-Host "  token-usage status"
Write-Host "  token-usage restart"
Write-Host "  token-usage open"
Write-Host "  token-usage update"
Write-Host "  token-usage version"
Write-Host ""

if (Test-Path (Join-Path $InstallDir "VERSION")) {
    $installedVersion = (Get-Content (Join-Path $InstallDir "VERSION") -TotalCount 1).Trim()
    Write-Host "Installed version: $installedVersion"
}

$p = Get-Process "token-usage-insights" -ErrorAction SilentlyContinue
if ($p) {
    Write-Host "Current status: RUNNING (PID $($p.Id))" -ForegroundColor Green
} else {
    Write-Host "Current status: not running yet. Try: token-usage start" -ForegroundColor Yellow
}
