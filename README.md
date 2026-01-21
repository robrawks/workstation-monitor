# Workstation Monitor

A lightweight, internal monitoring solution for Windows workstations. Built with PowerShell, zero licensing costs, minimal resource usage.

## Why This Exists

Commercial monitoring tools charge **per device per month**. For 40+ workstations, that adds up fast. This tool provides the visibility we need for troubleshooting without the cost.

## Key Points

- **Internal only** - All data stays on your network. Metrics are written to a local folder and optionally synced to an internal file share. No external services, no cloud, no data leaves your environment.
- **Minimal footprint** - Single lightweight EXE (~50KB), runs in background, negligible CPU/memory impact. Won't interfere with clinical workflows.
- **Simple setup** - Copy 4 files, double-click install. No agents, no server infrastructure, no database.
- **Zero cost** - Pure PowerShell compiled to EXE. No licenses, no subscriptions.

## What It Collects

Basic performance metrics for troubleshooting:
- CPU and memory utilization
- Network latency to key systems
- Top resource-consuming processes
- Currently logged-in user

**No sensitive data** - No patient info, no credentials, no browsing history, no keystrokes.

## Quick Start

### 1. Build (one time)
```batch
cd deploy
1-Build-Monitor.bat      # Creates WorkstationMonitor.exe
2-Build-Dashboard.bat    # Creates Dashboard.exe
```

### 2. Deploy to Workstations

Copy to each workstation:
- `3-Install.bat`
- `Install-Monitor.ps1`
- `WorkstationMonitor.exe`
- `config.json`

Double-click `3-Install.bat` (requires admin).

### 3. View Dashboard

Double-click `Dashboard.exe` → opens `http://localhost:9090`

## Configuration

Edit `config.json` before deploying:

```json
{
    "IntervalSeconds": 60,
    "OutputPath": "C:\\ProgramData\\WorkstationMonitor",
    "SharedPath": "\\\\yourserver\\share\\metrics",
    "LatencyTargets": ["your-pacs-server", "8.8.8.8"],
    "RetentionHours": 72
}
```

## Dashboard Features

- Search by PC name or logged-in user
- Filter by high CPU, memory, or latency
- Click workstation for detailed graphs
- Export to CSV

## Requirements

- Windows 10/11 or Server 2016+
- PowerShell 5.1+ (built into Windows)
- Write access to a network share (for centralized view)

## License

MIT
