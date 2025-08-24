// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./NodeRegistryFAB.sol";
import "./interfaces/IJobMarketplace.sol";
import "./interfaces/IPaymentEscrow.sol";
import "./interfaces/IReputationSystem.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title JobMarketplaceFAB
 * @dev JobMarketplace that works with NodeRegistryFAB instead of NodeRegistry
 */
contract JobMarketplaceFAB is ReentrancyGuard {
    enum JobStatus {
        Posted,
        Claimed,
        Completed
    }
    
    struct Job {
        address renter;
        JobStatus status;
        address assignedHost;
        uint256 maxPrice;
        uint256 deadline;
        uint256 completedAt;
        address paymentToken;
        bytes32 escrowId;
        string modelId;
        string inputHash;
        string resultHash;
    }
    
    uint256 public constant MAX_PAYMENT = 1000 ether;
    address public usdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    NodeRegistryFAB public nodeRegistry;
    IReputationSystem public reputationSystem;
    IPaymentEscrow public paymentEscrow;
    
    mapping(uint256 => Job) private jobs;
    uint256 private nextJobId = 1;
    
    event JobCreated(uint256 indexed jobId, address indexed renter, string modelId, uint256 maxPrice);
    event JobCreatedWithToken(bytes32 indexed jobId, address indexed renter, address paymentToken, uint256 paymentAmount);
    event JobClaimed(uint256 indexed jobId, address indexed host);
    event JobCompleted(uint256 indexed jobId, string resultHash);
    
    constructor(address _nodeRegistry) {
        nodeRegistry = NodeRegistryFAB(_nodeRegistry);
    }
    
    function setPaymentEscrow(address _paymentEscrow) external {
        require(address(paymentEscrow) == address(0), "Already set");
        paymentEscrow = IPaymentEscrow(_paymentEscrow);
    }
    
    function setUsdcAddress(address _usdc) external {
        usdcAddress = _usdc;
    }
    
    function setReputationSystem(address _reputation) external {
        require(address(reputationSystem) == address(0), "Already set");
        reputationSystem = IReputationSystem(_reputation);
    }
    
    // Post job with USDC token
    function postJobWithToken(
        IJobMarketplace.JobDetails memory details,
        IJobMarketplace.JobRequirements memory requirements,
        address paymentToken,
        uint256 paymentAmount
    ) external nonReentrant returns (bytes32) {
        require(paymentToken == usdcAddress, "Only USDC accepted");
        require(paymentAmount > 0, "Payment must be positive");
        require(address(paymentEscrow) != address(0), "PaymentEscrow not set");
        
        // Generate job ID
        bytes32 jobId = keccak256(abi.encodePacked(msg.sender, block.timestamp, nextJobId, details.modelId));
        
        // Transfer USDC to PaymentEscrow
        IERC20(paymentToken).transferFrom(msg.sender, address(this), paymentAmount);
        IERC20(paymentToken).transfer(address(paymentEscrow), paymentAmount);
        
        // Store job
        uint256 internalJobId = nextJobId++;
        jobs[internalJobId] = Job({
            renter: msg.sender,
            status: JobStatus.Posted,
            assignedHost: address(0),
            maxPrice: paymentAmount,
            deadline: block.timestamp + requirements.maxTimeToComplete,
            completedAt: 0,
            paymentToken: paymentToken,
            escrowId: jobId,
            modelId: details.modelId,
            inputHash: details.prompt,
            resultHash: ""
        });
        
        emit JobCreatedWithToken(jobId, msg.sender, paymentToken, paymentAmount);
        emit JobCreated(internalJobId, msg.sender, details.modelId, paymentAmount);
        
        return jobId;
    }
    
    // Claim job - FIXED for NodeRegistryFAB
    function claimJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        require(job.renter != address(0), "Job does not exist");
        require(job.status == JobStatus.Posted, "Job not available");
        require(block.timestamp <= job.deadline, "Job expired");
        
        // Check if host is registered in NodeRegistryFAB
        // nodes() returns (operator, stakedAmount, active, metadata)
        (address operator, uint256 stakedAmount, bool active, ) = nodeRegistry.nodes(msg.sender);
        require(operator != address(0), "Not a registered host");
        require(active, "Host not active");
        require(stakedAmount >= nodeRegistry.MIN_STAKE(), "Insufficient stake");
        
        job.assignedHost = msg.sender;
        job.status = JobStatus.Claimed;
        
        emit JobClaimed(_jobId, msg.sender);
    }
    
    // Complete job
    function completeJob(
        uint256 _jobId,
        string memory _resultHash,
        bytes memory _proof
    ) external nonReentrant {
        Job storage job = jobs[_jobId];
        require(job.assignedHost == msg.sender, "Not assigned host");
        require(job.status == JobStatus.Claimed, "Job not claimed");
        require(block.timestamp <= job.deadline, "Deadline passed");
        
        job.resultHash = _resultHash;
        job.status = JobStatus.Completed;
        job.completedAt = block.timestamp;
        
        // Handle payment
        if (job.paymentToken != address(0)) {
            // USDC payment through escrow
            paymentEscrow.releasePaymentFor(
                job.escrowId,
                msg.sender,
                job.maxPrice,
                job.paymentToken
            );
        } else {
            // ETH payment
            (bool success, ) = payable(msg.sender).call{value: job.maxPrice}("");
            require(success, "ETH transfer failed");
        }
        
        // Update reputation if available
        if (address(reputationSystem) != address(0)) {
            try reputationSystem.recordJobCompletion(msg.sender, _jobId, true) {} catch {}
        }
        
        emit JobCompleted(_jobId, _resultHash);
    }
    
    // Get job details
    function getJob(uint256 _jobId) external view returns (
        address renter,
        uint256 payment,
        JobStatus status,
        address assignedHost,
        string memory resultHash,
        uint256 deadline
    ) {
        Job memory job = jobs[_jobId];
        return (
            job.renter,
            job.maxPrice,
            job.status,
            job.assignedHost,
            job.resultHash,
            job.deadline
        );
    }
    
    function getJobStruct(uint256 _jobId) external view returns (Job memory) {
        return jobs[_jobId];
    }
}