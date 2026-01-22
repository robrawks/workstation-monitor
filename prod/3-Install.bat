@echo off
REM ============================================================================
REM Install WorkstationMonitor - Double-click to install and start
REM Requires Administrator rights (for any-user scheduled task)
REM ============================================================================

REM Check for admin rights and self-elevate if needed
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo ============================================
echo  Running as Administrator
echo ============================================
echo.
echo Installing WorkstationMonitor...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Monitor.ps1" -StartNow

echo.
pause
