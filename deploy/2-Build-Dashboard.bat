@echo off
REM ============================================================================
REM Build Dashboard.exe - Run this once before sharing the dashboard
REM ============================================================================

echo.
echo Building Dashboard.exe...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Dashboard.ps1"

echo.
pause
