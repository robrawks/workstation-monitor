@echo off
REM ============================================================================
REM Open Dashboard - View metrics in browser
REM ============================================================================

echo.
echo Starting Workstation Monitor Dashboard...
echo.
echo Press Ctrl+C to stop the dashboard server.
echo.

start "" "http://localhost:9090"
"%~dp0Dashboard.exe"
