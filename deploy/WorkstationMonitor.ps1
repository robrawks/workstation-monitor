# Workstation Monitor - EXE Version
# Lightweight monitoring agent for radiologist workstations.
# Version: 1.1.0 (EXE Edition)

# =============================================================================
# Configuration - Load from file or use defaults
# =============================================================================

# Detect script/exe directory (works for both .ps1 and compiled .exe)
$ScriptDir = $null
try {
    # Method 1: Get EXE location (works when compiled)
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($exePath -and (Test-Path $exePath)) {
        $ScriptDir = [System.IO.Path]::GetDirectoryName($exePath)
    }
} catch { }

# Method 2: PSScriptRoot (works for .ps1)
if (-not $ScriptDir -or $ScriptDir -like "*powershell*" -or $ScriptDir -like "*System32*") {
    if ($PSScriptRoot) { 
        $ScriptDir = $PSScriptRoot 
    }
}

# Method 3: Current directory as fallback
if (-not $ScriptDir) {
    $ScriptDir = (Get-Location).Path
}

# Config file - check script dir first, then ProgramData
$ConfigFile = Join-Path $ScriptDir "config.json"
if (-not (Test-Path $ConfigFile)) {
    $ConfigFile = "$env:ProgramData\WorkstationMonitor\config.json"
}
$DefaultConfig = @{
    IntervalSeconds = 60
    OutputPath = "$env:ProgramData\WorkstationMonitor"
    SharedPath = ""
    LatencyTargets = @("8.8.8.8", "1.1.1.1")
    DicomHosts = @()
    DicomPort = 104
    RetentionHours = 72
    RunOnce = $false
}

# Load config from file if exists, otherwise use defaults
if (Test-Path $ConfigFile) {
    try {
        $FileConfig = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        foreach ($key in $FileConfig.PSObject.Properties.Name) {
            $DefaultConfig[$key] = $FileConfig.$key
        }
    } catch {
        Write-Warning "Could not read config file, using defaults: $_"
    }
}

$Script:Config = @{
    Version = "1.1.0"
    Hostname = $env:COMPUTERNAME
    OutputPath = $DefaultConfig.OutputPath
    SharedPath = $DefaultConfig.SharedPath
    MetricsFile = "metrics.json"
    HistoryFile = "history.json"
    MaxHistoryRecords = [int](($DefaultConfig.RetentionHours * 3600) / $DefaultConfig.IntervalSeconds)
    LatencyTargets = @($DefaultConfig.LatencyTargets)
    DicomHosts = @($DefaultConfig.DicomHosts)
    DicomPort = $DefaultConfig.DicomPort
    IntervalSeconds = $DefaultConfig.IntervalSeconds
    RunOnce = $DefaultConfig.RunOnce
}

# =============================================================================
# Logging Function (for background operation)
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    $logFile = Join-Path $Script:Config.OutputPath "monitor.log"
    try {
        Add-Content -Path $logFile -Value $logLine -ErrorAction SilentlyContinue
        
        # Keep log file under 1MB
        if ((Get-Item $logFile -ErrorAction SilentlyContinue).Length -gt 1MB) {
            $content = Get-Content $logFile -Tail 1000
            $content | Set-Content $logFile
        }
    } catch { }
}

# =============================================================================
# Metric Collection Functions
# =============================================================================

# Cache core count - doesn't change at runtime
$Script:CachedCoreCount = $null

function Get-CPUMetrics {
    try {
        $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
        $cpuPercent = if ($cpuCounter) {
            [math]::Round($cpuCounter.CounterSamples[0].CookedValue, 1)
        } else {
            0
        }

        # Get only what we need: ProcessName, Id, CPU, WorkingSet64
        $processes = Get-Process | Select-Object ProcessName, Id, CPU, WorkingSet64

        $topCPU = $processes |
            Where-Object { $_.CPU -gt 0 } |
            Sort-Object CPU -Descending |
            Select-Object -First 5 |
            ForEach-Object {
                @{
                    Name = $_.ProcessName
                    PID = $_.Id
                    CPU_Seconds = [math]::Round($_.CPU, 1)
                    Memory_MB = [math]::Round($_.WorkingSet64 / 1MB, 1)
                }
            }

        # Cache core count
        if (-not $Script:CachedCoreCount) {
            $Script:CachedCoreCount = $env:NUMBER_OF_PROCESSORS
        }

        # Clear process list immediately
        $processes = $null

        return @{
            OverallPercent = $cpuPercent
            CoreCount = $Script:CachedCoreCount
            TopConsumers = @($topCPU)
        }
    }
    catch {
        Write-Log "Failed to collect CPU metrics: $_" "ERROR"
        return @{
            OverallPercent = -1
            CoreCount = 0
            TopConsumers = @()
            Error = $_.Exception.Message
        }
    }
}

function Get-MemoryMetrics {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop -Property TotalVisibleMemorySize, FreePhysicalMemory

        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedGB = [math]::Round($totalGB - $freeGB, 2)
        $percentUsed = [math]::Round(($usedGB / $totalGB) * 100, 1)

        # Dispose CIM object
        $os = $null

        # Get only what we need
        $processes = Get-Process | Select-Object ProcessName, Id, WorkingSet64, PrivateMemorySize64

        $topMem = $processes |
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First 5 |
            ForEach-Object {
                @{
                    Name = $_.ProcessName
                    PID = $_.Id
                    Memory_MB = [math]::Round($_.WorkingSet64 / 1MB, 1)
                    PrivateMemory_MB = [math]::Round($_.PrivateMemorySize64 / 1MB, 1)
                }
            }

        # Clear process list immediately
        $processes = $null

        return @{
            Total_GB = $totalGB
            Used_GB = $usedGB
            Available_GB = $freeGB
            PercentUsed = $percentUsed
            TopConsumers = @($topMem)
        }
    }
    catch {
        Write-Log "Failed to collect memory metrics: $_" "ERROR"
        return @{
            Total_GB = 0
            Used_GB = 0
            Available_GB = 0
            PercentUsed = -1
            TopConsumers = @()
            Error = $_.Exception.Message
        }
    }
}

function Get-NetworkMetrics {
    try {
        $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | 
            Where-Object { $_.Status -eq 'Up' } | 
            Select-Object -First 1
        
        if (-not $adapter) {
            $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | 
                Where-Object { $_.Status -eq 'Up' } | 
                Select-Object -First 1
        }
        
        if (-not $adapter) {
            return @{
                InterfaceName = "Unknown"
                InterfaceType = "Unknown"
                Status = "No active adapter"
                BytesSentRate = 0
                BytesReceivedRate = 0
                UtilizationPercent = 0
            }
        }
        
        $interfaceName = $adapter.Name
        $interfaceType = if ($adapter.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN') { "WiFi" } else { "Ethernet" }
        
        $linkSpeedBps = $adapter.LinkSpeed
        if ($linkSpeedBps -match '(\d+)\s*(Gbps|Mbps)') {
            $speed = [int]$Matches[1]
            $unit = $Matches[2]
            $linkSpeedBps = if ($unit -eq 'Gbps') { $speed * 1000000000 } else { $speed * 1000000 }
        }
        
        $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
        
        $currentStats = @{
            BytesSent = $stats.SentBytes
            BytesReceived = $stats.ReceivedBytes
            Timestamp = (Get-Date).ToString("o")
        }
        
        $rateData = @{
            BytesSentRate = 0
            BytesReceivedRate = 0
            UtilizationPercent = 0
        }
        
        $prevStatsFile = Join-Path $Script:Config.OutputPath "net_prev.json"
        if (Test-Path $prevStatsFile) {
            try {
                $prevStats = Get-Content $prevStatsFile -Raw | ConvertFrom-Json
                $elapsed = ((Get-Date) - [datetime]$prevStats.Timestamp).TotalSeconds
                
                if ($elapsed -gt 0 -and $elapsed -lt 300) {
                    $sentRate = ($currentStats.BytesSent - $prevStats.BytesSent) / $elapsed
                    $recvRate = ($currentStats.BytesReceived - $prevStats.BytesReceived) / $elapsed
                    
                    if ($sentRate -lt 0) { $sentRate = 0 }
                    if ($recvRate -lt 0) { $recvRate = 0 }
                    
                    $rateData.BytesSentRate = [math]::Round($sentRate, 0)
                    $rateData.BytesReceivedRate = [math]::Round($recvRate, 0)
                    
                    if ($linkSpeedBps -gt 0) {
                        $totalBitsPerSec = ($sentRate + $recvRate) * 8
                        $rateData.UtilizationPercent = [math]::Round(($totalBitsPerSec / $linkSpeedBps) * 100, 1)
                    }
                }
            } catch { }
        }
        
        $currentStats | ConvertTo-Json | Set-Content $prevStatsFile -Force
        
        return @{
            InterfaceName = $interfaceName
            InterfaceType = $interfaceType
            LinkSpeed = $adapter.LinkSpeed
            Status = $adapter.Status
            BytesSent = $stats.SentBytes
            BytesReceived = $stats.ReceivedBytes
            BytesSentRate = $rateData.BytesSentRate
            BytesReceivedRate = $rateData.BytesReceivedRate
            UtilizationPercent = $rateData.UtilizationPercent
        }
    }
    catch {
        Write-Log "Failed to collect network metrics: $_" "ERROR"
        return @{
            InterfaceName = "Error"
            Error = $_.Exception.Message
            BytesSentRate = 0
            BytesReceivedRate = 0
            UtilizationPercent = 0
        }
    }
}

function Get-LatencyMetrics {
    param([string]$Target)
    
    try {
        $pings = Test-Connection -ComputerName $Target -Count 4 -ErrorAction SilentlyContinue
        
        if ($pings) {
            $latencies = $pings | ForEach-Object { $_.ResponseTime }
            $avg = [math]::Round(($latencies | Measure-Object -Average).Average, 1)
            $min = [math]::Round(($latencies | Measure-Object -Minimum).Minimum, 1)
            $max = [math]::Round(($latencies | Measure-Object -Maximum).Maximum, 1)
            $jitter = [math]::Round($max - $min, 1)
            $loss = [math]::Round((1 - ($pings.Count / 4)) * 100, 0)
            
            return @{
                Target = $Target
                IsReachable = $true
                AvgLatency_ms = $avg
                MinLatency_ms = $min
                MaxLatency_ms = $max
                Jitter_ms = $jitter
                PacketLoss_Percent = $loss
            }
        } else {
            return @{
                Target = $Target
                IsReachable = $false
                AvgLatency_ms = -1
                PacketLoss_Percent = 100
            }
        }
    }
    catch {
        return @{
            Target = $Target
            IsReachable = $false
            Error = $_.Exception.Message
            AvgLatency_ms = -1
        }
    }
}

function Test-DicomConnectivity {
    param([string]$HostName, [int]$Port)
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Test-NetConnection -ComputerName $HostName -Port $Port -WarningAction SilentlyContinue
        $stopwatch.Stop()
        
        return @{
            Host = $HostName
            Port = $Port
            IsReachable = $result.TcpTestSucceeded
            ConnectionTime_ms = $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        return @{
            Host = $HostName
            Port = $Port
            IsReachable = $false
            Error = $_.Exception.Message
        }
    }
}

function Get-SystemInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue -Property LastBootUpTime, Caption
        $uptime = if ($os) {
            [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
        } else { 0 }
        $osCaption = $os.Caption
        $os = $null  # Dispose

        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
            Select-Object -First 1).IPAddress

        # Get logged-in user (works even when running as SYSTEM)
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue -Property UserName
        $loggedInUser = if ($cs.UserName) { $cs.UserName } else { "No user logged in" }
        $cs = $null  # Dispose

        return @{
            Hostname = $env:COMPUTERNAME
            LoggedInUser = $loggedInUser
            IPAddress = $ip
            OSVersion = $osCaption
            UptimeHours = $uptime
        }
    }
    catch {
        return @{
            Hostname = $env:COMPUTERNAME
            Error = $_.Exception.Message
        }
    }
}

# =============================================================================
# Main Collection Function
# =============================================================================

function Get-AllMetrics {
    $metrics = @{
        Timestamp = (Get-Date).ToString("o")
        CollectorVersion = $Script:Config.Version
        System = Get-SystemInfo
        CPU = Get-CPUMetrics
        Memory = Get-MemoryMetrics
        Network = Get-NetworkMetrics
        Latency = @()
        DICOM = @()
    }
    
    foreach ($target in $Script:Config.LatencyTargets) {
        if ($target) {
            $metrics.Latency += Get-LatencyMetrics -Target $target
        }
    }
    
    foreach ($dicomHost in $Script:Config.DicomHosts) {
        if ($dicomHost) {
            $metrics.DICOM += Test-DicomConnectivity -HostName $dicomHost -Port $Script:Config.DicomPort
        }
    }
    
    return $metrics
}

function Save-Metrics {
    param([hashtable]$Metrics)

    if (-not (Test-Path $Script:Config.OutputPath)) {
        New-Item -ItemType Directory -Path $Script:Config.OutputPath -Force | Out-Null
    }

    $currentFile = Join-Path $Script:Config.OutputPath $Script:Config.MetricsFile

    # Load existing RecentHistory from current metrics file
    $recentHistory = @()
    if (Test-Path $currentFile) {
        try {
            $existing = Get-Content $currentFile -Raw | ConvertFrom-Json
            if ($existing.RecentHistory) {
                $recentHistory = @($existing.RecentHistory)
            }
        } catch { }
    }

    # Add current reading to history
    $historyEntry = @{
        Timestamp = $Metrics.Timestamp
        CPU = $Metrics.CPU.OverallPercent
        Memory = $Metrics.Memory.PercentUsed
        Network = $Metrics.Network.UtilizationPercent
    }
    $recentHistory += $historyEntry

    # Keep last 30 entries
    if ($recentHistory.Count -gt 30) {
        $recentHistory = $recentHistory | Select-Object -Last 30
    }

    # Add to metrics
    $Metrics.RecentHistory = $recentHistory

    $Metrics | ConvertTo-Json -Depth 10 | Set-Content $currentFile -Force

    # Skip detailed history file - RecentHistory in metrics.json is sufficient for dashboard
    # This avoids loading/parsing potentially huge history file every cycle
    # If full history is needed, enable by uncommenting below

    <#
    $historyFile = Join-Path $Script:Config.OutputPath $Script:Config.HistoryFile
    $history = @()
    if (Test-Path $historyFile) {
        try {
            $existingHistory = Get-Content $historyFile -Raw | ConvertFrom-Json
            if ($existingHistory -is [array]) {
                $history = @($existingHistory)
            } else {
                $history = @($existingHistory)
            }
        } catch {
            $history = @()
        }
    }
    $history += $Metrics
    if ($history.Count -gt $Script:Config.MaxHistoryRecords) {
        $history = $history | Select-Object -Last $Script:Config.MaxHistoryRecords
    }
    $history | ConvertTo-Json -Depth 10 | Set-Content $historyFile -Force
    $history = $null
    #>

    if ($Script:Config.SharedPath -and (Test-Path $Script:Config.SharedPath)) {
        try {
            $sharedFile = Join-Path $Script:Config.SharedPath "$($env:COMPUTERNAME).json"
            $Metrics | ConvertTo-Json -Depth 10 | Set-Content $sharedFile -Force
        } catch {
            Write-Log "Failed to save to shared path: $_" "WARN"
        }
    }
}

# =============================================================================
# Main Execution
# =============================================================================

# Ensure output directory exists
if (-not (Test-Path $Script:Config.OutputPath)) {
    New-Item -ItemType Directory -Path $Script:Config.OutputPath -Force | Out-Null
}

Write-Log "WorkstationMonitor starting (Version $($Script:Config.Version))"
Write-Log "Output path: $($Script:Config.OutputPath)"
Write-Log "Interval: $($Script:Config.IntervalSeconds) seconds"

if ($Script:Config.RunOnce) {
    # Single collection run
    $metrics = Get-AllMetrics
    Save-Metrics -Metrics $metrics
    Write-Log "Single collection complete"
    
    # Display summary to console (if visible)
    Write-Host ""
    Write-Host "=== Workstation Monitor ===" -ForegroundColor Cyan
    Write-Host "Hostname:    $($metrics.System.Hostname)"
    Write-Host "CPU:         $($metrics.CPU.OverallPercent)%"
    Write-Host "Memory:      $($metrics.Memory.PercentUsed)%"
    Write-Host "Network:     $($metrics.Network.UtilizationPercent)%"
    Write-Host ""
    Write-Host "Data saved to: $($Script:Config.OutputPath)"
    
    exit 0
}

# Continuous monitoring mode (background)
$Script:LoopCount = 0
while ($true) {
    try {
        $metrics = Get-AllMetrics
        Save-Metrics -Metrics $metrics
        Write-Log "Collected: CPU=$($metrics.CPU.OverallPercent)% RAM=$($metrics.Memory.PercentUsed)%"
    }
    catch {
        Write-Log "Collection error: $_" "ERROR"
    }

    # Aggressive cleanup to prevent memory leak
    $metrics = $null
    $Script:LoopCount++

    # Force GC every cycle, full collection every 10 cycles
    if ($Script:LoopCount % 10 -eq 0) {
        [System.GC]::Collect(2, [System.GCCollectionMode]::Forced, $true)
        [System.GC]::WaitForPendingFinalizers()
    } else {
        [System.GC]::Collect()
    }

    Start-Sleep -Seconds $Script:Config.IntervalSeconds
}
