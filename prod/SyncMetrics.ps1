# SyncMetrics - Lightweight metrics sync to network share
# Runs as logged-in user (AtLogon) to access network shares
# The main monitor runs as SYSTEM and writes locally only

# Detect script/exe directory
$ScriptDir = $null
try {
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($exePath -and (Test-Path $exePath)) {
        $ScriptDir = [System.IO.Path]::GetDirectoryName($exePath)
    }
} catch { }

if (-not $ScriptDir -or $ScriptDir -like "*powershell*" -or $ScriptDir -like "*System32*") {
    if ($PSScriptRoot) { $ScriptDir = $PSScriptRoot }
}
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# Load config
$ConfigFile = Join-Path $ScriptDir "config.json"
if (-not (Test-Path $ConfigFile)) {
    $ConfigFile = "$env:ProgramData\WorkstationMonitor\config.json"
}

$Config = @{
    IntervalSeconds = 60
    OutputPath = "$env:ProgramData\WorkstationMonitor"
    SharedPath = ""
}

if (Test-Path $ConfigFile) {
    try {
        $FileConfig = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        foreach ($key in $FileConfig.PSObject.Properties.Name) {
            $Config[$key] = $FileConfig.$key
        }
    } catch { }
}

# Validate IntervalSeconds
if ($Config.IntervalSeconds -lt 10) {
    $Config.IntervalSeconds = 60
}

# Exit if SharedPath not configured
if (-not $Config.SharedPath) {
    exit 0
}

# Single instance protection via named mutex
$Script:Mutex = New-Object System.Threading.Mutex($false, "Global\WorkstationMonitorSync")
$Script:MutexAcquired = $false
try {
    $Script:MutexAcquired = $Script:Mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $Script:MutexAcquired = $true
}
if (-not $Script:MutexAcquired) {
    $Script:Mutex.Dispose()
    exit 0
}

# Simple logging
function Write-SyncLog {
    param([string]$Message, [string]$Level = "INFO")
    $logFile = Join-Path $Config.OutputPath "sync.log"
    try {
        $logLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
        Add-Content -Path $logFile -Value $logLine -ErrorAction SilentlyContinue
        # Keep log small
        if ((Get-Item $logFile -ErrorAction SilentlyContinue).Length -gt 512KB) {
            $content = Get-Content $logFile -Tail 500
            $content | Set-Content $logFile
        }
    } catch { }
}

Write-SyncLog "SyncMetrics starting - SharedPath: $($Config.SharedPath)"

# Sync loop
try {
    while ($true) {
        try {
            $localFile = Join-Path $Config.OutputPath "metrics.json"
            if ((Test-Path $localFile) -and (Test-Path $Config.SharedPath)) {
                $sharedFile = Join-Path $Config.SharedPath "$($env:COMPUTERNAME).json"
                Copy-Item -Path $localFile -Destination $sharedFile -Force
            } elseif (-not (Test-Path $Config.SharedPath)) {
                Write-SyncLog "SharedPath not accessible: $($Config.SharedPath)" "WARN"
            }
        } catch {
            Write-SyncLog "Sync failed: $_" "ERROR"
        }

        Start-Sleep -Seconds $Config.IntervalSeconds
    }
} finally {
    if ($Script:MutexAcquired) { $Script:Mutex.ReleaseMutex() }
    $Script:Mutex.Dispose()
}
