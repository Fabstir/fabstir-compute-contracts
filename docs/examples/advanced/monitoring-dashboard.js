/**
 * Example: Monitoring Dashboard
 * Purpose: Real-time monitoring system with metrics, alerts, and visualizations
 * Prerequisites:
 *   - Node.js with Express
 *   - WebSocket support
 *   - Basic understanding of monitoring concepts
 */

const { ethers } = require('ethers');
const express = require('express');
const WebSocket = require('ws');
const EventEmitter = require('events');
const fs = require('fs').promises;
const path = require('path');
require('dotenv').config({ path: '../.env' });

// Contract ABIs (simplified)
const CONTRACT_ABIS = {
    NodeRegistry: require('../contracts/NodeRegistry.json').abi,
    JobMarketplace: require('../contracts/JobMarketplace.json').abi,
    PaymentEscrow: require('../contracts/PaymentEscrow.json').abi,
    ReputationSystem: require('../contracts/ReputationSystem.json').abi
};

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    contracts: {
        nodeRegistry: process.env.NODE_REGISTRY,
        jobMarketplace: process.env.JOB_MARKETPLACE,
        paymentEscrow: process.env.PAYMENT_ESCROW,
        reputationSystem: process.env.REPUTATION_SYSTEM
    },
    
    // Monitoring settings
    monitoring: {
        httpPort: 3000,
        wsPort: 3001,
        metricsPort: 9090, // Prometheus metrics
        
        // Collection intervals
        blockInterval: 5000, // 5 seconds
        metricsInterval: 10000, // 10 seconds
        healthCheckInterval: 30000, // 30 seconds
        
        // Data retention
        maxDataPoints: 1000,
        maxLogEntries: 500,
        
        // Alert thresholds
        alerts: {
            highGasPrice: ethers.parseUnits('100', 'gwei'),
            lowNodeCount: 5,
            highFailureRate: 0.1, // 10%
            contractPaused: true,
            unusualActivity: 5 // 5x normal rate
        }
    },
    
    // Dashboard settings
    dashboard: {
        refreshInterval: 5000,
        chartDataPoints: 50,
        enableNotifications: true
    }
};

// Metrics collector
class MetricsCollector extends EventEmitter {
    constructor(provider, contracts) {
        super();
        this.provider = provider;
        this.contracts = contracts;
        this.metrics = {
            blockchain: {
                blockNumber: 0,
                gasPrice: ethers.parseUnits('0', 'gwei'),
                blockTime: 0
            },
            network: {
                totalNodes: 0,
                activeNodes: 0,
                totalJobs: 0,
                activeJobs: 0,
                completedJobs: 0,
                failedJobs: 0
            },
            financial: {
                totalVolume: ethers.parseEther('0'),
                averageJobValue: ethers.parseEther('0'),
                escrowBalance: ethers.parseEther('0'),
                dailyVolume: ethers.parseEther('0')
            },
            performance: {
                averageCompletionTime: 0,
                successRate: 0,
                nodeUtilization: 0,
                jobThroughput: 0
            }
        };
        
        this.history = {
            blockNumber: [],
            gasPrice: [],
            activeJobs: [],
            successRate: [],
            volume: []
        };
    }
    
    async start() {
        console.log('📊 Starting metrics collection...');
        
        // Initial collection
        await this.collectMetrics();
        
        // Set up intervals
        this.blockInterval = setInterval(() => this.collectBlockchainMetrics(), config.monitoring.blockInterval);
        this.metricsInterval = setInterval(() => this.collectNetworkMetrics(), config.monitoring.metricsInterval);
        
        console.log('   ✅ Metrics collector started');
    }
    
    async collectMetrics() {
        await Promise.all([
            this.collectBlockchainMetrics(),
            this.collectNetworkMetrics(),
            this.collectFinancialMetrics()
        ]);
    }
    
    async collectBlockchainMetrics() {
        try {
            const [block, gasPrice] = await Promise.all([
                this.provider.getBlock('latest'),
                this.provider.getFeeData()
            ]);
            
            this.metrics.blockchain = {
                blockNumber: block.number,
                gasPrice: gasPrice.gasPrice,
                blockTime: block.timestamp
            };
            
            // Update history
            this.updateHistory('blockNumber', block.number);
            this.updateHistory('gasPrice', Number(ethers.formatUnits(gasPrice.gasPrice, 'gwei')));
            
            // Check alerts
            if (gasPrice.gasPrice > config.monitoring.alerts.highGasPrice) {
                this.emit('alert', {
                    type: 'high-gas-price',
                    severity: 'warning',
                    message: `High gas price: ${ethers.formatUnits(gasPrice.gasPrice, 'gwei')} gwei`,
                    value: gasPrice.gasPrice
                });
            }
            
        } catch (error) {
            console.error('Error collecting blockchain metrics:', error);
        }
    }
    
    async collectNetworkMetrics() {
        try {
            // Mock data - in production, query actual contracts
            const activeNodes = Math.floor(Math.random() * 20) + 10;
            const activeJobs = Math.floor(Math.random() * 50) + 20;
            const completedJobs = this.metrics.network.completedJobs + Math.floor(Math.random() * 5);
            const failedJobs = this.metrics.network.failedJobs + (Math.random() > 0.9 ? 1 : 0);
            
            this.metrics.network = {
                totalNodes: activeNodes + Math.floor(Math.random() * 10),
                activeNodes,
                totalJobs: activeJobs + completedJobs + failedJobs,
                activeJobs,
                completedJobs,
                failedJobs
            };
            
            // Calculate performance metrics
            const totalProcessed = completedJobs + failedJobs;
            this.metrics.performance.successRate = totalProcessed > 0 
                ? (completedJobs / totalProcessed) * 100 
                : 100;
            
            this.metrics.performance.nodeUtilization = (activeJobs / (activeNodes * 5)) * 100;
            
            // Update history
            this.updateHistory('activeJobs', activeJobs);
            this.updateHistory('successRate', this.metrics.performance.successRate);
            
            // Check alerts
            if (activeNodes < config.monitoring.alerts.lowNodeCount) {
                this.emit('alert', {
                    type: 'low-node-count',
                    severity: 'critical',
                    message: `Low node count: ${activeNodes} active nodes`,
                    value: activeNodes
                });
            }
            
            if (this.metrics.performance.successRate < (100 - config.monitoring.alerts.highFailureRate * 100)) {
                this.emit('alert', {
                    type: 'high-failure-rate',
                    severity: 'warning',
                    message: `High failure rate: ${(100 - this.metrics.performance.successRate).toFixed(1)}%`,
                    value: this.metrics.performance.successRate
                });
            }
            
        } catch (error) {
            console.error('Error collecting network metrics:', error);
        }
    }
    
    async collectFinancialMetrics() {
        try {
            // Mock financial data
            const newVolume = ethers.parseEther((Math.random() * 10).toFixed(3));
            this.metrics.financial.dailyVolume = this.metrics.financial.dailyVolume + newVolume;
            this.metrics.financial.totalVolume = this.metrics.financial.totalVolume + newVolume;
            
            const jobCount = this.metrics.network.totalJobs || 1;
            this.metrics.financial.averageJobValue = this.metrics.financial.totalVolume / BigInt(jobCount);
            
            // Update history
            this.updateHistory('volume', Number(ethers.formatEther(this.metrics.financial.dailyVolume)));
            
        } catch (error) {
            console.error('Error collecting financial metrics:', error);
        }
    }
    
    updateHistory(metric, value) {
        if (!this.history[metric]) {
            this.history[metric] = [];
        }
        
        this.history[metric].push({
            timestamp: Date.now(),
            value
        });
        
        // Limit history size
        if (this.history[metric].length > config.monitoring.maxDataPoints) {
            this.history[metric].shift();
        }
    }
    
    getMetrics() {
        return {
            ...this.metrics,
            blockchain: {
                ...this.metrics.blockchain,
                gasPrice: ethers.formatUnits(this.metrics.blockchain.gasPrice, 'gwei') + ' gwei'
            },
            financial: {
                totalVolume: ethers.formatEther(this.metrics.financial.totalVolume) + ' ETH',
                averageJobValue: ethers.formatEther(this.metrics.financial.averageJobValue) + ' ETH',
                escrowBalance: ethers.formatEther(this.metrics.financial.escrowBalance) + ' ETH',
                dailyVolume: ethers.formatEther(this.metrics.financial.dailyVolume) + ' ETH'
            }
        };
    }
    
    getHistory(metric) {
        return this.history[metric] || [];
    }
    
    // Prometheus-compatible metrics
    getPrometheusMetrics() {
        const lines = [
            '# HELP fabstir_block_number Current block number',
            '# TYPE fabstir_block_number gauge',
            `fabstir_block_number ${this.metrics.blockchain.blockNumber}`,
            '',
            '# HELP fabstir_gas_price Current gas price in gwei',
            '# TYPE fabstir_gas_price gauge',
            `fabstir_gas_price ${ethers.formatUnits(this.metrics.blockchain.gasPrice, 'gwei')}`,
            '',
            '# HELP fabstir_active_nodes Number of active nodes',
            '# TYPE fabstir_active_nodes gauge',
            `fabstir_active_nodes ${this.metrics.network.activeNodes}`,
            '',
            '# HELP fabstir_active_jobs Number of active jobs',
            '# TYPE fabstir_active_jobs gauge',
            `fabstir_active_jobs ${this.metrics.network.activeJobs}`,
            '',
            '# HELP fabstir_success_rate Job success rate percentage',
            '# TYPE fabstir_success_rate gauge',
            `fabstir_success_rate ${this.metrics.performance.successRate}`,
            '',
            '# HELP fabstir_daily_volume Daily transaction volume in ETH',
            '# TYPE fabstir_daily_volume counter',
            `fabstir_daily_volume ${ethers.formatEther(this.metrics.financial.dailyVolume)}`
        ];
        
        return lines.join('\n');
    }
}

// Alert manager
class AlertManager extends EventEmitter {
    constructor() {
        super();
        this.alerts = [];
        this.activeAlerts = new Map();
    }
    
    addAlert(alert) {
        const id = `${alert.type}-${Date.now()}`;
        const fullAlert = {
            id,
            ...alert,
            timestamp: Date.now(),
            acknowledged: false
        };
        
        this.alerts.push(fullAlert);
        this.activeAlerts.set(id, fullAlert);
        
        // Limit alert history
        if (this.alerts.length > 100) {
            const removed = this.alerts.shift();
            this.activeAlerts.delete(removed.id);
        }
        
        this.emit('new-alert', fullAlert);
        
        // Auto-clear after 5 minutes
        setTimeout(() => {
            if (this.activeAlerts.has(id)) {
                this.clearAlert(id);
            }
        }, 300000);
        
        return id;
    }
    
    acknowledgeAlert(id) {
        const alert = this.activeAlerts.get(id);
        if (alert) {
            alert.acknowledged = true;
            this.emit('alert-acknowledged', alert);
        }
    }
    
    clearAlert(id) {
        const alert = this.activeAlerts.get(id);
        if (alert) {
            alert.clearedAt = Date.now();
            this.activeAlerts.delete(id);
            this.emit('alert-cleared', alert);
        }
    }
    
    getActiveAlerts() {
        return Array.from(this.activeAlerts.values());
    }
    
    getAlertHistory() {
        return this.alerts;
    }
}

// Web server
class MonitoringDashboard {
    constructor(metricsCollector, alertManager) {
        this.metrics = metricsCollector;
        this.alerts = alertManager;
        this.app = express();
        this.setupRoutes();
    }
    
    setupRoutes() {
        this.app.use(express.static(path.join(__dirname, 'public')));
        this.app.use(express.json());
        
        // API endpoints
        this.app.get('/api/metrics', (req, res) => {
            res.json(this.metrics.getMetrics());
        });
        
        this.app.get('/api/metrics/history/:metric', (req, res) => {
            const history = this.metrics.getHistory(req.params.metric);
            res.json(history);
        });
        
        this.app.get('/api/alerts', (req, res) => {
            res.json({
                active: this.alerts.getActiveAlerts(),
                history: this.alerts.getAlertHistory()
            });
        });
        
        this.app.post('/api/alerts/:id/acknowledge', (req, res) => {
            this.alerts.acknowledgeAlert(req.params.id);
            res.json({ success: true });
        });
        
        // Prometheus metrics
        this.app.get('/metrics', (req, res) => {
            res.set('Content-Type', 'text/plain');
            res.send(this.metrics.getPrometheusMetrics());
        });
        
        // Dashboard HTML
        this.app.get('/', (req, res) => {
            res.send(this.getDashboardHTML());
        });
    }
    
    getDashboardHTML() {
        return `
<!DOCTYPE html>
<html>
<head>
    <title>Fabstir Monitoring Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 0;
            background: #0f172a;
            color: #e2e8f0;
        }
        .header {
            background: #1e293b;
            padding: 20px;
            border-bottom: 1px solid #334155;
        }
        .header h1 {
            margin: 0;
            color: #f1f5f9;
            font-size: 24px;
        }
        .container {
            padding: 20px;
            max-width: 1400px;
            margin: 0 auto;
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .metric-card {
            background: #1e293b;
            border-radius: 8px;
            padding: 20px;
            border: 1px solid #334155;
        }
        .metric-label {
            color: #94a3b8;
            font-size: 14px;
            margin-bottom: 8px;
        }
        .metric-value {
            font-size: 32px;
            font-weight: bold;
            color: #3b82f6;
        }
        .metric-change {
            font-size: 14px;
            margin-top: 8px;
        }
        .positive { color: #10b981; }
        .negative { color: #ef4444; }
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .chart-container {
            background: #1e293b;
            border-radius: 8px;
            padding: 20px;
            border: 1px solid #334155;
        }
        .chart-title {
            font-size: 18px;
            margin-bottom: 15px;
            color: #f1f5f9;
        }
        .alerts-container {
            background: #1e293b;
            border-radius: 8px;
            padding: 20px;
            border: 1px solid #334155;
        }
        .alert {
            background: #334155;
            border-radius: 6px;
            padding: 15px;
            margin-bottom: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .alert.critical {
            border-left: 4px solid #ef4444;
        }
        .alert.warning {
            border-left: 4px solid #f59e0b;
        }
        .alert-content {
            flex: 1;
        }
        .alert-time {
            color: #94a3b8;
            font-size: 12px;
        }
        .alert-actions {
            display: flex;
            gap: 10px;
        }
        .btn {
            background: #3b82f6;
            color: white;
            border: none;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
        }
        .btn:hover {
            background: #2563eb;
        }
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-healthy { background: #10b981; }
        .status-warning { background: #f59e0b; }
        .status-critical { background: #ef4444; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 Fabstir Network Monitor</h1>
    </div>
    
    <div class="container">
        <!-- Key Metrics -->
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-label">Block Number</div>
                <div class="metric-value" id="blockNumber">-</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Gas Price</div>
                <div class="metric-value" id="gasPrice">-</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Active Nodes</div>
                <div class="metric-value" id="activeNodes">-</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Active Jobs</div>
                <div class="metric-value" id="activeJobs">-</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Success Rate</div>
                <div class="metric-value" id="successRate">-</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Daily Volume</div>
                <div class="metric-value" id="dailyVolume">-</div>
            </div>
        </div>
        
        <!-- Charts -->
        <div class="charts-grid">
            <div class="chart-container">
                <div class="chart-title">Active Jobs Trend</div>
                <canvas id="jobsChart"></canvas>
            </div>
            <div class="chart-container">
                <div class="chart-title">Success Rate Trend</div>
                <canvas id="successChart"></canvas>
            </div>
        </div>
        
        <!-- Alerts -->
        <div class="alerts-container">
            <h2>Active Alerts</h2>
            <div id="alertsList"></div>
        </div>
    </div>
    
    <script>
        // WebSocket connection
        const ws = new WebSocket('ws://localhost:3001');
        
        // Chart setup
        const chartOptions = {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false }
            },
            scales: {
                x: { 
                    grid: { color: '#334155' },
                    ticks: { color: '#94a3b8' }
                },
                y: { 
                    grid: { color: '#334155' },
                    ticks: { color: '#94a3b8' }
                }
            }
        };
        
        const jobsChart = new Chart(document.getElementById('jobsChart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#3b82f6',
                    backgroundColor: 'rgba(59, 130, 246, 0.1)',
                    tension: 0.4
                }]
            },
            options: { ...chartOptions, scales: { ...chartOptions.scales } }
        });
        
        const successChart = new Chart(document.getElementById('successChart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#10b981',
                    backgroundColor: 'rgba(16, 185, 129, 0.1)',
                    tension: 0.4
                }]
            },
            options: { ...chartOptions, scales: { ...chartOptions.scales, y: { ...chartOptions.scales.y, max: 100 } } }
        });
        
        // Update functions
        async function updateMetrics() {
            try {
                const response = await fetch('/api/metrics');
                const metrics = await response.json();
                
                document.getElementById('blockNumber').textContent = metrics.blockchain.blockNumber.toLocaleString();
                document.getElementById('gasPrice').textContent = metrics.blockchain.gasPrice;
                document.getElementById('activeNodes').textContent = metrics.network.activeNodes;
                document.getElementById('activeJobs').textContent = metrics.network.activeJobs;
                document.getElementById('successRate').textContent = metrics.performance.successRate.toFixed(1) + '%';
                document.getElementById('dailyVolume').textContent = metrics.financial.dailyVolume;
            } catch (error) {
                console.error('Error updating metrics:', error);
            }
        }
        
        async function updateHistory() {
            try {
                // Update jobs chart
                const jobsResponse = await fetch('/api/metrics/history/activeJobs');
                const jobsHistory = await jobsResponse.json();
                
                if (jobsHistory.length > 0) {
                    const labels = jobsHistory.slice(-30).map(h => new Date(h.timestamp).toLocaleTimeString());
                    const data = jobsHistory.slice(-30).map(h => h.value);
                    
                    jobsChart.data.labels = labels;
                    jobsChart.data.datasets[0].data = data;
                    jobsChart.update();
                }
                
                // Update success rate chart
                const successResponse = await fetch('/api/metrics/history/successRate');
                const successHistory = await successResponse.json();
                
                if (successHistory.length > 0) {
                    const labels = successHistory.slice(-30).map(h => new Date(h.timestamp).toLocaleTimeString());
                    const data = successHistory.slice(-30).map(h => h.value);
                    
                    successChart.data.labels = labels;
                    successChart.data.datasets[0].data = data;
                    successChart.update();
                }
            } catch (error) {
                console.error('Error updating history:', error);
            }
        }
        
        async function updateAlerts() {
            try {
                const response = await fetch('/api/alerts');
                const { active } = await response.json();
                
                const alertsList = document.getElementById('alertsList');
                if (active.length === 0) {
                    alertsList.innerHTML = '<p style="color: #94a3b8;">No active alerts</p>';
                } else {
                    alertsList.innerHTML = active.map(alert => `
                        <div class="alert ${alert.severity}">
                            <div class="alert-content">
                                <div>${alert.message}</div>
                                <div class="alert-time">${new Date(alert.timestamp).toLocaleString()}</div>
                            </div>
                            <div class="alert-actions">
                                ${!alert.acknowledged ? 
                                    `<button class="btn" onclick="acknowledgeAlert('${alert.id}')">Acknowledge</button>` : 
                                    '<span style="color: #94a3b8;">Acknowledged</span>'
                                }
                            </div>
                        </div>
                    `).join('');
                }
            } catch (error) {
                console.error('Error updating alerts:', error);
            }
        }
        
        async function acknowledgeAlert(id) {
            try {
                await fetch(`/api/alerts/${id}/acknowledge`, { method: 'POST' });
                updateAlerts();
            } catch (error) {
                console.error('Error acknowledging alert:', error);
            }
        }
        
        // WebSocket handlers
        ws.onmessage = (event) => {
            const message = JSON.parse(event.data);
            
            switch (message.type) {
                case 'metrics-update':
                    updateMetrics();
                    updateHistory();
                    break;
                case 'new-alert':
                    updateAlerts();
                    if (Notification.permission === 'granted') {
                        new Notification('Fabstir Alert', {
                            body: message.data.message,
                            icon: '/favicon.ico'
                        });
                    }
                    break;
            }
        };
        
        // Initial load and periodic updates
        updateMetrics();
        updateHistory();
        updateAlerts();
        
        setInterval(updateMetrics, 5000);
        setInterval(updateHistory, 10000);
        setInterval(updateAlerts, 5000);
        
        // Request notification permission
        if (Notification.permission === 'default') {
            Notification.requestPermission();
        }
    </script>
</body>
</html>
        `;
    }
    
    start(port) {
        this.app.listen(port, () => {
            console.log(`   🌐 Dashboard running at http://localhost:${port}`);
        });
    }
}

// WebSocket server for real-time updates
class MonitoringWebSocket {
    constructor(metricsCollector, alertManager) {
        this.metrics = metricsCollector;
        this.alerts = alertManager;
        this.wss = new WebSocket.Server({ port: config.monitoring.wsPort });
        this.clients = new Set();
        
        this.setupWebSocket();
        this.setupEventHandlers();
    }
    
    setupWebSocket() {
        this.wss.on('connection', (ws) => {
            this.clients.add(ws);
            console.log('   🔌 New dashboard client connected');
            
            ws.on('close', () => {
                this.clients.delete(ws);
            });
            
            ws.on('error', (error) => {
                console.error('WebSocket error:', error);
                this.clients.delete(ws);
            });
        });
        
        console.log(`   🔌 WebSocket server on port ${config.monitoring.wsPort}`);
    }
    
    setupEventHandlers() {
        // Forward alerts
        this.alerts.on('new-alert', (alert) => {
            this.broadcast({
                type: 'new-alert',
                data: alert
            });
        });
        
        // Periodic metrics updates
        setInterval(() => {
            this.broadcast({
                type: 'metrics-update',
                data: this.metrics.getMetrics()
            });
        }, config.dashboard.refreshInterval);
    }
    
    broadcast(message) {
        const data = JSON.stringify(message);
        this.clients.forEach(client => {
            if (client.readyState === WebSocket.OPEN) {
                client.send(data);
            }
        });
    }
}

// Main monitoring system
async function main() {
    try {
        console.log('📡 Fabstir Monitoring Dashboard\n');
        console.log('━'.repeat(50));
        
        // Setup
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        
        // Initialize contracts (read-only)
        const contracts = {};
        for (const [name, address] of Object.entries(config.contracts)) {
            if (address && CONTRACT_ABIS[name.charAt(0).toUpperCase() + name.slice(1)]) {
                contracts[name] = new ethers.Contract(
                    address,
                    CONTRACT_ABIS[name.charAt(0).toUpperCase() + name.slice(1)],
                    provider
                );
            }
        }
        
        console.log('Network:', config.chainId === 8453 ? 'Base Mainnet' : 'Base Sepolia');
        console.log('━'.repeat(50) + '\n');
        
        // Create components
        const metricsCollector = new MetricsCollector(provider, contracts);
        const alertManager = new AlertManager();
        const dashboard = new MonitoringDashboard(metricsCollector, alertManager);
        const websocket = new MonitoringWebSocket(metricsCollector, alertManager);
        
        // Set up alert forwarding
        metricsCollector.on('alert', (alert) => {
            alertManager.addAlert(alert);
        });
        
        // Start services
        await metricsCollector.start();
        dashboard.start(config.monitoring.httpPort);
        
        // Prometheus metrics endpoint
        const metricsApp = express();
        metricsApp.get('/metrics', (req, res) => {
            res.set('Content-Type', 'text/plain');
            res.send(metricsCollector.getPrometheusMetrics());
        });
        metricsApp.listen(config.monitoring.metricsPort, () => {
            console.log(`   📊 Prometheus metrics at http://localhost:${config.monitoring.metricsPort}/metrics`);
        });
        
        console.log('\n✅ Monitoring system running!');
        console.log(`   🌐 Dashboard: http://localhost:${config.monitoring.httpPort}`);
        console.log(`   📊 API: http://localhost:${config.monitoring.httpPort}/api/metrics`);
        console.log(`   🔌 WebSocket: ws://localhost:${config.monitoring.wsPort}`);
        console.log('\n📈 Collection intervals:');
        console.log(`   • Blockchain: ${config.monitoring.blockInterval / 1000}s`);
        console.log(`   • Network: ${config.monitoring.metricsInterval / 1000}s`);
        console.log(`   • Health checks: ${config.monitoring.healthCheckInterval / 1000}s`);
        
        // Display sample metrics periodically
        setInterval(() => {
            const metrics = metricsCollector.getMetrics();
            console.log(`\n📊 Metrics Snapshot - ${new Date().toLocaleTimeString()}`);
            console.log(`   Block: #${metrics.blockchain.blockNumber} | Gas: ${metrics.blockchain.gasPrice}`);
            console.log(`   Nodes: ${metrics.network.activeNodes} active | Jobs: ${metrics.network.activeJobs} active`);
            console.log(`   Success rate: ${metrics.performance.successRate.toFixed(1)}% | Volume: ${metrics.financial.dailyVolume}`);
        }, 60000);
        
        console.log('\nPress Ctrl+C to stop\n');
        
    } catch (error) {
        console.error('❌ Error:', error.message);
        process.exit(1);
    }
}

// Execute if run directly
if (require.main === module) {
    main();
}

// Export for use in other modules
module.exports = {
    MetricsCollector,
    AlertManager,
    MonitoringDashboard,
    MonitoringWebSocket,
    config
};

/**
 * Expected Output:
 * 
 * 📡 Fabstir Monitoring Dashboard
 * ══════════════════════════════════════════════════
 * Network: Base Mainnet
 * ══════════════════════════════════════════════════
 * 
 * 📊 Starting metrics collection...
 *    ✅ Metrics collector started
 *    🌐 Dashboard running at http://localhost:3000
 *    🔌 WebSocket server on port 3001
 *    📊 Prometheus metrics at http://localhost:9090/metrics
 * 
 * ✅ Monitoring system running!
 *    🌐 Dashboard: http://localhost:3000
 *    📊 API: http://localhost:3000/api/metrics
 *    🔌 WebSocket: ws://localhost:3001
 * 
 * 📈 Collection intervals:
 *    • Blockchain: 5s
 *    • Network: 10s
 *    • Health checks: 30s
 * 
 *    🔌 New dashboard client connected
 * 
 * 📊 Metrics Snapshot - 11:45:30 AM
 *    Block: #12,456,789 | Gas: 35.5 gwei
 *    Nodes: 18 active | Jobs: 34 active
 *    Success rate: 97.8% | Volume: 156.78 ETH
 * 
 * Press Ctrl+C to stop
 * 
 * [Dashboard shows real-time metrics with charts and alerts]
 */