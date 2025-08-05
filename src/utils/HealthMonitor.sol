// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./MonitoringHelper.sol";

contract HealthMonitor {
    MonitoringHelper public monitoringHelper;
    
    mapping(address => uint256) public lastHealthCheck;
    mapping(address => uint256) public healthScore;
    mapping(address => bool) public criticalContracts;
    
    uint256 public constant HEALTH_CHECK_INTERVAL = 5 minutes;
    uint256 public constant CRITICAL_THRESHOLD = 50;
    
    event ContractHealthUpdated(
        address indexed contract_,
        uint256 healthScore,
        string status
    );
    
    event CriticalHealthDetected(
        address indexed contract_,
        string reason
    );
    
    constructor(address _monitoringHelper) {
        monitoringHelper = MonitoringHelper(_monitoringHelper);
    }
    
    function checkHealth(address target) external returns (MonitoringHelper.HealthStatus memory) {
        require(
            block.timestamp >= lastHealthCheck[target] + HEALTH_CHECK_INTERVAL,
            "Health check too soon"
        );
        
        lastHealthCheck[target] = block.timestamp;
        
        MonitoringHelper.HealthStatus memory status = monitoringHelper.performHealthCheck(target);
        
        uint256 score = _calculateHealthScore(status);
        healthScore[target] = score;
        
        emit ContractHealthUpdated(target, score, status.status);
        
        if (score < CRITICAL_THRESHOLD) {
            emit CriticalHealthDetected(target, "Low health score");
        }
        
        return status;
    }
    
    function checkMultipleContracts(address[] memory targets) external {
        for (uint256 i = 0; i < targets.length; i++) {
            if (block.timestamp >= lastHealthCheck[targets[i]] + HEALTH_CHECK_INTERVAL) {
                this.checkHealth(targets[i]);
            }
        }
    }
    
    function markCriticalContract(address target, bool critical) external {
        criticalContracts[target] = critical;
    }
    
    function getSystemHealth(address[] memory contracts) external view returns (uint256) {
        uint256 totalScore;
        uint256 criticalCount;
        
        for (uint256 i = 0; i < contracts.length; i++) {
            uint256 score = healthScore[contracts[i]];
            
            if (criticalContracts[contracts[i]]) {
                criticalCount++;
                totalScore += score * 2;
            } else {
                totalScore += score;
            }
        }
        
        uint256 divisor = contracts.length + criticalCount;
        return divisor > 0 ? totalScore / divisor : 0;
    }
    
    function _calculateHealthScore(
        MonitoringHelper.HealthStatus memory status
    ) private pure returns (uint256) {
        if (!status.isOperational) return 0;
        
        if (keccak256(bytes(status.status)) == keccak256(bytes("healthy"))) {
            return 100;
        } else if (keccak256(bytes(status.status)) == keccak256(bytes("degraded"))) {
            return 70 - (status.errorCount * 10);
        } else {
            return 30 - (status.errorCount * 5);
        }
    }
}