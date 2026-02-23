<#
.SYNOPSIS
    Install WorkstationMonitor.exe as a scheduled background task

.DESCRIPTION
    Creates a Windows Scheduled Task that:
    - Starts WorkstationMonitor.exe at system startup (runs as SYSTEM)
    - Runs hidden in the background
    - Restarts if it crashes
    - Runs as NT AUTHORITY\SYSTEM (persists across user sessions)

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
    
    # Remove scheduled tasks
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "${TaskName}Sync" -Confirm:$false -ErrorAction SilentlyContinue
    
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
$SyncExePath = Join-Path $ScriptDir "SyncMetrics.exe"
if (Test-Path $SyncExePath) {
    Copy-Item -Path $SyncExePath -Destination $InstallPath -Force
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

    # Trigger: at system startup (runs as SYSTEM, independent of user sessions)
    $Trigger = New-ScheduledTaskTrigger -AtStartup

    # Run as SYSTEM - persists across user logon/logoff, survives reboots
    $Principal = New-ScheduledTaskPrincipal `
        -UserId "NT AUTHORITY\SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

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
        -Principal $Principal `
        -Description "Workstation Monitor - Background performance monitoring" | Out-Null

    Write-Host "      Scheduled task created (runs at system startup as SYSTEM)" -ForegroundColor Green
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

# Step 4b: Create sync task (runs as logged-in user for network share access)
$SyncExe = Join-Path $InstallPath "SyncMetrics.exe"
if (Test-Path $SyncExe) {
    Write-Host "[4b/5] Creating sync task..." -ForegroundColor Yellow

    $SyncTaskName = "WorkstationMonitorSync"
    Unregister-ScheduledTask -TaskName $SyncTaskName -Confirm:$false -ErrorAction SilentlyContinue

    try {
        $SyncAction = New-ScheduledTaskAction -Execute $SyncExe -WorkingDirectory $InstallPath
        $SyncTrigger = New-ScheduledTaskTrigger -AtLogon

        # Run as the installing admin user with "run whether logged on or not"
        # This allows the sync to run in the background using stored credentials
        $SyncSettings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RestartCount 3 `
            -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit (New-TimeSpan -Days 365)

        Register-ScheduledTask -TaskName $SyncTaskName `
            -Action $SyncAction `
            -Trigger $SyncTrigger `
            -Settings $SyncSettings `
            -User $env:USERNAME `
            -RunLevel Highest `
            -Description "Workstation Monitor Sync - Copies metrics to network share" | Out-Null

        Write-Host "      Sync task created (runs as $env:USERNAME at logon)" -ForegroundColor Green
        Write-Host "      NOTE: Windows may prompt for your password to store credentials" -ForegroundColor Yellow
    } catch {
        Write-Host "      Warning: Could not create sync task (non-critical)" -ForegroundColor Yellow
    }
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
Write-Host "  - Start automatically at system boot (runs as SYSTEM)" -ForegroundColor White
Write-Host "  - Persist across all user sessions (admin, rad, etc.)" -ForegroundColor White
Write-Host "  - Run silently in the background" -ForegroundColor White
Write-Host "  - Save metrics to $InstallPath" -ForegroundColor White
Write-Host "  - Sync metrics to network share when a user is logged in" -ForegroundColor White
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
    Write-Host "Or restart the computer." -ForegroundColor Gray
}

Write-Host ""
Write-Host "To view collected data:" -ForegroundColor Yellow
Write-Host "  explorer.exe `"$InstallPath`"" -ForegroundColor Gray
Write-Host ""
