# Workstation Monitor

A lightweight PowerShell-based monitoring solution for Windows workstations. Collects CPU, memory, network, and latency metrics with a web-based dashboard.

## Features

- **Low overhead** - Runs silently in the background as a scheduled task
- **No dependencies** - Compiles to standalone EXE using ps2exe
- **Centralized dashboard** - View all workstations from a single web interface
- **Network share sync** - Optionally sync metrics to a shared folder
- **Real-time alerts** - High CPU, memory, latency warnings
- **Process tracking** - Top CPU and memory consumers per workstation
- **User tracking** - See who's logged into each workstation

## Quick Start

### 1. Build the EXEs

```batch
cd deploy
1-Build-Monitor.bat      # Creates WorkstationMonitor.exe
2-Build-Dashboard.bat    # Creates Dashboard.exe
```

### 2. Configure (Optional)

Edit `deploy/config.json`:
```json
{
    "IntervalSeconds": 60,
    "OutputPath": "C:\\ProgramData\\WorkstationMonitor",
    "SharedPath": "\\\\server\\share\\metrics",
    "LatencyTargets": ["8.8.8.8", "1.1.1.1"],
    "RetentionHours": 72
}
```

### 3. Deploy to Workstations

Copy these files to each workstation:
- `3-Install.bat`
- `Install-Monitor.ps1`
- `WorkstationMonitor.exe`
- `config.json`

Run `3-Install.bat` (requires admin for scheduled task).

### 4. View Dashboard

Double-click `Dashboard.exe` and open `http://localhost:9090`

## Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| IntervalSeconds | 60 | Collection interval in seconds |
| OutputPath | C:\ProgramData\WorkstationMonitor | Local data storage |
| SharedPath | "" | Network share for centralized metrics |
| LatencyTargets | ["8.8.8.8"] | Hosts to ping for latency |
| DicomHosts | [] | DICOM/PACS hosts to check connectivity |
| DicomPort | 104 | DICOM port |
| RetentionHours | 72 | History retention |

## Dashboard Features

- Search by PC name or logged-in user
- Filter by High CPU, High Memory, High Latency
- Dismiss offline alerts
- Click workstation for detailed view with graphs
- Export to CSV

## File Structure

```
deploy/
├── WorkstationMonitor.ps1   # Monitor source
├── Dashboard.ps1            # Dashboard source
├── Install-Monitor.ps1      # Installation script
├── Build-Monitor.ps1        # Build monitor EXE
├── Build-Dashboard.ps1      # Build dashboard EXE
├── config.json              # Configuration template
├── 1-Build-Monitor.bat      # Build monitor
├── 2-Build-Dashboard.bat    # Build dashboard
├── 3-Install.bat            # Install on workstation
├── Uninstall.bat            # Remove from workstation
└── DEPLOYMENT-GUIDE.md      # Deployment instructions
```

## Managing the Monitor

### Check if Running
```powershell
Get-Process -Name "WorkstationMonitor"
```

### Stop the Monitor
```powershell
Get-Process -Name "WorkstationMonitor" | Stop-Process
```

### Start Manually
```powershell
Start-ScheduledTask -TaskName "WorkstationMonitor"
```

### View Task Status
```powershell
Get-ScheduledTask -TaskName "WorkstationMonitor" | Select-Object State
```

## Requirements

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1+
- ps2exe module (auto-installed during build)

## Troubleshooting

### "ps2exe not found" error
Run this in PowerShell first:
```powershell
Install-Module -Name ps2exe -Scope CurrentUser -Force
```

### EXE not starting
Check the log file: `C:\ProgramData\WorkstationMonitor\monitor.log`

### No data being collected
1. Make sure EXE is running: `Get-Process -Name "WorkstationMonitor"`
2. Check if `metrics.json` exists in output folder
3. Review `monitor.log` for errors

## License

MIT
