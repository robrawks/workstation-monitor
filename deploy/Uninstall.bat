@echo off
REM ============================================================================
REM Uninstall WorkstationMonitor - Removes scheduled task
REM ============================================================================

echo.
echo Uninstalling WorkstationMonitor...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Monitor.ps1" -Uninstall

echo.
pause
