// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./MonitoringHelper.sol";

contract MetricsCollector {
    MonitoringHelper public monitoringHelper;
    
    struct MetricHistory {
        uint256[] values;
        uint256[] timestamps;
    }
    
    struct PerformanceMetrics {
        uint256 responseTime;
        uint256 throughput;
        uint256 successRate;
        uint256 errorRate;
    }
    
    mapping(string => MetricHistory) internal metricHistories;
    mapping(address => PerformanceMetrics) public performanceMetrics;
    mapping(uint256 => MonitoringHelper.MetricSnapshot) public snapshots;
    
    uint256 public currentSnapshotId;
    uint256 public collectionInterval = 1 hours;
    uint256 public lastCollectionTime;
    
    uint256 private constant MAX_HISTORY_SIZE = 168;
    
    event MetricsAggregated(
        uint256 indexed snapshotId,
        uint256 timestamp,
        uint256 metricsCount
    );
    
    event PerformanceMetricRecorded(
        address indexed contract_,
        uint256 responseTime,
        uint256 throughput
    );
    
    constructor(address _monitoringHelper) {
        monitoringHelper = MonitoringHelper(_monitoringHelper);
    }
    
    function collectMetrics(
        address nodeRegistry,
        address jobMarketplace,
        address paymentEscrow
    ) external returns (uint256) {
        require(
            block.timestamp >= lastCollectionTime + collectionInterval,
            "Collection too soon"
        );
        
        lastCollectionTime = block.timestamp;
        currentSnapshotId++;
        
        uint256 metricId = monitoringHelper.collectMetrics(
            nodeRegistry,
            jobMarketplace,
            paymentEscrow
        );
        
        (
            ,
            uint256 activeNodes,
            uint256 activeJobs,
            uint256 completedJobs,
            uint256 totalVolume,
            ,
        ) = monitoringHelper.metrics(metricId);
        
        _recordMetric("activeNodes", activeNodes);
        _recordMetric("activeJobs", activeJobs);
        _recordMetric("completedJobs", completedJobs);
        _recordMetric("totalVolume", totalVolume);
        
        emit MetricsAggregated(currentSnapshotId, block.timestamp, 4);
        
        return currentSnapshotId;
    }
    
    function recordPerformanceMetric(
        address target,
        uint256 responseTime,
        uint256 throughput,
        bool success
    ) external {
        PerformanceMetrics storage pm = performanceMetrics[target];
        
        pm.responseTime = (pm.responseTime * 9 + responseTime) / 10;
        pm.throughput = (pm.throughput * 9 + throughput) / 10;
        
        if (success) {
            pm.successRate = (pm.successRate * 99 + 100) / 100;
            pm.errorRate = (pm.errorRate * 99) / 100;
        } else {
            pm.successRate = (pm.successRate * 99) / 100;
            pm.errorRate = (pm.errorRate * 99 + 100) / 100;
        }
        
        emit PerformanceMetricRecorded(target, responseTime, throughput);
    }
    
    function getHistoricalMetrics(string memory metricName, uint256 hoursBack) 
        external 
        view 
        returns (uint256[] memory values, uint256[] memory timestamps) 
    {
        MetricHistory storage history = metricHistories[metricName];
        uint256 count = history.values.length;
        
        if (count == 0 || hoursBack == 0) {
            return (new uint256[](0), new uint256[](0));
        }
        
        uint256 start = count > hoursBack ? count - hoursBack : 0;
        uint256 size = count - start;
        
        values = new uint256[](size);
        timestamps = new uint256[](size);
        
        for (uint256 i = 0; i < size; i++) {
            values[i] = history.values[start + i];
            timestamps[i] = history.timestamps[start + i];
        }
    }
    
    function getAverageMetric(string memory metricName, uint256 hoursBack) 
        external 
        view 
        returns (uint256) 
    {
        (uint256[] memory values, ) = this.getHistoricalMetrics(metricName, hoursBack);
        
        if (values.length == 0) return 0;
        
        uint256 sum;
        for (uint256 i = 0; i < values.length; i++) {
            sum += values[i];
        }
        
        return sum / values.length;
    }
    
    function getTrend(string memory metricName, uint256 hoursBack) 
        external 
        view 
        returns (int256) 
    {
        (uint256[] memory values, ) = this.getHistoricalMetrics(metricName, hoursBack);
        
        if (values.length < 2) return 0;
        
        uint256 firstHalf;
        uint256 secondHalf;
        uint256 midpoint = values.length / 2;
        
        for (uint256 i = 0; i < midpoint; i++) {
            firstHalf += values[i];
        }
        
        for (uint256 i = midpoint; i < values.length; i++) {
            secondHalf += values[i];
        }
        
        firstHalf = firstHalf / midpoint;
        secondHalf = secondHalf / (values.length - midpoint);
        
        if (secondHalf > firstHalf) {
            return int256((secondHalf - firstHalf) * 100 / firstHalf);
        } else {
            return -int256((firstHalf - secondHalf) * 100 / firstHalf);
        }
    }
    
    function exportPrometheusFormat() external view returns (string memory) {
        return string(abi.encodePacked(
            "# HELP active_nodes Number of active nodes\n",
            "# TYPE active_nodes gauge\n",
            "active_nodes ",
            _uint2str(_getLatestMetric("activeNodes")),
            "\n",
            "# HELP active_jobs Number of active jobs\n", 
            "# TYPE active_jobs gauge\n",
            "active_jobs ",
            _uint2str(_getLatestMetric("activeJobs")),
            "\n"
        ));
    }
    
    function _recordMetric(string memory name, uint256 value) private {
        MetricHistory storage history = metricHistories[name];
        
        history.values.push(value);
        history.timestamps.push(block.timestamp);
        
        if (history.values.length > MAX_HISTORY_SIZE) {
            for (uint256 i = 0; i < history.values.length - 1; i++) {
                history.values[i] = history.values[i + 1];
                history.timestamps[i] = history.timestamps[i + 1];
            }
            history.values.pop();
            history.timestamps.pop();
        }
    }
    
    function _getLatestMetric(string memory name) private view returns (uint256) {
        MetricHistory storage history = metricHistories[name];
        return history.values.length > 0 ? history.values[history.values.length - 1] : 0;
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