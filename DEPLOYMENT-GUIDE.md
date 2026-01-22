# HFMonitor Deployment Guide

## Health First Enterprise Deployment for Radiologist Workstations

This guide provides step-by-step instructions for deploying HFMonitor across approximately 40 radiologist workstations at Health First. The guide is written for IT staff and assumes basic Windows administration knowledge.

**Document Version:** 1.0
**Last Updated:** January 2026
**Target Environment:** Windows 11 Professional workstations

---

## Table of Contents

- [Overview](#overview)
- [Part 1: Single Workstation Deployment](#part-1-single-workstation-deployment)
- [Part 2: Centralized Dashboard Setup](#part-2-centralized-dashboard-setup)
- [Part 3: Mass Deployment Options](#part-3-mass-deployment-options)
- [Appendix A: Configuration Reference](#appendix-a-configuration-reference)
- [Appendix B: Troubleshooting Guide](#appendix-b-troubleshooting-guide)
- [Appendix C: Quick Reference Commands](#appendix-c-quick-reference-commands)

---

## Overview

### What is HFMonitor?

HFMonitor is a lightweight monitoring agent that collects performance metrics from radiologist workstations. It tracks:

- **CPU usage** - Overall processor utilization and top consuming processes
- **Memory usage** - RAM utilization and memory-heavy applications
- **Network activity** - Interface status and throughput
- **Network latency** - Ping times to configured targets (PACS servers, internet)
- **DICOM connectivity** - Port availability checks to PACS/imaging servers

### Architecture Overview

```
+------------------+     +------------------+     +------------------+
|  Workstation 1   |     |  Workstation 2   |     |  Workstation N   |
|  HFMonitor.exe   |     |  HFMonitor.exe   |     |  HFMonitor.exe   |
|       |          |     |       |          |     |       |          |
|  metrics.json    |     |  metrics.json    |     |  metrics.json    |
+--------|---------+     +--------|---------+     +--------|---------+
         |                        |                        |
         +------------------------+------------------------+
                                  |
                                  v
                     +------------------------+
                     |   Network Share        |
                     |   \\server\HFMonitor   |
                     |   +-- WORKSTATION1.json|
                     |   +-- WORKSTATION2.json|
                     |   +-- WORKSTATION-N.json|
                     +------------------------+
                                  |
                                  v
                     +------------------------+
                     |   Central Dashboard    |
                     |   HFDashboard.ps1      |
                     |   http://server:8080   |
                     +------------------------+
```

### Package Contents

| File | Purpose |
|------|---------|
| `0-Test-Once.bat` | Test the monitor before full deployment |
| `1-Build-EXE.bat` | Compile PowerShell script to EXE |
| `2-Install-and-Start.bat` | Install monitor and start immediately |
| `Uninstall.bat` | Remove the scheduled task |
| `Open-Dashboard.bat` | Start the web dashboard |
| `HFMonitor.ps1` | Monitor source code (compiled to EXE) |
| `HFDashboard.ps1` | Dashboard web server |
| `Build-EXE.ps1` | Build automation script |
| `Install-HFMonitor.ps1` | Installation automation script |
| `config.json` | Configuration file (edit before deployment) |

---

## Part 1: Single Workstation Deployment

This section covers deploying HFMonitor to a single workstation. Master this process before attempting mass deployment.

### Prerequisites

Before starting, ensure the following:

| Requirement | Details |
|-------------|---------|
| Operating System | Windows 11 Professional (Windows 10 also supported) |
| User Rights | Administrator access required for installation |
| PowerShell | Version 5.1 or higher (included in Windows 10/11) |
| Network | Internet access required for first-time build (to download ps2exe module) |
| Disk Space | Less than 5 MB required |

### Step 1: Copy the Package

1. Copy the entire HFMonitor folder to the target workstation
2. Recommended location: `C:\Temp\HFMonitor-Install\` or a USB drive

**Tip:** You can also copy from a network share:
```
\\fileserver\IT\Deployments\HFMonitor\
```

### Step 2: Configure the Monitor (IMPORTANT - Do This First)

Before building or installing, edit `config.json` to match your environment.

1. Open `config.json` in Notepad or any text editor
2. Modify the settings as needed:

```json
{
    "IntervalSeconds": 60,
    "OutputPath": "C:\\ProgramData\\HFMonitor",
    "SharedPath": "\\\\yourserver\\HFMonitor\\metrics",
    "LatencyTargets": ["8.8.8.8", "pacs.healthfirst.local"],
    "DicomHosts": ["pacs1.healthfirst.local", "pacs2.healthfirst.local"],
    "DicomPort": 104,
    "RetentionHours": 72,
    "RunOnce": false
}
```

**Configuration Settings Explained:**

| Setting | Default | What It Does |
|---------|---------|--------------|
| `IntervalSeconds` | 60 | How often metrics are collected (in seconds) |
| `OutputPath` | `C:\ProgramData\HFMonitor` | Local storage for metrics |
| `SharedPath` | "" (empty) | Network share for centralized viewing |
| `LatencyTargets` | `["8.8.8.8", "1.1.1.1"]` | IP addresses or hostnames to ping |
| `DicomHosts` | `[]` (empty) | PACS/DICOM servers to check connectivity |
| `DicomPort` | 104 | DICOM port to test (standard is 104) |
| `RetentionHours` | 72 | How many hours of history to keep locally |
| `RunOnce` | false | Set to true for testing; false for continuous monitoring |

**Important Notes:**
- Use double backslashes (`\\`) for paths in JSON
- The `SharedPath` is critical for centralized monitoring (covered in Part 2)
- Leave `DicomHosts` empty if you do not need PACS connectivity monitoring

### Step 3: Test the Monitor (Recommended)

Before full installation, run a single test to verify everything works:

1. **Double-click** `0-Test-Once.bat`
2. A command window will open showing the test progress
3. You should see output similar to:

```
=== Health First Workstation Monitor ===
Hostname:    RADIOLOGY-WS01
CPU:         23.5%
Memory:      67.2%
Network:     0.3%

Data saved to: C:\ProgramData\HFMonitor
```

4. Press any key to close the window

**If the test succeeds:** Proceed to Step 4.

**If the test fails:** See the [Troubleshooting Guide](#appendix-b-troubleshooting-guide) below.

### Step 4: Build the Executable

The monitor runs as a compiled executable (EXE) for reliability and to avoid PowerShell execution policy issues.

1. **Double-click** `1-Build-EXE.bat`
2. Wait for the build process to complete (30-60 seconds on first run)

**What Happens:**
- First time: Downloads and installs the `ps2exe` PowerShell module (requires internet)
- Compiles `HFMonitor.ps1` into `HFMonitor.exe`
- The EXE runs silently without a console window

**Expected Output:**
```
============================================
 HFMonitor EXE Builder
============================================

[1/3] Checking for ps2exe module...
      Installing ps2exe from PowerShell Gallery...
      ps2exe installed successfully
[2/3] Loading ps2exe...
      Module loaded
[3/3] Compiling HFMonitor.exe...
      Compilation successful!

============================================
 Build Complete!
============================================

Output file: C:\Temp\HFMonitor-Install\HFMonitor.exe
Size:        125.3 KB
```

3. Press any key to close the window

### Step 5: Install and Start the Monitor

1. **Double-click** `2-Install-and-Start.bat`
2. If prompted by User Account Control (UAC), click **Yes**

**What Happens:**
- Creates the folder `C:\ProgramData\HFMonitor\`
- Copies `HFMonitor.exe` and `config.json` to that folder
- Creates a Windows Scheduled Task named "HFWorkstationMonitor"
- Starts the monitor immediately

**Expected Output:**
```
============================================
 HFMonitor Installer
============================================

[1/4] Creating installation directory...
      C:\ProgramData\HFMonitor
[2/4] Copying files...
      Files copied
[3/4] Creating scheduled task...
      Scheduled task created
[4/4] Creating shortcuts...
      Shortcuts created

============================================
 Installation Complete!
============================================

Install location: C:\ProgramData\HFMonitor

The monitor will:
  - Start automatically when you log in
  - Run silently in the background
  - Save metrics to C:\ProgramData\HFMonitor

Starting monitor now...
  Monitor is running (PID: 12345)
```

### Step 6: Verify the Monitor is Running

**Method 1: Check the Process**

Open PowerShell and run:
```powershell
Get-Process -Name "HFMonitor"
```

Expected output:
```
Handles  NPM(K)    PM(K)      WS(K)     CPU(s)     Id  SI ProcessName
-------  ------    -----      -----     ------     --  -- -----------
    234      15    45678      56789       0.50   12345   1 HFMonitor
```

**Method 2: Check the Scheduled Task**

Open PowerShell and run:
```powershell
Get-ScheduledTask -TaskName "HFWorkstationMonitor" | Select-Object TaskName, State
```

Expected output:
```
TaskName               State
--------               -----
HFWorkstationMonitor   Running
```

**Method 3: Check the Output Files**

Navigate to `C:\ProgramData\HFMonitor\` and verify these files exist:
- `metrics.json` - Current metrics snapshot
- `history.json` - Rolling 72-hour history
- `monitor.log` - Log file for troubleshooting

### Step 7: Access the Local Dashboard

To view metrics in a web browser:

1. **Double-click** `Open-Dashboard.bat` (from the install package folder)

   OR run from PowerShell:
   ```powershell
   cd C:\ProgramData\HFMonitor
   powershell -File HFDashboard.ps1
   ```

2. Your default browser will open to `http://localhost:8080`
3. The dashboard shows real-time metrics for this workstation

**Dashboard Features:**
- Live CPU, Memory, and Network gauges
- Top resource-consuming processes
- Network latency measurements
- Auto-refreshes every 30 seconds

**Note:** The dashboard server must be running to view the page. The command window must stay open.

---

## Part 2: Centralized Dashboard Setup

This section explains how to configure a central dashboard that displays metrics from all 40 workstations.

### Architecture

```
All Workstations write to:  \\server\HFMonitor\metrics\HOSTNAME.json
Dashboard reads from:       \\server\HFMonitor\metrics\*.json
```

### Step 1: Create the Network Share

On your file server:

1. Create a folder for metrics storage:
   ```
   D:\HFMonitor\metrics\
   ```

2. Share this folder with appropriate permissions:
   - **Share Name:** `HFMonitor`
   - **Share Path:** `\\yourserver\HFMonitor`

3. Set NTFS permissions on `D:\HFMonitor\metrics\`:

| Group/User | Permission |
|------------|------------|
| Domain Computers | Modify (allows workstations to write their metrics) |
| IT Admins | Full Control |
| Domain Users | Read (allows viewing from dashboard) |

**PowerShell Commands to Create Share:**

```powershell
# Run on the file server as Administrator

# Create the folder
New-Item -Path "D:\HFMonitor\metrics" -ItemType Directory -Force

# Create the SMB share
New-SmbShare -Name "HFMonitor" -Path "D:\HFMonitor" -FullAccess "IT Admins" -ChangeAccess "Domain Computers" -ReadAccess "Domain Users"

# Verify the share
Get-SmbShare -Name "HFMonitor"
```

### Step 2: Configure Workstations to Write to SharedPath

Update the `config.json` on each workstation to include the network share path.

**Before:**
```json
{
    "SharedPath": "",
    ...
}
```

**After:**
```json
{
    "SharedPath": "\\\\yourserver\\HFMonitor\\metrics",
    ...
}
```

**Important:** Replace `yourserver` with your actual file server name.

**What Happens When SharedPath is Set:**

1. Each workstation writes its metrics locally to `C:\ProgramData\HFMonitor\metrics.json`
2. It ALSO writes a copy to `\\yourserver\HFMonitor\metrics\HOSTNAME.json`
3. The central dashboard reads all `*.json` files from the share

### Step 3: Set Up the Central Dashboard Server

Choose a server or workstation to run the dashboard. This could be:
- A dedicated monitoring server
- An IT admin workstation
- One of the radiologist workstations

**Option A: Run Dashboard Manually**

1. Copy `HFDashboard.ps1` to the dashboard server
2. Open PowerShell and run:

```powershell
.\HFDashboard.ps1 -SharedPath "\\yourserver\HFMonitor\metrics"
```

3. Open a browser to `http://localhost:8080`

**Option B: Run Dashboard as a Scheduled Task (Recommended for Production)**

Create a scheduled task to start the dashboard automatically:

```powershell
# Run as Administrator

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\HFDashboard\HFDashboard.ps1 -SharedPath '\\yourserver\HFMonitor\metrics'"

$Trigger = New-ScheduledTaskTrigger -AtStartup

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName "HFMonitorDashboard" `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -User "SYSTEM" `
    -RunLevel Highest
```

### Step 4: Access the Centralized Dashboard

Once the dashboard is running with the SharedPath configured:

1. Open a browser on any computer
2. Navigate to: `http://dashboard-server:8080`

   Replace `dashboard-server` with the actual hostname or IP address.

**Dashboard Capabilities:**
- View all workstations in a single interface
- See alerts for high CPU, memory, or latency
- Export data to CSV
- Auto-refresh every 30 seconds

### Network and Firewall Considerations

#### Required Network Access

| Source | Destination | Port | Protocol | Purpose |
|--------|-------------|------|----------|---------|
| Workstations | File Server | 445 | TCP | SMB file share (metrics upload) |
| Dashboard Server | File Server | 445 | TCP | SMB file share (metrics read) |
| Admin Browsers | Dashboard Server | 8080 | TCP | HTTP dashboard access |
| Workstations | Ping Targets | - | ICMP | Latency monitoring |
| Workstations | PACS Servers | 104 | TCP | DICOM connectivity check |

#### Windows Firewall Rules

**On the Dashboard Server:**

Allow inbound connections on port 8080:

```powershell
# Run as Administrator
New-NetFirewallRule `
    -DisplayName "HFMonitor Dashboard" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 8080 `
    -Action Allow
```

**On Workstations:**

No inbound firewall rules needed. Only outbound SMB (port 445) to the file server is required, which is typically allowed by default on domain-joined machines.

#### Testing Network Connectivity

From a workstation, test the share path:

```powershell
# Test share access
Test-Path "\\yourserver\HFMonitor\metrics"

# Test write access
"test" | Out-File "\\yourserver\HFMonitor\metrics\test.txt"
Remove-Item "\\yourserver\HFMonitor\metrics\test.txt"
```

From the dashboard server, test reading metrics:

```powershell
# List all workstation metrics files
Get-ChildItem "\\yourserver\HFMonitor\metrics\*.json"
```

---

## Part 3: Mass Deployment Options

This section covers deploying HFMonitor to all 40 workstations efficiently.

### Option 1: Manual Deployment with Pre-Built Package

Best for: Small deployments or environments without SCCM/GPO infrastructure.

**Preparation Steps:**

1. Build the EXE on one workstation using `1-Build-EXE.bat`
2. Edit `config.json` with production settings (SharedPath, PACS servers, etc.)
3. Create a deployment package folder containing:
   - `HFMonitor.exe` (the compiled executable)
   - `config.json` (with production settings)
   - `Install-HFMonitor.ps1`
   - `2-Install-and-Start.bat`

4. Copy this package to a network share:
   ```
   \\fileserver\IT\Deployments\HFMonitor\
   ```

**Deployment to Each Workstation:**

1. Log into the workstation as an administrator
2. Navigate to `\\fileserver\IT\Deployments\HFMonitor\`
3. Double-click `2-Install-and-Start.bat`
4. Verify the monitor is running

### Option 2: Group Policy Software Deployment

Best for: Domain environments where you want automatic deployment.

**Step 1: Create the Installation Script**

Create a silent installation script (`Install-Silent.ps1`):

```powershell
# Install-Silent.ps1 - Silent installation for GPO deployment
# Place this alongside HFMonitor.exe and config.json

$ErrorActionPreference = 'SilentlyContinue'

$SourceDir = $PSScriptRoot
$InstallPath = "$env:ProgramData\HFMonitor"
$TaskName = "HFWorkstationMonitor"

# Create install directory
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

# Copy files
Copy-Item -Path "$SourceDir\HFMonitor.exe" -Destination $InstallPath -Force
Copy-Item -Path "$SourceDir\config.json" -Destination $InstallPath -Force

# Remove existing task
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Stop any running instance
Get-Process -Name "HFMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force

# Create scheduled task
$Action = New-ScheduledTaskAction -Execute "$InstallPath\HFMonitor.exe" -WorkingDirectory $InstallPath
$Trigger = New-ScheduledTaskTrigger -AtLogon
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Health First Workstation Monitor" | Out-Null

# Start immediately
Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

exit 0
```

**Step 2: Create the GPO**

1. Open Group Policy Management Console (GPMC)
2. Create a new GPO: "HFMonitor Deployment"
3. Navigate to: Computer Configuration > Preferences > Windows Settings > Files
4. Add file copy operations:
   - Source: `\\fileserver\IT\Deployments\HFMonitor\HFMonitor.exe`
   - Destination: `C:\ProgramData\HFMonitor\HFMonitor.exe`

   - Source: `\\fileserver\IT\Deployments\HFMonitor\config.json`
   - Destination: `C:\ProgramData\HFMonitor\config.json`

5. Navigate to: Computer Configuration > Preferences > Control Panel Settings > Scheduled Tasks
6. Create a new Scheduled Task (Windows 7 and above)
7. Configure the task as described in the installation script

**Step 3: Link and Apply**

1. Link the GPO to the OU containing radiologist workstations
2. Wait for Group Policy to refresh, or force refresh:
   ```cmd
   gpupdate /force
   ```

### Option 3: SCCM/MECM Deployment

Best for: Enterprise environments with Microsoft Endpoint Configuration Manager.

**Create the Application in SCCM:**

1. **Application Name:** HFMonitor
2. **Deployment Type:** Script Installer
3. **Content Location:** `\\fileserver\IT\Deployments\HFMonitor\`
4. **Installation Program:**
   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-Silent.ps1
   ```
5. **Uninstall Program:**
   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Unregister-ScheduledTask -TaskName 'HFWorkstationMonitor' -Confirm:$false; Get-Process -Name 'HFMonitor' -ErrorAction SilentlyContinue | Stop-Process -Force"
   ```
6. **Detection Method:** File exists: `C:\ProgramData\HFMonitor\HFMonitor.exe`

**Deploy to Collection:**

1. Create a device collection for radiologist workstations
2. Deploy the application to that collection
3. Set deployment purpose: Required
4. Set schedule as appropriate for your environment

### Option 4: PowerShell Remoting Deployment

Best for: Immediate deployment to multiple machines via command line.

**Deployment Script:**

```powershell
# Deploy-HFMonitor.ps1 - Deploy to multiple workstations via PowerShell remoting

$Computers = @(
    "RADIOLOGY-WS01",
    "RADIOLOGY-WS02",
    "RADIOLOGY-WS03"
    # Add all workstation names here
)

# Or read from a file:
# $Computers = Get-Content "C:\workstations.txt"

$SourcePath = "\\fileserver\IT\Deployments\HFMonitor"

$ScriptBlock = {
    param($Source)

    $InstallPath = "$env:ProgramData\HFMonitor"
    $TaskName = "HFWorkstationMonitor"

    # Create directory
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

    # Copy files
    Copy-Item -Path "$Source\HFMonitor.exe" -Destination $InstallPath -Force
    Copy-Item -Path "$Source\config.json" -Destination $InstallPath -Force

    # Stop existing
    Get-Process -Name "HFMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    # Create task
    $Action = New-ScheduledTaskAction -Execute "$InstallPath\HFMonitor.exe" -WorkingDirectory $InstallPath
    $Trigger = New-ScheduledTaskTrigger -AtLogon
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null

    # Start
    Start-ScheduledTask -TaskName $TaskName

    return "Installed on $env:COMPUTERNAME"
}

# Deploy to all computers
$Results = Invoke-Command -ComputerName $Computers -ScriptBlock $ScriptBlock -ArgumentList $SourcePath

# Display results
$Results | Format-Table
```

### Configuration Management Across Stations

When you need to update configuration across all workstations:

**Method 1: Update config.json on the Share**

If workstations pull config from a central location, update the master config.

**Method 2: PowerShell Remoting Update**

```powershell
$Computers = Get-Content "C:\workstations.txt"
$NewConfig = Get-Content "\\fileserver\IT\Deployments\HFMonitor\config.json" -Raw

Invoke-Command -ComputerName $Computers -ScriptBlock {
    param($Config)
    $Config | Set-Content "C:\ProgramData\HFMonitor\config.json" -Force

    # Restart the monitor to apply new config
    Get-Process -Name "HFMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-ScheduledTask -TaskName "HFWorkstationMonitor"
} -ArgumentList $NewConfig
```

**Method 3: GPO File Replacement**

Update the file in the GPO deployment, and machines will receive the new config at next Group Policy refresh.

---

## Appendix A: Configuration Reference

### Complete config.json Example

```json
{
    "IntervalSeconds": 60,
    "OutputPath": "C:\\ProgramData\\HFMonitor",
    "SharedPath": "\\\\fileserver\\HFMonitor\\metrics",
    "LatencyTargets": [
        "8.8.8.8",
        "1.1.1.1",
        "pacs.healthfirst.local",
        "dcm-archive.healthfirst.local"
    ],
    "DicomHosts": [
        "pacs1.healthfirst.local",
        "pacs2.healthfirst.local"
    ],
    "DicomPort": 104,
    "RetentionHours": 72,
    "RunOnce": false
}
```

### Configuration Parameter Details

#### IntervalSeconds

- **Type:** Integer
- **Default:** 60
- **Recommended Range:** 30-300
- **Description:** How frequently metrics are collected. Lower values provide more granular data but use more disk space and CPU.

#### OutputPath

- **Type:** String (file path)
- **Default:** `C:\ProgramData\HFMonitor`
- **Description:** Local directory where metrics are stored. This location is used regardless of SharedPath setting.

#### SharedPath

- **Type:** String (UNC path)
- **Default:** "" (empty - disabled)
- **Description:** Network share where each workstation writes its metrics. Enable this for centralized monitoring.

#### LatencyTargets

- **Type:** Array of strings
- **Default:** `["8.8.8.8", "1.1.1.1"]`
- **Description:** IP addresses or hostnames to ping for latency measurement. Include your PACS servers to monitor image retrieval performance.

#### DicomHosts

- **Type:** Array of strings
- **Default:** `[]` (empty)
- **Description:** PACS/DICOM servers to test TCP connectivity. The monitor checks if the DICOM port is reachable.

#### DicomPort

- **Type:** Integer
- **Default:** 104
- **Description:** TCP port for DICOM connectivity testing. Standard DICOM port is 104.

#### RetentionHours

- **Type:** Integer
- **Default:** 72
- **Description:** How many hours of historical data to keep in `history.json`. 72 hours = 3 days of data.

#### RunOnce

- **Type:** Boolean
- **Default:** false
- **Description:** If true, collect metrics once and exit. If false, run continuously. Use true for testing only.

---

## Appendix B: Troubleshooting Guide

### Issue: Monitor Not Starting

**Symptoms:** HFMonitor.exe process not running after installation.

**Solutions:**

1. **Check the scheduled task:**
   ```powershell
   Get-ScheduledTask -TaskName "HFWorkstationMonitor" | Select-Object TaskName, State, LastRunTime, LastTaskResult
   ```

2. **Check the log file:**
   ```powershell
   Get-Content "C:\ProgramData\HFMonitor\monitor.log" -Tail 20
   ```

3. **Try starting manually:**
   ```powershell
   Start-ScheduledTask -TaskName "HFWorkstationMonitor"
   ```

4. **Run the EXE directly for testing:**
   ```powershell
   & "C:\ProgramData\HFMonitor\HFMonitor.exe"
   ```

### Issue: "ps2exe Not Found" During Build

**Symptoms:** Build fails with module not found error.

**Solution:**

Run this command in PowerShell (requires internet):
```powershell
Install-Module -Name ps2exe -Scope CurrentUser -Force
```

Then retry the build.

### Issue: Metrics Not Appearing on Central Dashboard

**Symptoms:** Workstation shows locally but not on centralized dashboard.

**Solutions:**

1. **Verify SharedPath in config.json:**
   ```powershell
   Get-Content "C:\ProgramData\HFMonitor\config.json" | ConvertFrom-Json | Select-Object SharedPath
   ```

2. **Test write access to the share:**
   ```powershell
   "test" | Out-File "\\yourserver\HFMonitor\metrics\test.txt"
   dir "\\yourserver\HFMonitor\metrics\"
   ```

3. **Check if the metrics file exists on the share:**
   ```powershell
   Test-Path "\\yourserver\HFMonitor\metrics\$env:COMPUTERNAME.json"
   ```

4. **Check the monitor log for share write errors:**
   ```powershell
   Select-String -Path "C:\ProgramData\HFMonitor\monitor.log" -Pattern "shared|error" -AllMatches
   ```

### Issue: High Latency Reported

**Symptoms:** Dashboard shows high latency or packet loss to targets.

**Solutions:**

1. **Verify the targets are correct** - Ensure `LatencyTargets` contains valid, reachable addresses

2. **Test manually:**
   ```powershell
   Test-Connection -ComputerName "pacs.healthfirst.local" -Count 4
   ```

3. **Check network path** - This may indicate actual network issues that need investigation

### Issue: Dashboard Shows "No Workstation Data Available"

**Symptoms:** Dashboard page loads but no workstations appear.

**Solutions:**

1. **Verify metrics.json exists:**
   ```powershell
   Test-Path "C:\ProgramData\HFMonitor\metrics.json"
   Get-Content "C:\ProgramData\HFMonitor\metrics.json"
   ```

2. **Verify the monitor is running:**
   ```powershell
   Get-Process -Name "HFMonitor"
   ```

3. **If using SharedPath, verify files on share:**
   ```powershell
   Get-ChildItem "\\yourserver\HFMonitor\metrics\*.json"
   ```

### Issue: Dashboard Port 8080 Already in Use

**Symptoms:** Dashboard fails to start with port binding error.

**Solution:**

Use a different port:
```powershell
.\HFDashboard.ps1 -Port 9090
```

Then access at `http://localhost:9090`

### Issue: Cannot Uninstall

**Symptoms:** Uninstall fails or monitor keeps running.

**Manual Cleanup:**

```powershell
# Stop the process
Get-Process -Name "HFMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force

# Remove the scheduled task
Unregister-ScheduledTask -TaskName "HFWorkstationMonitor" -Confirm:$false

# Optional: Remove data (preserves for debugging)
# Remove-Item -Path "C:\ProgramData\HFMonitor" -Recurse -Force
```

---

## Appendix C: Quick Reference Commands

### Checking Monitor Status

```powershell
# Is the process running?
Get-Process -Name "HFMonitor"

# What is the scheduled task status?
Get-ScheduledTask -TaskName "HFWorkstationMonitor" | Select-Object State

# View recent metrics
Get-Content "C:\ProgramData\HFMonitor\metrics.json" | ConvertFrom-Json

# View log entries
Get-Content "C:\ProgramData\HFMonitor\monitor.log" -Tail 20
```

### Managing the Monitor

```powershell
# Stop the monitor
Get-Process -Name "HFMonitor" | Stop-Process

# Start the monitor
Start-ScheduledTask -TaskName "HFWorkstationMonitor"

# Restart the monitor
Get-Process -Name "HFMonitor" | Stop-Process -Force
Start-ScheduledTask -TaskName "HFWorkstationMonitor"
```

### Dashboard Commands

```powershell
# Start dashboard with default settings
.\HFDashboard.ps1

# Start dashboard with custom port
.\HFDashboard.ps1 -Port 9090

# Start dashboard with shared path for multi-workstation view
.\HFDashboard.ps1 -SharedPath "\\server\HFMonitor\metrics"

# Start dashboard with all options
.\HFDashboard.ps1 -Port 8080 -DataPath "C:\ProgramData\HFMonitor" -SharedPath "\\server\HFMonitor\metrics"
```

### Bulk Operations via PowerShell Remoting

```powershell
# Check status on multiple machines
$Computers = Get-Content "C:\workstations.txt"
Invoke-Command -ComputerName $Computers -ScriptBlock {
    $proc = Get-Process -Name "HFMonitor" -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Computer = $env:COMPUTERNAME
        Running = ($null -ne $proc)
        PID = $proc.Id
    }
} | Format-Table

# Restart monitor on all machines
Invoke-Command -ComputerName $Computers -ScriptBlock {
    Get-Process -Name "HFMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-ScheduledTask -TaskName "HFWorkstationMonitor"
}

# Get latest metrics from all machines
Invoke-Command -ComputerName $Computers -ScriptBlock {
    $m = Get-Content "C:\ProgramData\HFMonitor\metrics.json" | ConvertFrom-Json
    [PSCustomObject]@{
        Computer = $env:COMPUTERNAME
        CPU = $m.CPU.OverallPercent
        Memory = $m.Memory.PercentUsed
        LastUpdate = $m.Timestamp
    }
} | Format-Table
```

---

## Support and Contacts

For assistance with HFMonitor deployment:

- **Internal IT:** Contact the EAD Team
- **Documentation Issues:** Submit updates to the repository

---

*This document is maintained by the Health First Enterprise Architecture & Design Team.*
