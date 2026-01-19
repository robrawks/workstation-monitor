@echo off
REM ============================================================================
REM Build WorkstationMonitor.exe - Double-click to run
REM ============================================================================

echo.
echo Building WorkstationMonitor.exe...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Monitor.ps1"

echo.
pause
