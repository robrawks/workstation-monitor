<#
.SYNOPSIS
    Install WorkstationMonitor.exe as a scheduled background task

.DESCRIPTION
    Creates a Windows Scheduled Task that:
    - Starts WorkstationMonitor.exe at user logon
    - Runs hidden in the background
    - Restarts if it crashes
    - Runs as the current user (no admin needed for basic install)

.PARAMETER Uninstall
    Remove the scheduled task and stop the monitor

.PARAMETER StartNow
    Start the monitor immediately after installation
#>

param(
    [switch]$Uninstall,
    [switch]$StartNow
)

$ErrorActionPreference = 'Stop'

$TaskName = "WorkstationMonitor"
$ScriptDir = $PSScriptRoot
$ExePath = Join-Path $ScriptDir "WorkstationMonitor.exe"
$ConfigPath = Join-Path $ScriptDir "config.json"
$InstallPath = "$env:ProgramData\WorkstationMonitor"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Workstation Monitor Installer" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Uninstall mode
if ($Uninstall) {
    Write-Host "Removing WorkstationMonitor..." -ForegroundColor Yellow

    # Stop any running instance
    Get-Process -Name "WorkstationMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
    
    # Remove scheduled task
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    Write-Host "  Scheduled task removed" -ForegroundColor Green
    Write-Host ""
    Write-Host "Uninstall complete." -ForegroundColor Green
    Write-Host "Data preserved in: $InstallPath" -ForegroundColor Gray
    exit 0
}

# Check EXE exists
if (-not (Test-Path $ExePath)) {
    Write-Host "ERROR: WorkstationMonitor.exe not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run '1-Build-Monitor.bat' first to create the executable." -ForegroundColor Yellow
    exit 1
}

# Step 1: Create install directory
Write-Host "[1/5] Creating installation directory..." -ForegroundColor Yellow
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
}
Write-Host "      $InstallPath" -ForegroundColor Green

# Step 2: Set secure folder permissions (Security Fix)
Write-Host "[2/5] Setting secure folder permissions..." -ForegroundColor Yellow
try {
    $acl = Get-Acl $InstallPath
    # Remove inherited permissions and start fresh
    $acl.SetAccessRuleProtection($true, $false)
    # Administrators get full control
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($adminRule)
    # SYSTEM account needs access for scheduled task
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($systemRule)
    # Current user gets modify access
    $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $env:USERNAME, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($userRule)
    Set-Acl -Path $InstallPath -AclObject $acl
    Write-Host "      Folder secured (Admins + current user only)" -ForegroundColor Green
}
catch {
    Write-Host "      Warning: Could not set ACLs (non-critical)" -ForegroundColor Yellow
}

# Step 3: Copy files
Write-Host "[3/5] Copying files..." -ForegroundColor Yellow
Copy-Item -Path $ExePath -Destination $InstallPath -Force
if (Test-Path $ConfigPath) {
    Copy-Item -Path $ConfigPath -Destination $InstallPath -Force
}
Write-Host "      Files copied" -ForegroundColor Green

# Step 4: Create scheduled task
Write-Host "[4/5] Creating scheduled task..." -ForegroundColor Yellow

$InstalledExe = Join-Path $InstallPath "WorkstationMonitor.exe"

# Remove existing task if present
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Stop any running instance
Get-Process -Name "WorkstationMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

try {
    # Create the action - run the EXE from the install path
    $Action = New-ScheduledTaskAction -Execute $InstalledExe -WorkingDirectory $InstallPath

    # Trigger: at user logon (runs as logged-in user for share access)
    $Trigger = New-ScheduledTaskTrigger -AtLogon

    # Settings for reliable background operation
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Days 365)

    # Register the task
    Register-ScheduledTask -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Description "Workstation Monitor - Background performance monitoring" | Out-Null

    Write-Host "      Scheduled task created (runs at user logon)" -ForegroundColor Green
}
catch {
    Write-Warning "Could not create scheduled task automatically."
    Write-Host ""
    Write-Host "This might require administrator privileges." -ForegroundColor Yellow
    Write-Host "Alternative: You can manually add WorkstationMonitor.exe to your Startup folder." -ForegroundColor Yellow
    Write-Host ""
    
    # Create startup shortcut as alternative
    $StartupFolder = [Environment]::GetFolderPath('Startup')
    $ShortcutPath = Join-Path $StartupFolder "WorkstationMonitor.lnk"

    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $InstalledExe
    $Shortcut.WorkingDirectory = $InstallPath
    $Shortcut.WindowStyle = 7  # Minimized
    $Shortcut.Description = "Workstation Monitor"
    $Shortcut.Save()
    
    Write-Host "Created startup shortcut instead: $ShortcutPath" -ForegroundColor Cyan
}

# Step 5: Create helper shortcuts
Write-Host "[5/5] Creating shortcuts..." -ForegroundColor Yellow

# Stop Monitor shortcut
$StopScript = @'
Get-Process -Name "WorkstationMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "WorkstationMonitor stopped." -ForegroundColor Green
'@
$StopScript | Set-Content (Join-Path $InstallPath "Stop-Monitor.ps1")

$Shell = New-Object -ComObject WScript.Shell

# Create "View Data" shortcut
$ViewShortcut = $Shell.CreateShortcut((Join-Path $InstallPath "View Metrics.lnk"))
$ViewShortcut.TargetPath = "explorer.exe"
$ViewShortcut.Arguments = $InstallPath
$ViewShortcut.Save()

Write-Host "      Shortcuts created" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Installation Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Install location: $InstallPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "The monitor will:" -ForegroundColor Yellow
Write-Host "  - Start automatically when any user logs in" -ForegroundColor White
Write-Host "  - Run silently in the background" -ForegroundColor White
Write-Host "  - Save metrics to $InstallPath" -ForegroundColor White
Write-Host ""

# Start now if requested
if ($StartNow) {
    Write-Host "Starting monitor now..." -ForegroundColor Yellow
    
    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
    catch {
        # Fallback: start directly
        Start-Process -FilePath $InstalledExe -WorkingDirectory $InstallPath -WindowStyle Hidden
    }
    
    Start-Sleep -Seconds 2
    
    $proc = Get-Process -Name "WorkstationMonitor" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "  Monitor is running (PID: $($proc.Id))" -ForegroundColor Green
    }
}
else {
    Write-Host "To start now, run:" -ForegroundColor Yellow
    Write-Host "  Start-ScheduledTask -TaskName 'WorkstationMonitor'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Or just log out and back in." -ForegroundColor Gray
}

Write-Host ""
Write-Host "To view collected data:" -ForegroundColor Yellow
Write-Host "  explorer.exe `"$InstallPath`"" -ForegroundColor Gray
Write-Host ""
