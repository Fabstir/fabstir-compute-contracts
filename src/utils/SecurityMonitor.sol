// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./MonitoringHelper.sol";

contract SecurityMonitor {
    MonitoringHelper public monitoringHelper;
    
    struct SuspiciousPattern {
        uint256 rapidTxThreshold;
        uint256 unusualGasThreshold;
        uint256 largeValueThreshold;
        bool enabled;
    }
    
    struct AddressActivity {
        uint256 txCount;
        uint256 firstSeen;
        uint256 lastSeen;
        uint256 totalValue;
        bool flagged;
    }
    
    mapping(address => AddressActivity) public addressActivities;
    mapping(address => mapping(uint256 => uint256)) public txTimestamps;
    mapping(address => uint256) public suspiciousScore;
    
    SuspiciousPattern public patterns = SuspiciousPattern({
        rapidTxThreshold: 10,
        unusualGasThreshold: 1000000,
        largeValueThreshold: 100 ether,
        enabled: true
    });
    
    uint256 private constant RAPID_TX_WINDOW = 1 minutes;
    uint256 private constant SUSPICIOUS_THRESHOLD = 75;
    
    event SuspiciousActivityDetected(
        address indexed target,
        string activityType,
        uint256 score
    );
    
    event SecurityPatternUpdated(
        string patternType,
        uint256 oldValue,
        uint256 newValue
    );
    
    constructor(address _monitoringHelper) {
        monitoringHelper = MonitoringHelper(_monitoringHelper);
    }
    
    function monitorTransaction(
        address from,
        address to,
        uint256 value,
        uint256 gasUsed
    ) external returns (bool suspicious) {
        _updateAddressActivity(from, value);
        _updateAddressActivity(to, 0);
        
        uint256 score = 0;
        
        if (_checkRapidTransactions(from)) {
            score += 30;
            emit SuspiciousActivityDetected(from, "rapid_transactions", 30);
        }
        
        if (_checkUnusualGas(gasUsed)) {
            score += 20;
            emit SuspiciousActivityDetected(from, "unusual_gas", 20);
        }
        
        if (_checkLargeValue(value)) {
            score += 25;
            emit SuspiciousActivityDetected(from, "large_value", 25);
        }
        
        if (_checkNewAddress(from) && value > 10 ether) {
            score += 25;
            emit SuspiciousActivityDetected(from, "new_address_large_tx", 25);
        }
        
        suspiciousScore[from] = score;
        
        if (score >= SUSPICIOUS_THRESHOLD) {
            addressActivities[from].flagged = true;
            monitoringHelper.recordSecurityAlert(
                from,
                "suspicious_activity",
                "high",
                abi.encode(score, value, gasUsed)
            );
            return true;
        }
        
        return false;
    }
    
    function checkAddressReputation(address target) external view returns (uint256 score) {
        AddressActivity memory activity = addressActivities[target];
        
        if (activity.flagged) return 0;
        if (activity.txCount == 0) return 50;
        
        uint256 ageInDays = (block.timestamp - activity.firstSeen) / 1 days;
        uint256 avgTxPerDay = activity.txCount / (ageInDays + 1);
        
        score = 50;
        
        if (ageInDays > 30) score += 20;
        else if (ageInDays > 7) score += 10;
        
        if (avgTxPerDay < 10) score += 20;
        else if (avgTxPerDay < 50) score += 10;
        
        if (suspiciousScore[target] > 0) {
            score = score * (100 - suspiciousScore[target]) / 100;
        }
        
        return score > 100 ? 100 : score;
    }
    
    function updateSecurityPattern(
        string memory patternType,
        uint256 newValue
    ) external {
        uint256 oldValue;
        
        if (keccak256(bytes(patternType)) == keccak256(bytes("rapid_tx"))) {
            oldValue = patterns.rapidTxThreshold;
            patterns.rapidTxThreshold = newValue;
        } else if (keccak256(bytes(patternType)) == keccak256(bytes("unusual_gas"))) {
            oldValue = patterns.unusualGasThreshold;
            patterns.unusualGasThreshold = newValue;
        } else if (keccak256(bytes(patternType)) == keccak256(bytes("large_value"))) {
            oldValue = patterns.largeValueThreshold;
            patterns.largeValueThreshold = newValue;
        } else {
            revert("Unknown pattern type");
        }
        
        emit SecurityPatternUpdated(patternType, oldValue, newValue);
    }
    
    function resetSuspiciousScore(address target) external {
        suspiciousScore[target] = 0;
        addressActivities[target].flagged = false;
    }
    
    function _updateAddressActivity(address target, uint256 value) private {
        AddressActivity storage activity = addressActivities[target];
        
        if (activity.firstSeen == 0) {
            activity.firstSeen = block.timestamp;
        }
        
        activity.lastSeen = block.timestamp;
        activity.txCount++;
        activity.totalValue += value;
        
        uint256 txIndex = activity.txCount % 100;
        txTimestamps[target][txIndex] = block.timestamp;
    }
    
    function _checkRapidTransactions(address target) private view returns (bool) {
        AddressActivity memory activity = addressActivities[target];
        if (activity.txCount < patterns.rapidTxThreshold) return false;
        
        uint256 recentCount = 0;
        uint256 cutoffTime = block.timestamp - RAPID_TX_WINDOW;
        
        for (uint256 i = 0; i < 100 && i < activity.txCount; i++) {
            if (txTimestamps[target][i] >= cutoffTime) {
                recentCount++;
            }
        }
        
        return recentCount >= patterns.rapidTxThreshold;
    }
    
    function _checkUnusualGas(uint256 gasUsed) private view returns (bool) {
        return gasUsed > patterns.unusualGasThreshold;
    }
    
    function _checkLargeValue(uint256 value) private view returns (bool) {
        return value > patterns.largeValueThreshold;
    }
    
    function _checkNewAddress(address target) private view returns (bool) {
        AddressActivity memory activity = addressActivities[target];
        return block.timestamp - activity.firstSeen < 1 days;
    }
}