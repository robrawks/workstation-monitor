<#
.SYNOPSIS
    Build Dashboard.exe from PowerShell script

.DESCRIPTION
    Compiles Dashboard.ps1 into a standalone EXE that can run from anywhere,
    including network shares, without PowerShell execution policy issues.
#>

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Dashboard EXE Builder" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = $PSScriptRoot
$SourceScript = Join-Path $ScriptDir "Dashboard.ps1"
$OutputExe = Join-Path $ScriptDir "Dashboard.exe"

# Check source exists
if (-not (Test-Path $SourceScript)) {
    Write-Error "Dashboard.ps1 not found in $ScriptDir"
    exit 1
}

# Step 1: Check ps2exe
Write-Host "[1/3] Checking for ps2exe module..." -ForegroundColor Yellow

$module = Get-Module -ListAvailable -Name ps2exe
if (-not $module) {
    Write-Host "      Installing ps2exe from PowerShell Gallery..." -ForegroundColor Gray
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
        Write-Host "      ps2exe installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "ERROR: Could not install ps2exe." -ForegroundColor Red
        Write-Host "Run: Install-Module -Name ps2exe -Scope CurrentUser -Force" -ForegroundColor Yellow
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
Write-Host "[3/3] Compiling Dashboard.exe..." -ForegroundColor Yellow

try {
    # Note: NOT using -NoConsole so users can see the server is running
    Invoke-PS2EXE -InputFile $SourceScript `
                  -OutputFile $OutputExe `
                  -Title "Workstation Monitor Dashboard" `
                  -Company "Your Organization" `
                  -Product "Dashboard" `
                  -Version "1.1.0.0" `
                  -Copyright "Your IT Team" `
                  -Description "Workstation monitoring dashboard"

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
    Write-Host "To run the dashboard:" -ForegroundColor Yellow
    Write-Host "  Double-click Open-Dashboard.bat" -ForegroundColor White
    Write-Host ""
} else {
    Write-Error "Output file was not created"
    exit 1
}
