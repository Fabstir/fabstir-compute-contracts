// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./NodeRegistry.sol";
import "./JobMarketplace.sol";

contract ReputationSystem {
    struct HostReputation {
        uint256 score;
        uint256 totalRatings;
        uint256 sumRatings;
        uint256 lastActivityTimestamp;
        mapping(uint256 => bool) hasRatedJob;
    }
    
    NodeRegistry public nodeRegistry;
    JobMarketplace public jobMarketplace;
    address public governance;
    
    uint256 public constant INITIAL_REPUTATION = 100;
    uint256 public constant SUCCESS_BONUS = 10;
    uint256 public constant FAILURE_PENALTY = 20;
    uint256 public constant DECAY_PERIOD = 30 days;
    uint256 public constant DECAY_RATE = 5; // 5% decay per period
    uint256 public constant INCENTIVE_THRESHOLD = 150;
    
    mapping(address => HostReputation) public hostReputations;
    address[] public allHosts;
    mapping(address => bool) public isTrackedHost;
    
    event ReputationUpdated(address indexed host, int256 change, uint256 newScore);
    event QualityReported(address indexed host, address indexed renter, uint8 rating, string feedback);
    event ReputationSlashed(address indexed host, uint256 amount, string reason);
    
    modifier onlyJobMarketplace() {
        require(msg.sender == address(jobMarketplace), "Only job marketplace");
        _;
    }
    
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance");
        _;
    }
    
    constructor(
        address _nodeRegistry,
        address _jobMarketplace,
        address _governance
    ) {
        nodeRegistry = NodeRegistry(_nodeRegistry);
        jobMarketplace = JobMarketplace(_jobMarketplace);
        governance = _governance;
    }
    
    function getReputation(address host) external view returns (uint256) {
        // Check if host is registered in NodeRegistry
        NodeRegistry.Node memory node = nodeRegistry.getNode(host);
        if (node.operator == address(0)) {
            return 0;
        }
        
        HostReputation storage rep = hostReputations[host];
        if (rep.lastActivityTimestamp == 0) {
            return INITIAL_REPUTATION;
        }
        
        // Calculate decayed reputation
        uint256 timePassed = block.timestamp - rep.lastActivityTimestamp;
        uint256 periods = timePassed / DECAY_PERIOD;
        
        if (periods > 0) {
            uint256 decayAmount = (rep.score * periods * DECAY_RATE) / 100;
            if (decayAmount >= rep.score) {
                return INITIAL_REPUTATION;
            }
            return rep.score - decayAmount;
        }
        
        return rep.score;
    }
    
    function recordJobCompletion(
        address host,
        uint256 jobId,
        bool success
    ) external onlyJobMarketplace {
        _initializeHostIfNeeded(host);
        
        HostReputation storage rep = hostReputations[host];
        int256 change;
        
        if (success) {
            rep.score += SUCCESS_BONUS;
            change = int256(SUCCESS_BONUS);
        } else {
            if (rep.score > FAILURE_PENALTY) {
                rep.score -= FAILURE_PENALTY;
                change = -int256(FAILURE_PENALTY);
            } else {
                change = -int256(rep.score);
                rep.score = 0;
            }
        }
        
        rep.lastActivityTimestamp = block.timestamp;
        emit ReputationUpdated(host, change, rep.score);
    }
    
    function rateHost(
        address host,
        uint256 jobId,
        uint8 rating,
        string memory feedback
    ) external {
        require(rating >= 1 && rating <= 5, "Invalid rating");
        
        // Verify caller is the renter for this job
        JobMarketplace.Job memory job = jobMarketplace.getJob(jobId);
        require(msg.sender == job.renter, "Not job renter");
        require(job.assignedHost == host, "Host not assigned to job");
        require(job.status == JobMarketplace.JobStatus.Completed, "Job not completed");
        
        HostReputation storage rep = hostReputations[host];
        require(!rep.hasRatedJob[jobId], "Already rated");
        
        _initializeHostIfNeeded(host);
        
        rep.hasRatedJob[jobId] = true;
        rep.totalRatings++;
        rep.sumRatings += rating;
        
        // Bonus reputation for high ratings
        if (rating >= 4) {
            uint256 bonus = (rating - 3) * 2; // 4 stars = +2, 5 stars = +4
            rep.score += bonus;
            emit ReputationUpdated(host, int256(bonus), rep.score);
        }
        
        emit QualityReported(host, msg.sender, rating, feedback);
    }
    
    function getAverageRating(address host) external view returns (uint256) {
        HostReputation storage rep = hostReputations[host];
        if (rep.totalRatings == 0) {
            return 0;
        }
        return rep.sumRatings / rep.totalRatings;
    }
    
    function sortHostsByReputation(address[] memory hosts) external view returns (address[] memory) {
        uint256 length = hosts.length;
        address[] memory sorted = new address[](length);
        
        // Copy array
        for (uint256 i = 0; i < length; i++) {
            sorted[i] = hosts[i];
        }
        
        // Bubble sort by reputation (descending)
        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                uint256 rep1 = this.getReputation(sorted[j]);
                uint256 rep2 = this.getReputation(sorted[j + 1]);
                
                if (rep1 < rep2) {
                    address temp = sorted[j];
                    sorted[j] = sorted[j + 1];
                    sorted[j + 1] = temp;
                }
            }
        }
        
        return sorted;
    }
    
    function applyReputationDecay(address host) external {
        HostReputation storage rep = hostReputations[host];
        require(rep.lastActivityTimestamp > 0, "No activity recorded");
        
        uint256 currentRep = this.getReputation(host);
        rep.score = currentRep;
        rep.lastActivityTimestamp = block.timestamp;
    }
    
    function slashReputation(
        address host,
        uint256 amount,
        string memory reason
    ) external onlyGovernance {
        _initializeHostIfNeeded(host);
        
        HostReputation storage rep = hostReputations[host];
        
        if (amount >= rep.score) {
            rep.score = 0;
        } else {
            rep.score -= amount;
        }
        
        emit ReputationSlashed(host, amount, reason);
        emit ReputationUpdated(host, -int256(amount), rep.score);
    }
    
    function isEligibleForIncentives(address host) external view returns (bool) {
        return this.getReputation(host) >= INCENTIVE_THRESHOLD;
    }
    
    function getTopHosts(uint256 count) external view returns (address[] memory) {
        uint256 hostCount = allHosts.length;
        if (count > hostCount) {
            count = hostCount;
        }
        
        address[] memory topHosts = new address[](count);
        uint256[] memory topScores = new uint256[](count);
        
        for (uint256 i = 0; i < hostCount; i++) {
            address host = allHosts[i];
            uint256 score = this.getReputation(host);
            
            // Find position to insert
            for (uint256 j = 0; j < count; j++) {
                if (score > topScores[j]) {
                    // Shift elements down
                    for (uint256 k = count - 1; k > j; k--) {
                        topHosts[k] = topHosts[k - 1];
                        topScores[k] = topScores[k - 1];
                    }
                    
                    topHosts[j] = host;
                    topScores[j] = score;
                    break;
                }
            }
        }
        
        return topHosts;
    }
    
    function _initializeHostIfNeeded(address host) private {
        HostReputation storage rep = hostReputations[host];
        
        if (rep.lastActivityTimestamp == 0) {
            // First time initialization
            rep.score = INITIAL_REPUTATION;
            rep.lastActivityTimestamp = block.timestamp;
            
            if (!isTrackedHost[host]) {
                allHosts.push(host);
                isTrackedHost[host] = true;
            }
        }
    }
}