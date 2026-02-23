# Persistent Monitor (SYSTEM Scheduled Task) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the workstation monitor run continuously as SYSTEM at startup, surviving reboots and user session changes (admin -> rad -> admin).

**Architecture:** Change the Windows Scheduled Task from `AtLogon` (user session) to `AtStartup` with `NT AUTHORITY\SYSTEM` principal. Update both the generic (`prod/`) and HF-specific (`hfmonitorDeployment/`) installers and monitor scripts identically.

**Tech Stack:** PowerShell 5.1, Windows Task Scheduler, ps2exe

**Design doc:** `docs/plans/2026-02-23-persistent-system-service-design.md`

---

### Task 1: Update prod/Install-Monitor.ps1 — Scheduled Task to SYSTEM at Startup

**Files:**
- Modify: `prod/Install-Monitor.ps1:7,10,118-119,131-135,137,190,218`

**Step 1: Update synopsis comment (line 7)**

Change:
```
    - Starts WorkstationMonitor.exe at user logon
```
To:
```
    - Starts WorkstationMonitor.exe at system startup (runs as SYSTEM)
```

**Step 2: Update description comment (line 10)**

Change:
```
    - Runs as the current user (no admin needed for basic install)
```
To:
```
    - Runs as NT AUTHORITY\SYSTEM (persists across user sessions)
```

**Step 3: Update trigger and add principal (lines 118-119, 131-135)**

Replace lines 118-135:
```powershell
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
```

**Step 4: Update success message (line 137)**

Change:
```powershell
    Write-Host "      Scheduled task created (runs at user logon)" -ForegroundColor Green
```
To:
```powershell
    Write-Host "      Scheduled task created (runs at system startup as SYSTEM)" -ForegroundColor Green
```

**Step 5: Update summary messages (line 190)**

Change:
```powershell
Write-Host "  - Start automatically when any user logs in" -ForegroundColor White
```
To:
```powershell
Write-Host "  - Start automatically at system boot (runs as SYSTEM)" -ForegroundColor White
Write-Host "  - Persist across all user sessions (admin, rad, etc.)" -ForegroundColor White
```

**Step 6: Update "start now" fallback message (line 218)**

Change:
```powershell
    Write-Host "Or just log out and back in." -ForegroundColor Gray
```
To:
```powershell
    Write-Host "Or restart the computer." -ForegroundColor Gray
```

**Step 7: Commit**

```bash
git add prod/Install-Monitor.ps1
git commit -m "feat: run WorkstationMonitor as SYSTEM at startup

Changes scheduled task from AtLogon to AtStartup with
NT AUTHORITY\SYSTEM principal. Monitor now persists across
user sessions and survives reboots without requiring login."
```

---

### Task 2: Update hfmonitorDeployment/Install-HFMonitor.ps1 — Same Changes

**Files:**
- Modify: `hfmonitorDeployment/Install-HFMonitor.ps1:7,10,118-119,131-135,137,190,218`

Apply the exact same changes as Task 1, but for the HF installer. The line numbers and structure are identical. The only differences are the task/exe names (HFMonitor vs WorkstationMonitor) which are already correct in the file and should not change.

**Step 1-6:** Apply same edits as Task 1 steps 1-6.

**Step 7: Commit**

```bash
git add hfmonitorDeployment/Install-HFMonitor.ps1
git commit -m "feat: run HFMonitor as SYSTEM at startup

Same SYSTEM/AtStartup changes as prod installer."
```

---

### Task 3: Improve SharedPath Handling in prod/WorkstationMonitor.ps1

**Files:**
- Modify: `prod/WorkstationMonitor.ps1:499-506`

When running as SYSTEM, network share access uses the machine's computer account (DOMAIN\COMPUTERNAME$). The share write may fail if the share ACL doesn't include the machine account. Add clearer logging so admins know why the share write failed.

**Step 1: Replace SharedPath write block (lines 499-506)**

Replace:
```powershell
    if ($Script:Config.SharedPath -and (Test-Path $Script:Config.SharedPath)) {
        try {
            $sharedFile = Join-Path $Script:Config.SharedPath "$($env:COMPUTERNAME).json"
            $Metrics | ConvertTo-Json -Depth 10 | Set-Content $sharedFile -Force
        } catch {
            Write-Log "Failed to save to shared path: $_" "WARN"
        }
    }
```

With:
```powershell
    if ($Script:Config.SharedPath) {
        try {
            if (-not (Test-Path $Script:Config.SharedPath)) {
                Write-Log "SharedPath not accessible: $($Script:Config.SharedPath) - check share permissions for computer account ($env:COMPUTERNAME`$)" "WARN"
            } else {
                $sharedFile = Join-Path $Script:Config.SharedPath "$($env:COMPUTERNAME).json"
                $Metrics | ConvertTo-Json -Depth 10 | Set-Content $sharedFile -Force
            }
        } catch {
            Write-Log "Failed to save to shared path: $_ - if running as SYSTEM, ensure share grants write to computer account ($env:COMPUTERNAME`$)" "WARN"
        }
    }
```

**Step 2: Commit**

```bash
git add prod/WorkstationMonitor.ps1
git commit -m "fix: improve SharedPath error logging for SYSTEM context

When running as SYSTEM, network share access uses the machine
account. Log actionable messages about share permissions."
```

---

### Task 4: Same SharedPath Fix in hfmonitorDeployment/HFMonitor.ps1

**Files:**
- Modify: `hfmonitorDeployment/HFMonitor.ps1:499-506`

**Step 1:** Apply the exact same SharedPath replacement from Task 3.

**Step 2: Commit**

```bash
git add hfmonitorDeployment/HFMonitor.ps1
git commit -m "fix: improve SharedPath error logging for SYSTEM context (HF)

Same SharedPath logging improvement as prod monitor."
```

---

### Task 5: Push to Feature Branch and Create PR

**Step 1: Create feature branch and push**

```bash
git checkout -b feature/system-service-persistence
git push -u origin feature/system-service-persistence
```

**Step 2: Create PR**

Title: `feat: run monitor as SYSTEM at startup for persistent monitoring`

Body should summarize:
- Problem: monitor dies on logoff/restart, rads have no permissions
- Solution: SYSTEM principal + AtStartup trigger
- Files changed: both installers + both monitor scripts
- Note about network share: admins need to ensure share ACL includes machine accounts

---

### Deployment Notes (for the admin)

After merging, on each workstation:
1. Rebuild the EXE: `1-Build-Monitor.bat`
2. Re-run the installer: `3-Install.bat` (this will replace the old scheduled task)
3. The monitor will start immediately via `-StartNow` and persist through all future reboots/user switches

For the network share: ensure the share ACL grants write access to `DOMAIN\Domain Computers` or individual `COMPUTERNAME$` accounts.
