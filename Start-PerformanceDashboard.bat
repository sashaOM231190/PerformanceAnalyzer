@echo off
setlocal

if "%~1"=="" (
    echo Usage:
    echo   %~nx0 "E:\Path\Capture.blg"
    echo.
    echo You can also drag and drop a .blg file onto this BAT file.
    exit /b 1
)

if /I not "%~x1"==".blg" (
    echo Error: Input must be a .blg file.
    exit /b 2
)

set "BLG=%~f1"
if not exist "%BLG%" (
    echo Error: BLG file not found:
    echo   %BLG%
    exit /b 3
)

set "DASHBOARD_SCRIPT=%~dp0Show-PerfCounterDashboard.ps1"
if not exist "%DASHBOARD_SCRIPT%" (
    echo Error: PowerShell dashboard script not found:
    echo   %DASHBOARD_SCRIPT%
    exit /b 4
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DASHBOARD_SCRIPT%" -InputPath "%BLG%"
exit /b %ERRORLEVEL%
