@echo off
setlocal

for %%I in ("%~dp0..") do set "PROJECT_DIR=%%~fI"
set "LOG_DIR=%~dp0logs"
set "LOG_FILE=%LOG_DIR%\install-startup-task.latest.log"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul

> "%LOG_FILE%" (
    echo [%DATE% %TIME%] Iniciando instalador do automount WSL VHD.
    echo Projeto: %PROJECT_DIR%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\Install-StartupTask.ps1" -RunNow -InstallLogPath "%LOG_FILE%" %*
set "EXIT_CODE=%ERRORLEVEL%"

>> "%LOG_FILE%" (
    echo.
    echo [%DATE% %TIME%] Launcher finalizado com codigo %EXIT_CODE%.
)

if not "%EXIT_CODE%"=="0" (
    echo.
    echo [ERROR] Falhou ao instalar o automount.
    echo [INFO] Log salvo em:
    echo "%LOG_FILE%"
    echo.
    pause
)

exit /b %EXIT_CODE%
