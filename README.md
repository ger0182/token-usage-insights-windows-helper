# Token Usage Insights Windows Helper

Windows helper for running [TokenUsageInsights](https://github.com/doggy8088/TokenUsageInsights) in the background without keeping a CMD / PowerShell window open.

> This repository is an **unofficial helper**. TokenUsageInsights itself is maintained by the upstream project.

## What this helper does

The setup script:

- Installs the official native Windows build of TokenUsageInsights if it is not already installed.
- Runs TokenUsageInsights in the background through Windows Task Scheduler.
- Starts it automatically when the current Windows user signs in.
- Adds a convenient `token-usage` command.
- Binds the dashboard to `127.0.0.1:3003` so it is only accessible from the local PC.
- Provides an update command that backs up the SQLite database before upgrading.

## Requirements

- Windows 10 / 11
- PowerShell
- Internet access during installation and updates

Before running the setup script, close any CMD window currently running:

```cmd
npx -y token-usage-insights
```

Otherwise port `3003` may already be occupied.

## Installation

Clone this repository:

```cmd
git clone https://github.com/ger0182/token-usage-insights-windows-helper.git
cd token-usage-insights-windows-helper
```

Run the setup script from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-background.ps1"
```

After setup finishes, open a **new CMD window** so the updated user `PATH` is loaded.

Check the service:

```cmd
token-usage status
```

Open the dashboard:

```cmd
token-usage open
```

Dashboard URL:

```text
http://127.0.0.1:3003
```

## Commands

| Command | Purpose |
| --- | --- |
| `token-usage start` | Start TokenUsageInsights in the background |
| `token-usage stop` | Stop TokenUsageInsights |
| `token-usage restart` | Restart TokenUsageInsights |
| `token-usage status` | Check whether the process and dashboard are running |
| `token-usage open` | Open the dashboard in the default browser |
| `token-usage update` | Update to the latest official TokenUsageInsights release |
| `token-usage version` | Show the currently installed version |

Running `token-usage` without an argument also prints the command list.

## Windows auto-start

The setup script creates this Windows Task Scheduler task:

```text
TokenUsageInsights
```

Trigger:

```text
Current user logon
```

This means the dashboard starts automatically after signing in to Windows. A CMD window does not need to remain open.

## Installation locations

Main TokenUsageInsights installation directory:

```text
%LOCALAPPDATA%\TokenUsageInsights
```

Usually this resolves to:

```text
C:\Users\<username>\AppData\Local\TokenUsageInsights
```

Important files include:

```text
%LOCALAPPDATA%\TokenUsageInsights\token-usage-insights.exe
%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db
%LOCALAPPDATA%\TokenUsageInsights\token-usage-background.cmd
%LOCALAPPDATA%\TokenUsageInsights\token-usage-update.ps1
```

The helper command is installed at:

```text
%USERPROFILE%\bin\token-usage.cmd
```

The official installer also places its own `token-usage-insights.cmd` shim in `%USERPROFILE%\bin`.

## Updating TokenUsageInsights

Use:

```cmd
token-usage update
```

The helper performs the following sequence:

```text
Stop current process
        ↓
Back up SQLite database
        ↓
Download the official latest release
        ↓
Run the official Windows installer
        ↓
Keep the existing usage database
        ↓
Restart the scheduled task
        ↓
Check http://127.0.0.1:3003
```

Before each update, the database is copied to:

```text
%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db.pre-update.bak
```

The upstream `get.ps1` installer is designed to be safe to re-run for upgrades.

To check the installed version:

```cmd
token-usage version
```

## Data / database

Token usage history is stored in:

```text
%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db
```

Do not delete this file if you want to keep existing usage history.

For an extra manual backup:

```cmd
copy "%LOCALAPPDATA%\TokenUsageInsights\token_usage_insights.db" "%USERPROFILE%\Desktop\token_usage_insights.db.bak"
```

## Re-running setup

It is safe to re-run:

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-background.ps1"
```

This refreshes the helper scripts and Task Scheduler configuration. If TokenUsageInsights is already installed, the setup does not reinstall it unnecessarily.

Use this after pulling a newer version of this helper repository:

```cmd
git pull
powershell -ExecutionPolicy Bypass -File ".\setup-token-usage-background.ps1"
```

## Troubleshooting

### `token-usage` is not recognized

Open a new CMD / PowerShell window after running the setup script.

The setup adds this directory to the user `PATH`:

```text
%USERPROFILE%\bin
```

You can verify the command with:

```cmd
where token-usage
```

### Port 3003 is already in use

Check which process is listening on the port:

```powershell
Get-NetTCPConnection -LocalPort 3003 -State Listen
```

If the old `npx` version is still running, close that CMD window before running the setup again.

### Process is running but the page is not ready

Check:

```cmd
token-usage status
```

Then try:

```cmd
token-usage restart
```

### Check the Windows scheduled task

PowerShell:

```powershell
Get-ScheduledTask -TaskName "TokenUsageInsights"
```

Or open Windows **Task Scheduler** and look for `TokenUsageInsights`.

## Uninstall helper / auto-start

First stop TokenUsageInsights:

```cmd
token-usage stop
```

Remove the scheduled task:

```powershell
Unregister-ScheduledTask -TaskName "TokenUsageInsights" -Confirm:$false
```

Remove helper files:

```powershell
Remove-Item "$HOME\bin\token-usage.cmd" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\TokenUsageInsights\token-usage-background.cmd" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\TokenUsageInsights\token-usage-update.ps1" -Force -ErrorAction SilentlyContinue
```

If you also want to completely remove TokenUsageInsights and **do not need the usage history anymore**, remove the application directory:

```powershell
Remove-Item "$env:LOCALAPPDATA\TokenUsageInsights" -Recurse -Force
```

> Warning: the final command also deletes `token_usage_insights.db` and therefore removes the stored usage history.

## Upstream project

TokenUsageInsights:

https://github.com/doggy8088/TokenUsageInsights

Official Windows bootstrap installer used by this helper:

```powershell
irm https://raw.githubusercontent.com/doggy8088/TokenUsageInsights/main/scripts/get.ps1 | iex
```

## Repository files

```text
setup-token-usage-background.ps1   Main Windows setup/helper script
README.md                           Installation and usage notes
```
