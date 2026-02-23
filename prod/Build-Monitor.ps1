<#
.SYNOPSIS
    Build WorkstationMonitor.exe from PowerShell script

.DESCRIPTION
    This script installs ps2exe (if needed) and compiles WorkstationMonitor.ps1 into
    a standalone EXE that runs in the background without a console window.

.NOTES
    Run this script ONCE to create the EXE.
    Requires internet connection (first time only, to download ps2exe).
#>

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Workstation Monitor EXE Builder" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = $PSScriptRoot
$SourceScript = Join-Path $ScriptDir "WorkstationMonitor.ps1"
$OutputExe = Join-Path $ScriptDir "WorkstationMonitor.exe"

# Check source exists
if (-not (Test-Path $SourceScript)) {
    Write-Error "WorkstationMonitor.ps1 not found in $ScriptDir"
    exit 1
}

# Step 1: Install ps2exe if not present
Write-Host "[1/3] Checking for ps2exe module..." -ForegroundColor Yellow

$module = Get-Module -ListAvailable -Name ps2exe
if (-not $module) {
    Write-Host "      Installing ps2exe from PowerShell Gallery..." -ForegroundColor Gray
    
    # Try to install for current user (no admin needed)
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
        Write-Host "      ps2exe installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "ERROR: Could not install ps2exe automatically." -ForegroundColor Red
        Write-Host ""
        Write-Host "Please run this command manually first:" -ForegroundColor Yellow
        Write-Host "  Install-Module -Name ps2exe -Scope CurrentUser -Force" -ForegroundColor White
        Write-Host ""
        Write-Host "Then run this build script again." -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "      ps2exe is already installed" -ForegroundColor Green
}

# Step 2: Import module
Write-Host "[2/3] Loading ps2exe..." -ForegroundColor Yellow
Import-Module ps2exe -Force
Write-Host "      Module loaded" -ForegroundColor Green

# Step 3: Compile to EXE
Write-Host "[3/3] Compiling WorkstationMonitor.exe..." -ForegroundColor Yellow

try {
    # Compile with these options:
    # -NoConsole: Run without showing a window (background service)
    # -NoOutput: Suppress compiler output
    # -Title: Sets the EXE metadata
    # -Company: Sets company in file properties
    # -Version: Sets version number
    
    Invoke-PS2EXE -InputFile $SourceScript `
                  -OutputFile $OutputExe `
                  -NoConsole `
                  -Title "Workstation Monitor" `
                  -Company "Your Organization" `
                  -Product "WorkstationMonitor" `
                  -Version "1.1.0.0" `
                  -Copyright "Your IT Team" `
                  -Description "Workstation performance monitoring agent"
    
    Write-Host "      Compilation successful!" -ForegroundColor Green
}
catch {
    Write-Error "Compilation failed: $_"
    exit 1
}

# Verify output
if (Test-Path $OutputExe) {
    $exeInfo = Get-Item $OutputExe
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host " Build Complete!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Output file: $OutputExe" -ForegroundColor Cyan
    Write-Host "Size:        $([math]::Round($exeInfo.Length / 1KB, 1)) KB" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Run '3-Install.bat' to schedule the monitor" -ForegroundColor White
    Write-Host "  2. Or manually run: WorkstationMonitor.exe" -ForegroundColor White
    Write-Host ""
    Write-Host "The EXE will run silently in the background." -ForegroundColor Gray
    Write-Host "Check C:\ProgramData\WorkstationMonitor\ for output files." -ForegroundColor Gray
} else {
    Write-Error "Output file was not created"
    exit 1
}
