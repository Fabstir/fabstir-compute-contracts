// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/INodeRegistry.sol";
import "../interfaces/IJobMarketplace.sol";
import "../interfaces/IPaymentEscrow.sol";
import "../interfaces/IReputationSystem.sol";

contract MonitoringHelper {
    struct HealthStatus {
        bool isOperational;
        uint256 lastBlockProcessed;
        uint256 pendingTransactions;
        uint256 errorCount;
        string status;
    }

    struct MetricSnapshot {
        uint256 timestamp;
        uint256 activeNodes;
        uint256 activeJobs;
        uint256 completedJobs;
        uint256 totalVolume;
        uint256 averageGasPrice;
        uint256 averageJobDuration;
    }

    struct AlertConfig {
        uint256 threshold;
        uint256 cooldownPeriod;
        bool enabled;
        address[] recipients;
        string alertType;
    }

    struct ContractMetrics {
        uint256 transactionCount;
        uint256 uniqueUsers;
        uint256 totalGasUsed;
        uint256 averageGasPerTx;
        uint256 failureRate;
        uint256 lastActivityTime;
    }

    struct SecurityAlert {
        uint256 timestamp;
        address target;
        string alertType;
        string severity;
        bytes data;
        bool resolved;
    }

    mapping(address => HealthStatus) public contractHealth;
    mapping(uint256 => MetricSnapshot) public metrics;
    mapping(string => AlertConfig) public alertConfigs;
    mapping(address => ContractMetrics) public contractMetrics;
    mapping(uint256 => SecurityAlert) public securityAlerts;
    
    mapping(string => uint256) public lastAlertTime;
    mapping(address => uint256) public lastTxTime;
    mapping(address => uint256) public txCount;
    
    uint256 public currentMetricId;
    uint256 public currentAlertId;
    
    uint256 private constant ANOMALY_THRESHOLD = 200; // 200% deviation
    uint256 private constant RATE_WINDOW = 1 hours;
    
    event HealthCheckPerformed(
        address indexed contract_,
        string status,
        uint256 errorCount
    );
    
    event MetricsCollected(
        uint256 indexed timestamp,
        uint256 activeNodes,
        uint256 activeJobs,
        uint256 totalVolume
    );
    
    event AlertTriggered(
        string indexed alertType,
        string severity,
        uint256 value,
        uint256 threshold
    );
    
    event AnomalyDetected(
        string indexed metricType,
        uint256 expectedValue,
        uint256 actualValue,
        uint256 deviation
    );

    function performHealthCheck(address target) external returns (HealthStatus memory) {
        HealthStatus memory status;
        
        status.isOperational = _isContractDeployed(target);
        status.lastBlockProcessed = block.number;
        
        if (!status.isOperational) {
            status.status = "critical";
            status.errorCount = 1;
        } else if (_isPaused(target)) {
            status.status = "degraded";
            status.errorCount = 1;
        } else {
            status.status = "healthy";
            status.errorCount = 0;
        }
        
        contractHealth[target] = status;
        emit HealthCheckPerformed(target, status.status, status.errorCount);
        
        return status;
    }

    function collectMetrics(
        address nodeRegistry,
        address jobMarketplace,
        address paymentEscrow
    ) external returns (uint256) {
        MetricSnapshot memory snapshot;
        
        snapshot.timestamp = block.timestamp;
        snapshot.activeNodes = _getActiveNodeCount(nodeRegistry);
        snapshot.activeJobs = _getActiveJobCount(jobMarketplace);
        snapshot.completedJobs = _getCompletedJobCount(jobMarketplace);
        snapshot.totalVolume = _getTotalVolume(paymentEscrow);
        snapshot.averageGasPrice = tx.gasprice;
        snapshot.averageJobDuration = _getAverageJobDuration();
        
        currentMetricId++;
        metrics[currentMetricId] = snapshot;
        
        emit MetricsCollected(
            snapshot.timestamp,
            snapshot.activeNodes,
            snapshot.activeJobs,
            snapshot.totalVolume
        );
        
        return currentMetricId;
    }

    function checkAlert(
        string memory alertType,
        uint256 value,
        uint256 threshold
    ) external returns (bool triggered) {
        AlertConfig storage config = alertConfigs[alertType];
        
        
        if (!config.enabled) {
            return false;
        }
        
        if (value > config.threshold) {
            uint256 lastAlert = lastAlertTime[alertType];
            
            // Allow first alert or if cooldown has passed
            if (lastAlert == 0 || block.timestamp >= lastAlert + config.cooldownPeriod) {
                lastAlertTime[alertType] = block.timestamp;
                emit AlertTriggered(alertType, "high", value, config.threshold);
                return true;
            }
            return false; // Cooldown not passed
        }
        
        return false; // Value not greater than threshold
    }

    function detectAnomaly(
        string memory metricType,
        uint256 expectedValue,
        uint256 actualValue
    ) external returns (bool) {
        if (expectedValue == 0) return false;
        
        uint256 deviation = actualValue > expectedValue 
            ? ((actualValue - expectedValue) * 100) / expectedValue
            : ((expectedValue - actualValue) * 100) / expectedValue;
            
        if (deviation > ANOMALY_THRESHOLD) {
            emit AnomalyDetected(metricType, expectedValue, actualValue, deviation);
            return true;
        }
        
        return false;
    }

    function trackTransaction(address target) external {
        lastTxTime[target] = block.timestamp;
        txCount[target]++;
        
        ContractMetrics storage cm = contractMetrics[target];
        cm.transactionCount++;
        cm.lastActivityTime = block.timestamp;
        cm.totalGasUsed += gasleft();
        cm.averageGasPerTx = cm.totalGasUsed / cm.transactionCount;
    }

    function recordSecurityAlert(
        address target,
        string memory alertType,
        string memory severity,
        bytes memory data
    ) external returns (uint256) {
        currentAlertId++;
        
        securityAlerts[currentAlertId] = SecurityAlert({
            timestamp: block.timestamp,
            target: target,
            alertType: alertType,
            severity: severity,
            data: data,
            resolved: false
        });
        
        emit AlertTriggered(alertType, severity, 0, 0);
        
        return currentAlertId;
    }

    function configureAlert(
        string memory alertType,
        uint256 threshold,
        uint256 cooldownPeriod,
        bool enabled
    ) external {
        alertConfigs[alertType] = AlertConfig({
            threshold: threshold,
            cooldownPeriod: cooldownPeriod,
            enabled: enabled,
            recipients: new address[](0),
            alertType: alertType
        });
    }
    
    function getAlertConfig(string memory alertType) external view returns (uint256 threshold, bool enabled) {
        AlertConfig memory config = alertConfigs[alertType];
        return (config.threshold, config.enabled);
    }

    function _isContractDeployed(address target) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(target)
        }
        return size > 0;
    }

    function _isPaused(address target) private view returns (bool) {
        (bool success, bytes memory data) = target.staticcall(
            abi.encodeWithSignature("isPaused()")
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (bool));
        }
        
        (success, data) = target.staticcall(
            abi.encodeWithSignature("paused()")
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (bool));
        }
        
        return false;
    }

    function _getActiveNodeCount(address nodeRegistry) private view returns (uint256) {
        (bool success, bytes memory data) = nodeRegistry.staticcall(
            abi.encodeWithSignature("getActiveNodeCount()")
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (uint256));
        }
        
        return 0;
    }

    function _getActiveJobCount(address jobMarketplace) private view returns (uint256) {
        (bool success, bytes memory data) = jobMarketplace.staticcall(
            abi.encodeWithSignature("getActiveJobCount()")
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (uint256));
        }
        
        return 0;
    }

    function _getCompletedJobCount(address jobMarketplace) private view returns (uint256) {
        (bool success, bytes memory data) = jobMarketplace.staticcall(
            abi.encodeWithSignature("getCompletedJobCount()")
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (uint256));
        }
        
        return 0;
    }

    function _getTotalVolume(address paymentEscrow) private view returns (uint256) {
        (bool success, bytes memory data) = paymentEscrow.staticcall(
            abi.encodeWithSignature("getTotalVolume()")
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (uint256));
        }
        
        return 0;
    }

    function _getAverageJobDuration() private pure returns (uint256) {
        return 3 hours;
    }
}