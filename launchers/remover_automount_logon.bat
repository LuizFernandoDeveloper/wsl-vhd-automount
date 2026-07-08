@echo off
setlocal

set "PROJECT_DIR=%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\Remove-StartupTask.ps1" %*
