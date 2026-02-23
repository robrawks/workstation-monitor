# Design: Persistent Monitor via SYSTEM Scheduled Task

## Problem

The workstation monitor dies when:
- The admin who installed it logs off
- A radiologist (restricted user) logs in — they have no permissions (can't even open Task Manager)
- The computer restarts and no admin logs in

Root cause: The scheduled task uses `AtLogon` trigger with no explicit principal, so it runs under a user session context that dies on logoff.

## Solution

Change the scheduled task to run as `NT AUTHORITY\SYSTEM` with an `AtStartup` trigger.

### Why This Works

- SYSTEM runs independently of any user session
- Starts at boot, before any user logs in
- Survives all user switches (admin -> rad -> admin)
- SYSTEM has full local filesystem access (C:\ProgramData already grants SYSTEM FullControl)
- The monitor code already detects the logged-in user via `Win32_ComputerSystem.UserName`, not `$env:USERNAME`

### Files to Modify

| File | Change |
|------|--------|
| `prod/Install-Monitor.ps1` | AtStartup trigger + SYSTEM principal |
| `hfmonitorDeployment/Install-HFMonitor.ps1` | Same |
| `prod/WorkstationMonitor.ps1` | Improve SharedPath error handling for SYSTEM context |
| `hfmonitorDeployment/HFMonitor.ps1` | Same |

### Installer Changes

```powershell
# Before
$Trigger = New-ScheduledTaskTrigger -AtLogon

Register-ScheduledTask -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings

# After
$Trigger = New-ScheduledTaskTrigger -AtStartup

$Principal = New-ScheduledTaskPrincipal `
    -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Principal $Principal
```

### Monitor Script Changes

- Add resilient SharedPath handling: try/catch around network share writes with retry logic
- Log clear message when SharedPath fails (likely a permissions issue for machine account)
- No changes to metric collection — all CIM/WMI/counter APIs work under SYSTEM

### Network Share Consideration

When running as SYSTEM, network share access uses the computer account (DOMAIN\COMPUTERNAME$). The network share ACL must grant write access to the machine accounts. If it doesn't, monitoring continues locally and logs a warning.

### No Changes Needed

- config.json — no new settings
- Dashboard.ps1 / HFDashboard.ps1 — no changes
- Build scripts — no changes
- Uninstall scripts — Unregister-ScheduledTask works regardless of principal
