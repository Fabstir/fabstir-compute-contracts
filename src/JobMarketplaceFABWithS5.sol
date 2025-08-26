// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./NodeRegistryFAB.sol";
import "./interfaces/IJobMarketplace.sol";
import "./interfaces/IPaymentEscrow.sol";
import "./interfaces/IReputationSystem.sol";
import "./HostEarnings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title JobMarketplaceFABWithS5
 * @dev JobMarketplace with S5 CID storage for prompts and responses
 * @notice Stores prompts and responses as S5 CIDs to maintain decentralization while reducing gas costs
 */
contract JobMarketplaceFABWithS5 is ReentrancyGuard {
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
        string promptCID;      // S5 CID for the prompt
        string responseCID;    // S5 CID for the response
    }
    
    struct JobDetails {
        string modelId;
        string promptCID;      // S5 CID for prompt (changed from prompt text)
        string responseCID;    // S5 CID for response (new field)
        string resultFormat;
        uint256 temperature;
        uint256 maxTokens;
        uint32 seed;
    }
    
    uint256 public constant MAX_PAYMENT = 1000 ether;
    address public usdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    NodeRegistryFAB public nodeRegistry;
    IReputationSystem public reputationSystem;
    IPaymentEscrow public paymentEscrow;
    HostEarnings public hostEarnings;
    
    mapping(uint256 => Job) private jobs;
    uint256 private nextJobId = 1;
    
    // Track total earnings credited per host for analytics
    mapping(address => uint256) public totalEarningsCredited;
    
    event JobCreated(
        uint256 indexed jobId, 
        address indexed renter, 
        string modelId, 
        uint256 maxPrice,
        string promptCID
    );
    event JobCreatedWithToken(
        bytes32 indexed jobId, 
        address indexed renter, 
        address paymentToken, 
        uint256 paymentAmount,
        string promptCID
    );
    event JobClaimed(uint256 indexed jobId, address indexed host);
    event JobCompleted(uint256 indexed jobId, string responseCID);
    event EarningsCredited(address indexed host, uint256 amount, address token);
    
    constructor(address _nodeRegistry, address payable _hostEarnings) {
        nodeRegistry = NodeRegistryFAB(_nodeRegistry);
        hostEarnings = HostEarnings(_hostEarnings);
    }
    
    function setPaymentEscrow(address _paymentEscrow) external {
        require(address(paymentEscrow) == address(0), "Already set");
        paymentEscrow = IPaymentEscrow(_paymentEscrow);
    }
    
    function setHostEarnings(address payable _hostEarnings) external {
        require(_hostEarnings != address(0), "Invalid address");
        hostEarnings = HostEarnings(_hostEarnings);
    }
    
    function setUsdcAddress(address _usdc) external {
        usdcAddress = _usdc;
    }
    
    function setReputationSystem(address _reputation) external {
        require(address(reputationSystem) == address(0), "Already set");
        reputationSystem = IReputationSystem(_reputation);
    }
    
    /**
     * @notice Post a job with USDC token payment and S5 CID for prompt
     * @param promptCID S5 CID where the prompt is stored
     * @param modelId The AI model to use
     * @param paymentToken The ERC20 token address (must be USDC)
     * @param paymentAmount The payment amount
     * @param deadline The deadline for job completion
     * @param hostAddress Specific host address (0x0 for any host)
     */
    function postJobWithToken(
        string memory promptCID,
        string memory modelId,
        address paymentToken,
        uint256 paymentAmount,
        uint256 deadline,
        address hostAddress
    ) external nonReentrant returns (bytes32) {
        require(bytes(promptCID).length > 0, "Prompt CID required");
        require(paymentToken == usdcAddress, "Only USDC accepted");
        require(paymentAmount > 0, "Payment must be positive");
        require(address(paymentEscrow) != address(0), "PaymentEscrow not set");
        require(deadline > block.timestamp, "Deadline must be in future");
        
        // Generate job ID
        bytes32 jobId = keccak256(abi.encodePacked(msg.sender, block.timestamp, nextJobId, modelId));
        
        // Transfer USDC to PaymentEscrow
        IERC20(paymentToken).transferFrom(msg.sender, address(this), paymentAmount);
        IERC20(paymentToken).transfer(address(paymentEscrow), paymentAmount);
        
        // Store job with S5 CID
        uint256 internalJobId = nextJobId++;
        jobs[internalJobId] = Job({
            renter: msg.sender,
            status: JobStatus.Posted,
            assignedHost: hostAddress, // Can be 0x0 for any host
            maxPrice: paymentAmount,
            deadline: deadline,
            completedAt: 0,
            paymentToken: paymentToken,
            escrowId: jobId,
            modelId: modelId,
            promptCID: promptCID,
            responseCID: ""
        });
        
        emit JobCreatedWithToken(jobId, msg.sender, paymentToken, paymentAmount, promptCID);
        emit JobCreated(internalJobId, msg.sender, modelId, paymentAmount, promptCID);
        
        return jobId;
    }
    
    /**
     * @notice Post a job with JobDetails struct (includes S5 CIDs)
     * @param details Job details including promptCID
     * @param requirements Job requirements
     * @param paymentToken The ERC20 token address (must be USDC)
     * @param paymentAmount The payment amount
     */
    function postJobWithDetails(
        JobDetails memory details,
        IJobMarketplace.JobRequirements memory requirements,
        address paymentToken,
        uint256 paymentAmount
    ) external nonReentrant returns (bytes32) {
        require(bytes(details.promptCID).length > 0, "Prompt CID required");
        require(paymentToken == usdcAddress, "Only USDC accepted");
        require(paymentAmount > 0, "Payment must be positive");
        require(address(paymentEscrow) != address(0), "PaymentEscrow not set");
        
        // Generate job ID
        bytes32 jobId = keccak256(abi.encodePacked(msg.sender, block.timestamp, nextJobId, details.modelId));
        
        // Transfer USDC to PaymentEscrow
        IERC20(paymentToken).transferFrom(msg.sender, address(this), paymentAmount);
        IERC20(paymentToken).transfer(address(paymentEscrow), paymentAmount);
        
        // Store job with S5 CID
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
            promptCID: details.promptCID,
            responseCID: ""
        });
        
        emit JobCreatedWithToken(jobId, msg.sender, paymentToken, paymentAmount, details.promptCID);
        emit JobCreated(internalJobId, msg.sender, details.modelId, paymentAmount, details.promptCID);
        
        return jobId;
    }
    
    /**
     * @notice Claim a job
     * @param _jobId The job ID to claim
     */
    function claimJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        require(job.renter != address(0), "Job does not exist");
        require(job.status == JobStatus.Posted, "Job not available");
        require(block.timestamp <= job.deadline, "Job expired");
        
        // If specific host was requested, only that host can claim
        if (job.assignedHost != address(0)) {
            require(job.assignedHost == msg.sender, "Job reserved for specific host");
        }
        
        // Check if host is registered in NodeRegistryFAB
        (address operator, uint256 stakedAmount, bool active, ) = nodeRegistry.nodes(msg.sender);
        require(operator != address(0), "Not a registered host");
        require(active, "Host not active");
        require(stakedAmount >= nodeRegistry.MIN_STAKE(), "Insufficient stake");
        
        job.assignedHost = msg.sender;
        job.status = JobStatus.Claimed;
        
        emit JobClaimed(_jobId, msg.sender);
    }
    
    /**
     * @notice Complete a job with S5 CID for response
     * @param _jobId The job ID to complete
     * @param _responseCID S5 CID where the response is stored
     */
    function completeJob(
        uint256 _jobId,
        string memory _responseCID
    ) external nonReentrant {
        Job storage job = jobs[_jobId];
        require(job.assignedHost == msg.sender, "Not assigned host");
        require(job.status == JobStatus.Claimed, "Job not claimed");
        require(block.timestamp <= job.deadline, "Deadline passed");
        require(bytes(_responseCID).length > 0, "Response CID required");
        
        job.responseCID = _responseCID;
        job.status = JobStatus.Completed;
        job.completedAt = block.timestamp;
        
        // Handle payment through earnings accumulation
        if (job.paymentToken != address(0)) {
            // USDC payment - release to HostEarnings contract
            paymentEscrow.releaseToEarnings(
                job.escrowId,
                msg.sender,
                job.maxPrice,
                job.paymentToken,
                address(hostEarnings)
            );
            
            // Track total credited
            totalEarningsCredited[msg.sender] += job.maxPrice;
            
            emit EarningsCredited(msg.sender, job.maxPrice, job.paymentToken);
        } else {
            // ETH payment - accumulate in HostEarnings
            revert("ETH payments not supported with earnings accumulation");
        }
        
        // Update reputation if available
        if (address(reputationSystem) != address(0)) {
            try reputationSystem.recordJobCompletion(msg.sender, _jobId, true) {} catch {}
        }
        
        emit JobCompleted(_jobId, _responseCID);
    }
    
    /**
     * @notice Get job details including CIDs
     * @param _jobId The job ID
     * @return renter The job creator
     * @return payment The payment amount
     * @return status The job status
     * @return assignedHost The assigned host
     * @return promptCID The S5 CID for the prompt
     * @return responseCID The S5 CID for the response
     * @return deadline The job deadline
     */
    function getJob(uint256 _jobId) external view returns (
        address renter,
        uint256 payment,
        JobStatus status,
        address assignedHost,
        string memory promptCID,
        string memory responseCID,
        uint256 deadline
    ) {
        Job memory job = jobs[_jobId];
        return (
            job.renter,
            job.maxPrice,
            job.status,
            job.assignedHost,
            job.promptCID,
            job.responseCID,
            job.deadline
        );
    }
    
    /**
     * @notice Get full job struct
     * @param _jobId The job ID
     * @return The complete job struct
     */
    function getJobStruct(uint256 _jobId) external view returns (Job memory) {
        return jobs[_jobId];
    }
    
    /**
     * @notice Get job CIDs only
     * @param _jobId The job ID
     * @return promptCID The S5 CID for the prompt
     * @return responseCID The S5 CID for the response
     */
    function getJobCIDs(uint256 _jobId) external view returns (
        string memory promptCID,
        string memory responseCID
    ) {
        Job memory job = jobs[_jobId];
        return (job.promptCID, job.responseCID);
    }
    
    /**
     * @notice Check host's total credited earnings
     * @param host The host address
     * @return Total earnings credited to the host
     */
    function getHostTotalCredited(address host) external view returns (uint256) {
        return totalEarningsCredited[host];
    }
    
    /**
     * @notice Post job with ETH (deprecated)
     */
    function postJob(
        string memory _modelId,
        string memory _inputHash,
        uint256 _maxPrice
    ) external payable nonReentrant returns (uint256) {
        revert("ETH jobs not supported - use postJobWithToken with USDC");
    }
}