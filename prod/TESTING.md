# Build & Test Guide

## Overview

Each workstation runs a monitor (as SYSTEM) that writes `metrics.json` locally.
A hidden SMB share (`WsMonitor$`) exposes that file read-only.
The dashboard on the admin PC pulls `\\HOSTNAME\WsMonitor$\metrics.json` from each workstation.

## Part 1: Build

On your admin PC, from the `prod\` folder:

1. **Double-click `1-Build-Monitor.bat`**
   - Installs `ps2exe` module if needed (first time only, needs internet)
   - Compiles `WorkstationMonitor.ps1` into `WorkstationMonitor.exe`
   - You should see `[3/3] Compiling WorkstationMonitor.exe... Compilation successful!`
   - Verify: `WorkstationMonitor.exe` appears in the folder

2. **Double-click `2-Build-Dashboard.bat`**
   - Compiles `Dashboard.ps1` into `Dashboard.exe`
   - Verify: `Dashboard.exe` appears in the folder

## Part 2: Install on a Test Workstation

Copy the `prod\` folder to the target workstation, then:

1. **Double-click `3-Install.bat`** (auto-elevates to admin)
   - Creates `C:\ProgramData\WorkstationMonitor\`
   - Sets NTFS permissions (Admins, SYSTEM, current user, Authenticated Users read)
   - Creates hidden SMB share `WsMonitor$`
   - Copies `WorkstationMonitor.exe`
   - Creates scheduled task (runs at boot as SYSTEM)
   - Starts the monitor immediately

2. **Verify the install worked:**
   Open an admin PowerShell on the workstation and run:
   ```powershell
   # Share exists?
   Get-SmbShare -Name "WsMonitor$"

   # ACL has Authenticated Users?
   (Get-Acl "$env:ProgramData\WorkstationMonitor").Access |
       Where-Object IdentityReference -like "*Authenticated*"

   # Monitor is running?
   Get-Process WorkstationMonitor

   # Metrics file exists? (may take up to 60s after first start)
   Test-Path "$env:ProgramData\WorkstationMonitor\metrics.json"
   ```

3. **Verify remote access from your admin PC:**
   ```powershell
   # Replace WSRAD001 with the actual hostname
   Test-Path "\\WSRAD001\WsMonitor$\metrics.json"

   # Read the metrics
   Get-Content "\\WSRAD001\WsMonitor$\metrics.json" | ConvertFrom-Json
   ```
   If `Test-Path` returns `False`, check that port 445 is open between the two machines
   (it should be by default for domain-joined workstations).

## Part 3: Run the Dashboard

On your admin PC:

1. **Edit `workstations.txt`** in the `prod\` folder — uncomment and add your test workstation hostname(s):
   ```
   # Workstation hostnames - one per line
   WSRAD001
   ```

2. **Double-click `Open-Dashboard.bat`**
   - Starts the dashboard server on `http://localhost:9090`
   - Auto-opens your browser
   - You should see your test workstation's card with live CPU, memory, network, and latency data

3. **Verify pull-based collection:**
   - The workstation card should show as ONLINE with current metrics
   - Add another hostname to `workstations.txt` — it appears on next auto-refresh (30s) without restarting the dashboard
   - Add a hostname that doesn't exist — it should show nothing (not hang), since unreachable hosts timeout after 3 seconds

## Part 4: Test Uninstall

On the test workstation:

1. **Double-click `Uninstall.bat`** (or run `Install-Monitor.ps1 -Uninstall` from admin PowerShell)

2. **Verify cleanup:**
   ```powershell
   # Share removed?
   Get-SmbShare -Name "WsMonitor$"   # should error / return nothing

   # Task removed?
   Get-ScheduledTask -TaskName "WorkstationMonitor" -ErrorAction SilentlyContinue   # should be null

   # Data preserved?
   Test-Path "$env:ProgramData\WorkstationMonitor"   # True - data is kept
   ```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `Test-Path \\HOST\WsMonitor$\...` returns False | Is the share created? (`Get-SmbShare` on workstation). Is port 445 open? |
| Dashboard shows workstation as offline | Is `WorkstationMonitor.exe` running? Has it written `metrics.json` yet? (wait 60s) |
| Dashboard hangs on refresh | Shouldn't happen — 3 second timeout per host. Check if PowerShell jobs are piling up in Task Manager |
| Build step fails at ps2exe | Need internet on first run. Or install manually: `Install-Module ps2exe -Scope CurrentUser` |
