<#
.SYNOPSIS
    Workstation Monitor - Local Dashboard Server

.DESCRIPTION
    Starts a lightweight HTTP server on localhost to view the monitoring dashboard.
    RDP into any workstation, run this script, open browser to http://localhost:8080

    Can view:
    - Local metrics only (default)
    - All workstations if SharedPath is configured

.EXAMPLE
    # Start dashboard on port 8080
    .\Dashboard.ps1

    # Start on different port
    .\Dashboard.ps1 -Port 9090

    # View metrics from shared network path
    .\Dashboard.ps1 -SharedPath "\\server\metrics"

.NOTES
    Author: Your IT Team
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [int]$Port = 9090,
    [string]$DataPath = "$env:ProgramData\WorkstationMonitor",
    [string]$SharedPath = ""
)

# =============================================================================
# Dashboard HTML Template
# =============================================================================

$DashboardHTML = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Workstation Monitor</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0f172a; 
            color: #e2e8f0;
            min-height: 100vh;
        }
        .header {
            background: linear-gradient(135deg, #1e3a5f 0%, #0f172a 100%);
            padding: 1.5rem 2rem;
            border-bottom: 1px solid #334155;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .header h1 { 
            color: #38bdf8; 
            font-size: 1.5rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        .header .subtitle { color: #94a3b8; font-size: 0.9rem; margin-top: 0.25rem; }
        .header-right { text-align: right; }
        .header-right .last-update { color: #64748b; font-size: 0.85rem; }
        
        .container { padding: 2rem; max-width: 1800px; margin: 0 auto; }
        
        /* Alerts Section */
        .alerts-section {
            background: #1e293b;
            border-radius: 12px;
            padding: 1.25rem;
            margin-bottom: 2rem;
            border: 1px solid #334155;
        }
        .alerts-header { 
            display: flex; 
            justify-content: space-between; 
            align-items: center;
            margin-bottom: 1rem;
        }
        .alerts-header h2 { color: #f87171; font-size: 1rem; }
        .alert-count {
            background: #7f1d1d;
            color: #fca5a5;
            padding: 0.25rem 0.75rem;
            border-radius: 20px;
            font-size: 0.8rem;
        }
        .alert {
            background: #0f172a;
            border-left: 4px solid #f87171;
            padding: 0.75rem 1rem;
            margin-bottom: 0.5rem;
            border-radius: 0 8px 8px 0;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .alert.warning { border-color: #fbbf24; }
        .alert .hostname { font-weight: 600; color: #38bdf8; }
        .alert .message { color: #94a3b8; margin-left: 0.5rem; }
        .alert .value { color: #f87171; font-weight: 600; }
        .alert .dismiss-btn {
            background: #334155;
            border: none;
            color: #64748b;
            width: 24px;
            height: 24px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 1rem;
            margin-left: 0.75rem;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: all 0.2s;
        }
        .alert .dismiss-btn:hover {
            background: #475569;
            color: #e2e8f0;
        }
        .alert-actions {
            display: flex;
            align-items: center;
        }
        .dismissed-toggle {
            font-size: 0.8rem;
            color: #64748b;
            cursor: pointer;
            margin-left: 1rem;
        }
        .dismissed-toggle:hover {
            color: #94a3b8;
        }
        .no-alerts { 
            color: #4ade80; 
            padding: 1rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        
        /* Summary Cards */
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin-bottom: 2rem;
        }
        .summary-card {
            background: #1e293b;
            border-radius: 12px;
            padding: 1.25rem;
            border: 1px solid #334155;
            text-align: center;
        }
        .summary-card .label { color: #64748b; font-size: 0.85rem; margin-bottom: 0.5rem; }
        .summary-card .value { font-size: 2rem; font-weight: 700; }
        .summary-card .value.good { color: #4ade80; }
        .summary-card .value.warning { color: #fbbf24; }
        .summary-card .value.critical { color: #f87171; }
        
        /* Workstation Grid */
        .section-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1rem;
            flex-wrap: wrap;
            gap: 1rem;
        }
        .section-header h2 { color: #e2e8f0; font-size: 1.1rem; }

        /* Search and Filter Controls */
        .filter-controls {
            display: flex;
            gap: 1rem;
            align-items: center;
            flex-wrap: wrap;
        }
        .search-box {
            background: #0f172a;
            border: 1px solid #334155;
            border-radius: 6px;
            padding: 0.5rem 1rem;
            color: #e2e8f0;
            font-size: 0.85rem;
            width: 200px;
        }
        .search-box:focus {
            outline: none;
            border-color: #38bdf8;
        }
        .search-box::placeholder {
            color: #64748b;
        }
        .filter-buttons {
            display: flex;
            gap: 0.5rem;
            flex-wrap: wrap;
        }
        .filter-btn {
            background: #334155;
            border: none;
            color: #94a3b8;
            padding: 0.5rem 0.75rem;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.8rem;
            transition: all 0.2s;
        }
        .filter-btn:hover {
            background: #475569;
        }
        .filter-btn.active {
            background: #38bdf8;
            color: #0f172a;
        }
        .filter-btn.active.alert-filter {
            background: #f87171;
            color: #0f172a;
        }
        .filter-divider {
            width: 1px;
            height: 24px;
            background: #334155;
        }
        .workstation-card.hidden {
            display: none;
        }
        .no-results {
            grid-column: 1 / -1;
            text-align: center;
            padding: 2rem;
            color: #64748b;
        }
        
        .workstations-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
            gap: 1.5rem;
        }
        .workstation-card {
            background: #1e293b;
            border-radius: 12px;
            padding: 1.5rem;
            border: 1px solid #334155;
            transition: all 0.2s ease;
            cursor: pointer;
        }
        .workstation-card:hover {
            border-color: #38bdf8;
            transform: translateY(-2px);
        }
        .workstation-card.offline { 
            opacity: 0.6; 
            border-color: #f87171;
        }
        .workstation-card.local {
            border-color: #38bdf8;
            box-shadow: 0 0 20px rgba(56, 189, 248, 0.1);
        }
        
        .workstation-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 1rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid #334155;
        }
        .workstation-name { 
            font-weight: 700; 
            color: #38bdf8; 
            font-size: 1.1rem;
        }
        .workstation-ip { color: #64748b; font-size: 0.85rem; margin-top: 0.25rem; }
        .workstation-user { color: #94a3b8; font-size: 0.85rem; margin-top: 0.15rem; }
        .status-badge {
            padding: 0.35rem 0.85rem;
            border-radius: 20px;
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        .status-badge.online { background: #166534; color: #4ade80; }
        .status-badge.offline { background: #7f1d1d; color: #fca5a5; }
        .status-badge.local { background: #0369a1; color: #38bdf8; }
        
        /* Metric Gauges */
        .metrics-row {
            display: flex;
            gap: 1rem;
            margin-bottom: 1rem;
        }
        .metric-gauge {
            flex: 1;
            background: #0f172a;
            border-radius: 8px;
            padding: 1rem;
            text-align: center;
        }
        .metric-gauge .label { 
            color: #64748b; 
            font-size: 0.75rem; 
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 0.5rem;
        }
        .metric-gauge .value { 
            font-size: 1.75rem; 
            font-weight: 700;
        }
        .metric-gauge .bar {
            height: 6px;
            background: #334155;
            border-radius: 3px;
            margin-top: 0.5rem;
            overflow: hidden;
        }
        .metric-gauge .bar-fill {
            height: 100%;
            border-radius: 3px;
            transition: width 0.3s ease;
        }
        .bar-fill.good { background: linear-gradient(90deg, #22c55e, #4ade80); }
        .bar-fill.warning { background: linear-gradient(90deg, #f59e0b, #fbbf24); }
        .bar-fill.critical { background: linear-gradient(90deg, #dc2626, #f87171); }
        
        /* Process List */
        .process-section {
            margin-top: 1rem;
            padding-top: 1rem;
            border-top: 1px solid #334155;
        }
        .process-section h4 {
            color: #64748b;
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 0.5rem;
        }
        .process-list {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
        }
        .process-tag {
            background: #334155;
            color: #94a3b8;
            padding: 0.25rem 0.6rem;
            border-radius: 4px;
            font-size: 0.75rem;
            font-family: 'Consolas', monospace;
        }
        .process-tag .value {
            color: #fbbf24;
            margin-left: 0.25rem;
        }
        
        /* Latency Section */
        .latency-section {
            margin-top: 1rem;
            padding-top: 1rem;
            border-top: 1px solid #334155;
        }
        .latency-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.4rem 0;
            font-size: 0.85rem;
        }
        .latency-target { color: #94a3b8; }
        .latency-value { font-weight: 600; }
        .latency-value.good { color: #4ade80; }
        .latency-value.warning { color: #fbbf24; }
        .latency-value.critical { color: #f87171; }
        .latency-jitter { color: #64748b; font-size: 0.75rem; margin-left: 0.5rem; }
        
        /* Footer */
        .footer {
            text-align: center;
            color: #475569;
            font-size: 0.8rem;
            margin-top: 2rem;
            padding-top: 1rem;
            border-top: 1px solid #334155;
        }
        
        /* Export Button */
        .export-btn {
            background: #334155;
            color: #94a3b8;
            border: 1px solid #475569;
            padding: 0.5rem 1rem;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.85rem;
            transition: all 0.2s;
        }
        .export-btn:hover {
            background: #475569;
            color: #e2e8f0;
        }
        
        /* History Chart Placeholder */
        .chart-container {
            background: #1e293b;
            border-radius: 12px;
            padding: 1.5rem;
            margin-bottom: 2rem;
            border: 1px solid #334155;
        }
        .chart-container h3 {
            color: #e2e8f0;
            font-size: 1rem;
            margin-bottom: 1rem;
        }
        .chart-placeholder {
            height: 200px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #64748b;
            border: 2px dashed #334155;
            border-radius: 8px;
        }

        /* Modal Overlay */
        .modal-overlay {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.8);
            z-index: 1000;
            justify-content: center;
            align-items: center;
            overflow-y: auto;
            padding: 2rem;
        }
        .modal-overlay.active {
            display: flex;
        }
        .modal-content {
            background: #1e293b;
            border-radius: 12px;
            max-width: 900px;
            width: 100%;
            max-height: 90vh;
            overflow-y: auto;
            position: relative;
            border: 1px solid #334155;
        }
        .modal-header {
            padding: 1.5rem;
            border-bottom: 1px solid #334155;
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            position: sticky;
            top: 0;
            background: #1e293b;
            z-index: 10;
        }
        .modal-header h2 {
            color: #38bdf8;
            font-size: 1.5rem;
            margin-bottom: 0.25rem;
        }
        .modal-header .ip {
            color: #64748b;
            font-size: 0.9rem;
        }
        .modal-close {
            background: #334155;
            border: none;
            color: #94a3b8;
            width: 32px;
            height: 32px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 1.2rem;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: all 0.2s;
        }
        .modal-close:hover {
            background: #475569;
            color: #e2e8f0;
        }
        .modal-body {
            padding: 1.5rem;
        }
        .modal-graphs {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1.5rem;
            margin-bottom: 1.5rem;
        }
        .graph-container {
            background: #0f172a;
            border-radius: 8px;
            padding: 1rem;
        }
        .graph-container h3 {
            color: #64748b;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 0.75rem;
        }
        .graph-empty {
            color: #475569;
            font-size: 0.85rem;
            text-align: center;
            padding: 2rem;
        }
        .modal-processes {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1.5rem;
        }
        .process-column {
            background: #0f172a;
            border-radius: 8px;
            padding: 1rem;
        }
        .process-column h3 {
            color: #64748b;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 0.75rem;
        }
        .process-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.5rem;
            margin-bottom: 0.25rem;
            background: #1e293b;
            border-radius: 4px;
            font-size: 0.85rem;
        }
        .process-item .name {
            color: #94a3b8;
            font-family: 'Consolas', monospace;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            flex: 1;
            margin-right: 0.5rem;
        }
        .process-item .value {
            color: #fbbf24;
            font-weight: 600;
            white-space: nowrap;
        }
    </style>
</head>
<body>
    <div class="header">
        <div>
            <h1>Workstation Monitor</h1>
            <div class="subtitle">Workstation Performance Monitoring</div>
        </div>
        <div class="header-right">
            <button class="export-btn" onclick="exportData()">Export CSV</button>
            <div class="last-update">Last refresh: <span id="last-update">--</span></div>
        </div>
    </div>
    
    <div class="container">
        <!-- Alerts -->
        <div class="alerts-section" id="alerts-section">
            <div class="alerts-header">
                <h2>Active Alerts</h2>
                <div style="display: flex; align-items: center; gap: 0.75rem;">
                    <span class="alert-count" id="alert-count">0</span>
                    <span class="dismissed-toggle" id="dismissed-toggle" onclick="toggleDismissedAlerts()"></span>
                </div>
            </div>
            <div id="alerts-container">Loading...</div>
        </div>
        
        <!-- Summary Cards -->
        <div class="summary-grid" id="summary-grid">
            <div class="summary-card">
                <div class="label">Total Workstations</div>
                <div class="value" id="total-count">-</div>
            </div>
            <div class="summary-card">
                <div class="label">Online</div>
                <div class="value good" id="online-count">-</div>
            </div>
            <div class="summary-card">
                <div class="label">Avg CPU</div>
                <div class="value" id="avg-cpu">-</div>
            </div>
            <div class="summary-card">
                <div class="label">Avg Memory</div>
                <div class="value" id="avg-memory">-</div>
            </div>
            <div class="summary-card">
                <div class="label">High Latency</div>
                <div class="value" id="high-latency">-</div>
            </div>
        </div>
        
        <!-- Workstations -->
        <div class="section-header">
            <h2>Workstations <span id="visible-count" style="color: #64748b; font-weight: normal;"></span></h2>
            <div class="filter-controls">
                <input type="text" class="search-box" id="search-box" placeholder="Search PC or user..." oninput="applyFilters()">
                <div class="filter-divider"></div>
                <div class="filter-buttons">
                    <button class="filter-btn" id="filter-cpu" onclick="toggleFilter('cpu')">High CPU</button>
                    <button class="filter-btn" id="filter-memory" onclick="toggleFilter('memory')">High Memory</button>
                    <button class="filter-btn" id="filter-latency" onclick="toggleFilter('latency')">High Latency</button>
                    <button class="filter-btn alert-filter" id="filter-alerts" onclick="toggleFilter('alerts')">Has Alerts</button>
                </div>
                <div class="filter-divider"></div>
                <button class="filter-btn active" id="filter-offline" onclick="toggleFilter('offline')">Hide Offline</button>
            </div>
        </div>
        <div class="workstations-grid" id="workstations-container">
            Loading...
        </div>
        
        <div class="footer">
            Auto-refreshes every 30 seconds | Your IT Team
        </div>
    </div>

    <!-- Modal Overlay -->
    <div class="modal-overlay" id="modal-overlay" onclick="closeModalOnBackdrop(event)">
        <div class="modal-content">
            <div class="modal-header">
                <div>
                    <h2 id="modal-hostname">Loading...</h2>
                    <div class="ip" id="modal-ip"></div>
                </div>
                <button class="modal-close" onclick="closeModal()">&times;</button>
            </div>
            <div class="modal-body" id="modal-body">
                Loading...
            </div>
        </div>
    </div>

    <script>
        const CONFIG = {
            refreshInterval: 30000,
            thresholds: {
                cpu: { warning: 70, critical: 90 },
                memory: { warning: 70, critical: 90 },
                latency: { warning: 20, critical: 30 },
                offlineMinutes: 5
            }
        };

        let allMetrics = [];
        let activeFilters = {
            cpu: false,
            memory: false,
            latency: false,
            alerts: false,
            offline: true  // Hide offline by default
        };
        let dismissedAlerts = JSON.parse(localStorage.getItem('dismissedAlerts') || '{}');
        let showDismissed = false;

        // XSS Protection: Escape HTML entities in user-controlled data
        function escapeHtml(unsafe) {
            if (unsafe === null || unsafe === undefined) return '';
            return String(unsafe)
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&#039;");
        }
        
        function getStatusClass(value, warning, critical) {
            if (value >= critical) return 'critical';
            if (value >= warning) return 'warning';
            return 'good';
        }
        
        function formatTimestamp(ts) {
            if (!ts) return 'Never';
            const date = new Date(ts);
            const now = new Date();
            const diffMs = now - date;
            const diffMins = Math.floor(diffMs / 60000);
            
            if (diffMins < 1) return 'Just now';
            if (diffMins < 60) return diffMins + 'm ago';
            if (diffMins < 1440) return Math.floor(diffMins/60) + 'h ago';
            return date.toLocaleDateString();
        }
        
        function isOffline(timestamp) {
            if (!timestamp) return true;
            const date = new Date(timestamp);
            const now = new Date();
            return (now - date) > CONFIG.thresholds.offlineMinutes * 60 * 1000;
        }
        
        function getAlertKey(hostname, type) {
            return hostname + ':' + type;
        }

        function dismissAlert(hostname, type) {
            const key = getAlertKey(hostname, type);
            dismissedAlerts[key] = Date.now();
            localStorage.setItem('dismissedAlerts', JSON.stringify(dismissedAlerts));
            renderAlerts(generateAlerts(allMetrics));
        }

        function clearDismissedAlert(hostname, type) {
            const key = getAlertKey(hostname, type);
            delete dismissedAlerts[key];
            localStorage.setItem('dismissedAlerts', JSON.stringify(dismissedAlerts));
        }

        function toggleDismissedAlerts() {
            showDismissed = !showDismissed;
            renderAlerts(generateAlerts(allMetrics));
        }

        function generateAlerts(metrics) {
            const alerts = [];
            const onlineHosts = new Set();

            // First pass: identify online hosts to clear their dismissed offline alerts
            metrics.forEach(m => {
                if (!isOffline(m.Timestamp)) {
                    const hostname = m.System?.Hostname || 'Unknown';
                    onlineHosts.add(hostname);
                    // Clear dismissed offline alert if workstation came back online
                    clearDismissedAlert(hostname, 'offline');
                }
            });

            metrics.forEach(m => {
                const hostname = m.System?.Hostname || 'Unknown';

                if (isOffline(m.Timestamp)) {
                    alerts.push({
                        hostname: hostname,
                        type: 'offline',
                        severity: 'critical',
                        message: 'Workstation offline',
                        value: formatTimestamp(m.Timestamp),
                        dismissed: !!dismissedAlerts[getAlertKey(hostname, 'offline')]
                    });
                    return;
                }

                if (m.CPU?.OverallPercent > CONFIG.thresholds.cpu.critical) {
                    alerts.push({
                        hostname: hostname,
                        type: 'cpu',
                        severity: 'critical',
                        message: 'High CPU',
                        value: m.CPU.OverallPercent.toFixed(1) + '%',
                        dismissed: false  // Don't persist CPU/Memory alerts
                    });
                }

                if (m.Memory?.PercentUsed > CONFIG.thresholds.memory.critical) {
                    alerts.push({
                        hostname: hostname,
                        type: 'memory',
                        severity: 'critical',
                        message: 'High Memory',
                        value: m.Memory.PercentUsed.toFixed(1) + '%',
                        dismissed: false
                    });
                }

                m.Latency?.forEach(lat => {
                    if (lat.AvgLatency_ms > CONFIG.thresholds.latency.critical) {
                        alerts.push({
                            hostname: hostname,
                            type: 'latency',
                            severity: 'warning',
                            message: 'High latency to ' + lat.Target,
                            value: lat.AvgLatency_ms.toFixed(0) + 'ms',
                            dismissed: false
                        });
                    }
                });
            });

            return alerts;
        }
        
        function renderAlerts(alerts) {
            const container = document.getElementById('alerts-container');
            const countEl = document.getElementById('alert-count');
            const toggleEl = document.getElementById('dismissed-toggle');

            const activeAlerts = alerts.filter(a => !a.dismissed);
            const dismissedCount = alerts.filter(a => a.dismissed).length;
            const displayAlerts = showDismissed ? alerts : activeAlerts;

            countEl.textContent = activeAlerts.length;
            countEl.style.display = activeAlerts.length ? 'inline' : 'none';

            // Update dismissed toggle text
            if (dismissedCount > 0) {
                toggleEl.textContent = showDismissed
                    ? 'Hide ' + dismissedCount + ' dismissed'
                    : 'Show ' + dismissedCount + ' dismissed';
                toggleEl.style.display = 'inline';
            } else {
                toggleEl.style.display = 'none';
            }

            if (displayAlerts.length === 0) {
                container.innerHTML = '<div class="no-alerts">OK - No active alerts - all systems nominal</div>';
                return;
            }

            container.innerHTML = displayAlerts.map(a => `
                <div class="alert ${a.severity === 'warning' ? 'warning' : ''}" style="${a.dismissed ? 'opacity: 0.5;' : ''}">
                    <div>
                        <span class="hostname">${escapeHtml(a.hostname)}</span>
                        <span class="message">${escapeHtml(a.message)}</span>
                        ${a.dismissed ? '<span style="color: #64748b; font-size: 0.75rem; margin-left: 0.5rem;">(dismissed)</span>' : ''}
                    </div>
                    <div class="alert-actions">
                        <span class="value">${escapeHtml(a.value)}</span>
                        ${a.type === 'offline' && !a.dismissed ? `
                            <button class="dismiss-btn" onclick="dismissAlert('${escapeHtml(a.hostname)}', '${a.type}')" title="Dismiss this alert">×</button>
                        ` : ''}
                    </div>
                </div>
            `).join('');
        }
        
        function renderSummary(metrics) {
            const online = metrics.filter(m => !isOffline(m.Timestamp));
            
            document.getElementById('total-count').textContent = metrics.length;
            document.getElementById('online-count').textContent = online.length;
            
            if (online.length > 0) {
                const avgCpu = online.reduce((sum, m) => sum + (m.CPU?.OverallPercent || 0), 0) / online.length;
                const avgMem = online.reduce((sum, m) => sum + (m.Memory?.PercentUsed || 0), 0) / online.length;
                
                const cpuEl = document.getElementById('avg-cpu');
                cpuEl.textContent = avgCpu.toFixed(1) + '%';
                cpuEl.className = 'value ' + getStatusClass(avgCpu, 70, 90);
                
                const memEl = document.getElementById('avg-memory');
                memEl.textContent = avgMem.toFixed(1) + '%';
                memEl.className = 'value ' + getStatusClass(avgMem, 70, 90);
                
                let highLatencyCount = 0;
                online.forEach(m => {
                    m.Latency?.forEach(lat => {
                        if (lat.AvgLatency_ms > CONFIG.thresholds.latency.warning) highLatencyCount++;
                    });
                });
                
                const latEl = document.getElementById('high-latency');
                latEl.textContent = highLatencyCount;
                latEl.className = 'value ' + (highLatencyCount > 0 ? 'warning' : 'good');
            }
        }
        
        function renderWorkstations(metrics) {
            const container = document.getElementById('workstations-container');
            const currentHost = '{{HOSTNAME}}';
            
            if (metrics.length === 0) {
                container.innerHTML = '<p style="color: #64748b; grid-column: 1/-1; text-align: center; padding: 2rem;">No workstation data available. Make sure the monitor agent is running.</p>';
                return;
            }
            
            // Sort: local first, then by hostname
            metrics.sort((a, b) => {
                const aHost = a.System?.Hostname || '';
                const bHost = b.System?.Hostname || '';
                if (aHost === currentHost) return -1;
                if (bHost === currentHost) return 1;
                return aHost.localeCompare(bHost);
            });
            
            container.innerHTML = metrics.map(m => {
                const hostname = m.System?.Hostname || 'Unknown';
                const isLocal = hostname === currentHost;
                const offline = isOffline(m.Timestamp);
                
                const cpu = m.CPU?.OverallPercent || 0;
                const mem = m.Memory?.PercentUsed || 0;
                const net = m.Network?.UtilizationPercent || 0;
                
                const cpuClass = getStatusClass(cpu, 70, 90);
                const memClass = getStatusClass(mem, 70, 90);
                
                // Top processes
                const cpuProcs = (m.CPU?.TopConsumers || []).slice(0, 3)
                    .map(p => `<span class="process-tag">${escapeHtml(p.Name)}<span class="value">${escapeHtml(p.CPU_Seconds)}s</span></span>`).join('');
                const memProcs = (m.Memory?.TopConsumers || []).slice(0, 3)
                    .map(p => `<span class="process-tag">${escapeHtml(p.Name)}<span class="value">${escapeHtml(p.Memory_MB)}MB</span></span>`).join('');
                
                // Latency rows
                const latencyRows = (m.Latency || []).map(lat => {
                    const latClass = getStatusClass(lat.AvgLatency_ms, 50, 100);
                    return `
                        <div class="latency-row">
                            <span class="latency-target">${escapeHtml(lat.Target)}</span>
                            <span>
                                <span class="latency-value ${latClass}">${lat.AvgLatency_ms >= 0 ? lat.AvgLatency_ms.toFixed(0) + 'ms' : 'N/A'}</span>
                                <span class="latency-jitter">(±${lat.Jitter_ms >= 0 ? lat.Jitter_ms.toFixed(1) : '-'})</span>
                            </span>
                        </div>
                    `;
                }).join('');
                
                return `
                    <div class="workstation-card ${offline ? 'offline' : ''} ${isLocal ? 'local' : ''}" onclick="showWorkstationDetail('${escapeHtml(hostname)}')">
                        <div class="workstation-header">
                            <div>
                                <div class="workstation-name">${escapeHtml(hostname)}</div>
                                <div class="workstation-ip">${escapeHtml(m.System?.IPAddress || 'Unknown IP')}</div>
                                <div class="workstation-user">${escapeHtml(m.System?.LoggedInUser || '')}</div>
                            </div>
                            <span class="status-badge ${offline ? 'offline' : isLocal ? 'local' : 'online'}">
                                ${offline ? 'OFFLINE' : isLocal ? 'THIS PC' : 'ONLINE'}
                            </span>
                        </div>
                        
                        <div class="metrics-row">
                            <div class="metric-gauge">
                                <div class="label">CPU</div>
                                <div class="value ${cpuClass}">${cpu.toFixed(1)}%</div>
                                <div class="bar"><div class="bar-fill ${cpuClass}" style="width: ${cpu}%"></div></div>
                            </div>
                            <div class="metric-gauge">
                                <div class="label">Memory</div>
                                <div class="value ${memClass}">${mem.toFixed(1)}%</div>
                                <div class="bar"><div class="bar-fill ${memClass}" style="width: ${mem}%"></div></div>
                            </div>
                            <div class="metric-gauge">
                                <div class="label">Network</div>
                                <div class="value">${net.toFixed(1)}%</div>
                                <div class="bar"><div class="bar-fill good" style="width: ${Math.min(net * 2, 100)}%"></div></div>
                            </div>
                        </div>
                        
                        ${cpuProcs ? `
                        <div class="process-section">
                            <h4>Top CPU</h4>
                            <div class="process-list">${cpuProcs}</div>
                        </div>
                        ` : ''}

                        ${memProcs ? `
                        <div class="process-section">
                            <h4>Top Memory</h4>
                            <div class="process-list">${memProcs}</div>
                        </div>
                        ` : ''}
                        
                        ${latencyRows ? `
                        <div class="latency-section">
                            <h4 style="color: #64748b; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.5rem;">Latency & Jitter</h4>
                            ${latencyRows}
                        </div>
                        ` : ''}
                        
                        <div style="margin-top: 1rem; text-align: right; color: #475569; font-size: 0.75rem;">
                            Uptime: ${(m.System?.UptimeHours || 0).toFixed(1)}h | Last: ${formatTimestamp(m.Timestamp)}
                        </div>
                    </div>
                `;
            }).join('');
        }
        
        function renderGraph(dataArray, label) {
            if (!dataArray || dataArray.length === 0) {
                return `<div class="graph-empty">No history available</div>`;
            }

            const width = 300;
            const height = 100;
            const padding = 10;
            const graphWidth = width - padding * 2;
            const graphHeight = height - padding * 2;

            // Find min/max for scaling
            const values = dataArray.map(d => d[label] || 0);
            const maxValue = Math.max(...values, 100); // At least 100 for percentage scale
            const minValue = 0;

            // Generate points
            const points = dataArray.map((d, i) => {
                const x = padding + (i / (dataArray.length - 1)) * graphWidth;
                const value = d[label] || 0;
                const y = height - padding - ((value - minValue) / (maxValue - minValue)) * graphHeight;
                return `${x},${y}`;
            }).join(' ');

            return `
                <svg width="${width}" height="${height}" style="display: block;">
                    <polyline
                        points="${points}"
                        fill="none"
                        stroke="#38bdf8"
                        stroke-width="2"
                    />
                </svg>
            `;
        }

        function renderProcessList(processes, valueKey, unit, limit = 10) {
            if (!processes || processes.length === 0) {
                return '<div style="color: #475569; font-size: 0.85rem; padding: 0.5rem;">No data available</div>';
            }

            return processes.slice(0, limit).map(p => `
                <div class="process-item">
                    <span class="name">${escapeHtml(p.Name)}</span>
                    <span class="value">${escapeHtml(p[valueKey])}${unit}</span>
                </div>
            `).join('');
        }

        function showWorkstationDetail(hostname) {
            const metric = allMetrics.find(m => (m.System?.Hostname || '') === hostname);
            if (!metric) return;

            const modal = document.getElementById('modal-overlay');
            const modalBody = document.getElementById('modal-body');

            // Update header
            document.getElementById('modal-hostname').textContent = escapeHtml(hostname);
            const userInfo = metric.System?.LoggedInUser ? ' | ' + escapeHtml(metric.System.LoggedInUser) : '';
            document.getElementById('modal-ip').textContent = escapeHtml(metric.System?.IPAddress || 'Unknown IP') + userInfo;

            // Build graphs
            const cpuGraph = renderGraph(metric.RecentHistory || [], 'CPU');
            const memGraph = renderGraph(metric.RecentHistory || [], 'Memory');

            // Build process lists
            const cpuProcesses = renderProcessList(metric.CPU?.TopConsumers || [], 'CPU_Seconds', 's', 10);
            const memProcesses = renderProcessList(metric.Memory?.TopConsumers || [], 'Memory_MB', 'MB', 10);

            modalBody.innerHTML = `
                <div class="modal-graphs">
                    <div class="graph-container">
                        <h3>CPU % History</h3>
                        ${cpuGraph}
                    </div>
                    <div class="graph-container">
                        <h3>Memory % History</h3>
                        ${memGraph}
                    </div>
                </div>
                <div class="modal-processes">
                    <div class="process-column">
                        <h3>Top 10 CPU Processes</h3>
                        ${cpuProcesses}
                    </div>
                    <div class="process-column">
                        <h3>Top 10 Memory Processes</h3>
                        ${memProcesses}
                    </div>
                </div>
            `;

            modal.classList.add('active');
        }

        function closeModal() {
            document.getElementById('modal-overlay').classList.remove('active');
        }

        function closeModalOnBackdrop(event) {
            if (event.target.id === 'modal-overlay') {
                closeModal();
            }
        }

        function toggleFilter(filterName) {
            activeFilters[filterName] = !activeFilters[filterName];
            const btn = document.getElementById('filter-' + filterName);
            if (btn) {
                btn.classList.toggle('active', activeFilters[filterName]);
            }
            applyFilters();
        }

        function applyFilters() {
            const searchTerm = document.getElementById('search-box').value.toLowerCase();
            const cards = document.querySelectorAll('.workstation-card');
            let visibleCount = 0;

            cards.forEach(card => {
                const hostname = card.querySelector('.workstation-name').textContent.toLowerCase();
                const isOffline = card.classList.contains('offline');

                // Get metric data from allMetrics
                const metric = allMetrics.find(m =>
                    (m.System?.Hostname || '').toLowerCase() === hostname
                );

                let show = true;

                // Search filter (PC name or logged-in user)
                const loggedInUser = (metric?.System?.LoggedInUser || '').toLowerCase();
                if (searchTerm && !hostname.includes(searchTerm) && !loggedInUser.includes(searchTerm)) {
                    show = false;
                }

                // Offline filter
                if (activeFilters.offline && isOffline) {
                    show = false;
                }

                // High CPU filter
                if (activeFilters.cpu && show) {
                    const cpu = metric?.CPU?.OverallPercent || 0;
                    if (cpu < CONFIG.thresholds.cpu.warning) {
                        show = false;
                    }
                }

                // High Memory filter
                if (activeFilters.memory && show) {
                    const mem = metric?.Memory?.PercentUsed || 0;
                    if (mem < CONFIG.thresholds.memory.warning) {
                        show = false;
                    }
                }

                // High Latency filter
                if (activeFilters.latency && show) {
                    let hasHighLatency = false;
                    (metric?.Latency || []).forEach(lat => {
                        if (lat.AvgLatency_ms > CONFIG.thresholds.latency.warning) {
                            hasHighLatency = true;
                        }
                    });
                    if (!hasHighLatency) {
                        show = false;
                    }
                }

                // Has Alerts filter
                if (activeFilters.alerts && show) {
                    let hasAlert = false;
                    if (isOffline) hasAlert = true;
                    if ((metric?.CPU?.OverallPercent || 0) > CONFIG.thresholds.cpu.critical) hasAlert = true;
                    if ((metric?.Memory?.PercentUsed || 0) > CONFIG.thresholds.memory.critical) hasAlert = true;
                    (metric?.Latency || []).forEach(lat => {
                        if (lat.AvgLatency_ms > CONFIG.thresholds.latency.critical) hasAlert = true;
                    });
                    if (!hasAlert) {
                        show = false;
                    }
                }

                card.classList.toggle('hidden', !show);
                if (show) visibleCount++;
            });

            // Update visible count
            const totalCount = cards.length;
            document.getElementById('visible-count').textContent =
                visibleCount === totalCount ? '' : `(${visibleCount}/${totalCount})`;

            // Show no results message if needed
            const container = document.getElementById('workstations-container');
            let noResults = container.querySelector('.no-results');
            if (visibleCount === 0 && cards.length > 0) {
                if (!noResults) {
                    noResults = document.createElement('div');
                    noResults.className = 'no-results';
                    noResults.textContent = 'No workstations match the current filters';
                    container.appendChild(noResults);
                }
            } else if (noResults) {
                noResults.remove();
            }
        }

        function exportData() {
            if (allMetrics.length === 0) {
                alert('No data to export');
                return;
            }

            // Build CSV
            const headers = ['Timestamp', 'Hostname', 'IP', 'CPU%', 'Memory%', 'Network%', 'Uptime_Hours'];
            const rows = allMetrics.map(m => [
                m.Timestamp,
                m.System?.Hostname || '',
                m.System?.IPAddress || '',
                m.CPU?.OverallPercent || '',
                m.Memory?.PercentUsed || '',
                m.Network?.UtilizationPercent || '',
                m.System?.UptimeHours || ''
            ]);

            const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');

            const blob = new Blob([csv], { type: 'text/csv' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'workstation_metrics_' + new Date().toISOString().slice(0,10) + '.csv';
            a.click();
        }
        
        async function loadData() {
            try {
                const response = await fetch('/api/metrics');
                allMetrics = await response.json();
                
                const alerts = generateAlerts(allMetrics);
                renderAlerts(alerts);
                renderSummary(allMetrics);
                renderWorkstations(allMetrics);
                applyFilters();

                document.getElementById('last-update').textContent = new Date().toLocaleTimeString();
            } catch (error) {
                console.error('Error loading data:', error);
                document.getElementById('workstations-container').innerHTML = 
                    '<p style="color: #f87171; grid-column: 1/-1; text-align: center; padding: 2rem;">Error loading data. Is the dashboard server running?</p>';
            }
        }
        
        // Initial load and auto-refresh
        loadData();
        setInterval(loadData, CONFIG.refreshInterval);
    </script>
</body>
</html>
'@

# =============================================================================
# HTTP Server
# =============================================================================

function Start-DashboardServer {
    param(
        [int]$Port,
        [string]$DataPath,
        [string]$SharedPath
    )
    
    # Create HTTP listener
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    
    try {
        $listener.Start()
    }
    catch {
        Write-Error "Failed to start HTTP listener on port $Port. Is another process using it?"
        Write-Host "Try: .\Dashboard.ps1 -Port 9090" -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Workstation Monitor" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Dashboard running at: " -NoNewline
    Write-Host "http://localhost:$Port" -ForegroundColor Green
    Write-Host ""
    Write-Host "Data path: $DataPath"
    if ($SharedPath) {
        Write-Host "Shared path: $SharedPath"
    }
    Write-Host ""
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    Write-Host ""
    
    # Prepare dashboard HTML with hostname injected
    $html = $DashboardHTML.Replace('{{HOSTNAME}}', $env:COMPUTERNAME)
    
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            $path = $request.Url.LocalPath
            
            switch ($path) {
                "/" {
                    # Serve dashboard HTML
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                    $response.ContentType = "text/html; charset=utf-8"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                
                "/api/metrics" {
                    # Return metrics as JSON array
                    $metricsList = @()
                    
                    # Load local metrics
                    $localFile = Join-Path $DataPath "metrics.json"
                    if (Test-Path $localFile) {
                        try {
                            $localMetrics = Get-Content $localFile -Raw | ConvertFrom-Json
                            $metricsList += ,$localMetrics
                        }
                        catch {
                            Write-Warning "Failed to read local metrics: $_"
                        }
                    }
                    
                    # Load shared metrics if configured
                    if ($SharedPath -and (Test-Path $SharedPath)) {
                        Get-ChildItem -Path $SharedPath -Filter "*.json" -ErrorAction SilentlyContinue | ForEach-Object {
                            # Skip if this is the local machine's file (already loaded)
                            if ($_.BaseName -eq $env:COMPUTERNAME) { return }
                            
                            try {
                                $sharedMetrics = Get-Content $_.FullName -Raw | ConvertFrom-Json
                                $metricsList += ,$sharedMetrics
                            }
                            catch {
                                Write-Warning "Failed to read shared metrics from $($_.Name): $_"
                            }
                        }
                    }
                    
                    # Build JSON manually to ensure array format
                    if ($metricsList.Count -eq 0) {
                        $json = "[]"
                    } elseif ($metricsList.Count -eq 1) {
                        $innerJson = $metricsList[0] | ConvertTo-Json -Depth 10
                        $json = "[$innerJson]"
                    } else {
                        $json = ConvertTo-Json -InputObject $metricsList -Depth 10
                    }
                    
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                
                "/api/history" {
                    # Return historical data
                    $historyFile = Join-Path $DataPath "history.json"
                    if (Test-Path $historyFile) {
                        $json = Get-Content $historyFile -Raw
                    }
                    else {
                        $json = "[]"
                    }
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                
                default {
                    $response.StatusCode = 404
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
            }
            
            $response.OutputStream.Close()
        }
        catch [System.Net.HttpListenerException] {
            # Listener was stopped
            break
        }
        catch {
            Write-Warning "Request error: $_"
        }
    }
}

# =============================================================================
# Main
# =============================================================================

# Hardcode values for EXE compilation (ps2exe doesn't handle param defaults)
if (-not $Port) { $Port = 9090 }
if (-not $SharedPath) { $SharedPath = "" }

Start-DashboardServer -Port $Port -DataPath $DataPath -SharedPath $SharedPath