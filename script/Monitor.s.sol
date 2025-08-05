// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/utils/MonitoringHelper.sol";
import "../src/utils/HealthMonitor.sol";
import "../src/utils/MetricsCollector.sol";
import "../src/utils/SecurityMonitor.sol";
import "../src/NodeRegistry.sol";
import "../src/JobMarketplace.sol";
import "../src/PaymentEscrow.sol";
import "../src/ReputationSystem.sol";
import "../src/ProofSystem.sol";

contract MonitorScript is Script {
    MonitoringHelper public monitoringHelper;
    HealthMonitor public healthMonitor;
    MetricsCollector public metricsCollector;
    SecurityMonitor public securityMonitor;
    
    address[] public contractsToMonitor;
    
    struct MonitoringConfig {
        uint256 healthCheckInterval;
        uint256 metricsInterval;
        uint256 reportInterval;
        bool alertsEnabled;
        string webhookUrl;
    }
    
    MonitoringConfig public config = MonitoringConfig({
        healthCheckInterval: 5 minutes,
        metricsInterval: 1 hours,
        reportInterval: 24 hours,
        alertsEnabled: true,
        webhookUrl: ""
    });
    
    function setUp() public {
        monitoringHelper = new MonitoringHelper();
        healthMonitor = new HealthMonitor(address(monitoringHelper));
        metricsCollector = new MetricsCollector(address(monitoringHelper));
        securityMonitor = new SecurityMonitor(address(monitoringHelper));
    }
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        address nodeRegistry = vm.envAddress("NODE_REGISTRY");
        address jobMarketplace = vm.envAddress("JOB_MARKETPLACE");
        address paymentEscrow = vm.envAddress("PAYMENT_ESCROW");
        address reputationSystem = vm.envAddress("REPUTATION_SYSTEM");
        address proofSystem = vm.envAddress("PROOF_SYSTEM");
        
        contractsToMonitor.push(nodeRegistry);
        contractsToMonitor.push(jobMarketplace);
        contractsToMonitor.push(paymentEscrow);
        contractsToMonitor.push(reputationSystem);
        contractsToMonitor.push(proofSystem);
        
        _setupAlerts();
        
        _performHealthChecks();
        _collectMetrics(nodeRegistry, jobMarketplace, paymentEscrow);
        _generateDailyReport();
        
        vm.stopBroadcast();
    }
    
    function monitor() external {
        _performHealthChecks();
        
        address nodeRegistry = contractsToMonitor[0];
        address jobMarketplace = contractsToMonitor[1];
        address paymentEscrow = contractsToMonitor[2];
        
        _collectMetrics(nodeRegistry, jobMarketplace, paymentEscrow);
        
        _checkAlerts();
        
        if (block.timestamp % config.reportInterval == 0) {
            _generateDailyReport();
        }
    }
    
    function generateReport(string memory reportType) external returns (uint256 reportId) {
        if (keccak256(bytes(reportType)) == keccak256(bytes("daily"))) {
            return _generateDailyReport();
        } else if (keccak256(bytes(reportType)) == keccak256(bytes("weekly"))) {
            return _generateWeeklyReport();
        } else if (keccak256(bytes(reportType)) == keccak256(bytes("custom"))) {
            string[] memory metrics = new string[](3);
            metrics[0] = "activeNodes";
            metrics[1] = "completedJobs";
            metrics[2] = "totalVolume";
            return _generateCustomReport(block.number - 7200, block.number, metrics);
        }
        
        revert("Unknown report type");
    }
    
    function exportMetrics(string memory format) external view returns (string memory) {
        if (keccak256(bytes(format)) == keccak256(bytes("prometheus"))) {
            return metricsCollector.exportPrometheusFormat();
        } else if (keccak256(bytes(format)) == keccak256(bytes("json"))) {
            return _exportJsonFormat();
        }
        
        revert("Unknown export format");
    }
    
    function _setupAlerts() private {
        monitoringHelper.configureAlert("high_gas", 500000, 1 hours, true);
        monitoringHelper.configureAlert("low_nodes", 5, 30 minutes, true);
        monitoringHelper.configureAlert("job_failures", 10, 1 hours, true);
        monitoringHelper.configureAlert("suspicious_activity", 1, 5 minutes, true);
    }
    
    function _performHealthChecks() private {
        for (uint256 i = 0; i < contractsToMonitor.length; i++) {
            MonitoringHelper.HealthStatus memory status = healthMonitor.checkHealth(
                contractsToMonitor[i]
            );
            
            if (keccak256(bytes(status.status)) != keccak256(bytes("healthy"))) {
                _sendAlert("health", contractsToMonitor[i], status.status);
            }
        }
    }
    
    function _collectMetrics(
        address nodeRegistry,
        address jobMarketplace,
        address paymentEscrow
    ) private {
        metricsCollector.collectMetrics(nodeRegistry, jobMarketplace, paymentEscrow);
        
        uint256 avgResponseTime = _measureResponseTime(jobMarketplace);
        uint256 throughput = _measureThroughput(jobMarketplace);
        
        metricsCollector.recordPerformanceMetric(
            jobMarketplace,
            avgResponseTime,
            throughput,
            true
        );
    }
    
    function _checkAlerts() private {
        (uint256 avgGas, , , , , , ) = monitoringHelper.metrics(
            monitoringHelper.currentMetricId()
        );
        
        monitoringHelper.checkAlert("high_gas", avgGas, 500000);
        
        uint256 activeNodes = metricsCollector.getAverageMetric("activeNodes", 1);
        monitoringHelper.checkAlert("low_nodes", activeNodes, 5);
        
        _checkAnomalies();
    }
    
    function _checkAnomalies() private {
        string[4] memory metrics = ["activeNodes", "activeJobs", "completedJobs", "totalVolume"];
        
        for (uint256 i = 0; i < metrics.length; i++) {
            uint256 current = metricsCollector.getAverageMetric(metrics[i], 1);
            uint256 historical = metricsCollector.getAverageMetric(metrics[i], 24);
            
            monitoringHelper.detectAnomaly(metrics[i], historical, current);
        }
    }
    
    function _generateDailyReport() private returns (uint256) {
        uint256 reportId = uint256(keccak256(abi.encode(block.timestamp, "daily")));
        
        console.log("=== Daily Monitoring Report ===");
        console.log("Report ID:", reportId);
        console.log("Timestamp:", block.timestamp);
        
        for (uint256 i = 0; i < contractsToMonitor.length; i++) {
            uint256 health = healthMonitor.healthScore(contractsToMonitor[i]);
            console.log("Contract Health:", contractsToMonitor[i], health);
        }
        
        return reportId;
    }
    
    function _generateWeeklyReport() private returns (uint256) {
        uint256 reportId = uint256(keccak256(abi.encode(block.timestamp, "weekly")));
        
        console.log("=== Weekly Monitoring Report ===");
        console.log("Report ID:", reportId);
        
        string[4] memory metrics = ["activeNodes", "activeJobs", "completedJobs", "totalVolume"];
        
        for (uint256 i = 0; i < metrics.length; i++) {
            int256 trend = metricsCollector.getTrend(metrics[i], 168);
            console.log("Metric Trend:");
            console.log(metrics[i]);
            console.logInt(trend);
        }
        
        return reportId;
    }
    
    function _generateCustomReport(
        uint256 fromBlock,
        uint256 toBlock,
        string[] memory metrics
    ) private returns (uint256) {
        uint256 reportId = uint256(keccak256(abi.encode(fromBlock, toBlock, metrics)));
        
        console.log("=== Custom Report ===");
        console.log("Report ID:", reportId);
        console.log("Blocks:", fromBlock, "-", toBlock);
        
        for (uint256 i = 0; i < metrics.length; i++) {
            uint256 value = metricsCollector.getAverageMetric(metrics[i], 24);
            console.log("Metric:", metrics[i], value);
        }
        
        return reportId;
    }
    
    function _measureResponseTime(address target) private returns (uint256) {
        uint256 startGas = gasleft();
        
        (bool success, ) = target.call(abi.encodeWithSignature("getActiveJobCount()"));
        require(success, "Call failed");
        
        return startGas - gasleft();
    }
    
    function _measureThroughput(address target) private view returns (uint256) {
        (
            uint256 transactionCount,
            ,
            ,
            ,
            ,
            uint256 lastActivityTime
        ) = monitoringHelper.contractMetrics(target);
        
        if (lastActivityTime == 0) return 0;
        
        uint256 timeDiff = block.timestamp - lastActivityTime;
        if (timeDiff == 0) return transactionCount;
        
        return (transactionCount * 3600) / timeDiff;
    }
    
    function _sendAlert(string memory alertType, address target, string memory message) private {
        if (!config.alertsEnabled) return;
        
        console.log("ALERT:", alertType, target, message);
        
        if (bytes(config.webhookUrl).length > 0) {
            // In production, this would send to webhook
            console.log("Webhook notification sent to:", config.webhookUrl);
        }
    }
    
    function _exportJsonFormat() private view returns (string memory) {
        return string(abi.encodePacked(
            "{",
            '"timestamp":', _uint2str(block.timestamp), ",",
            '"activeNodes":', _uint2str(metricsCollector.getAverageMetric("activeNodes", 1)), ",",
            '"activeJobs":', _uint2str(metricsCollector.getAverageMetric("activeJobs", 1)), ",",
            '"systemHealth":', _uint2str(healthMonitor.getSystemHealth(contractsToMonitor)),
            "}"
        ));
    }
    
    function _uint2str(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        
        uint256 temp = value;
        uint256 digits;
        
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
}