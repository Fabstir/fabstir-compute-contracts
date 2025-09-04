// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./NodeRegistryFAB.sol";
import "./interfaces/IJobMarketplace.sol";
import "./interfaces/IPaymentEscrow.sol";
import "./interfaces/IReputationSystem.sol";
import "./HostEarnings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Proof system interface
interface IProofSystem {
    function verifyEKZL(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) external view returns (bool);
    
    function verifyAndMarkComplete(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) external returns (bool);
}

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
    
    // New enums for session support
    enum JobType { SinglePrompt, Session }
    enum SessionStatus { Active, Completed, TimedOut, Disputed, Abandoned, Cancelled }
    
    // EZKL proof tracking structure
    struct ProofSubmission {
        bytes32 proofHash;
        uint256 tokensClaimed;
        uint256 timestamp;
        bool verified;
    }
    
    // Session details for long-running jobs
    struct SessionDetails {
        uint256 depositAmount;
        uint256 pricePerToken;
        uint256 maxDuration;
        uint256 sessionStartTime;
        address assignedHost;
        SessionStatus status;
        
        // EZKL proof tracking
        uint256 provenTokens;
        uint256 lastProofSubmission;
        bytes32 aggregateProofHash;
        uint256 checkpointInterval;
        
        // Timeout & dispute tracking
        uint256 lastActivity;      // Last interaction timestamp
        uint256 disputeDeadline;   // When dispute period ends
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
    uint256 public constant MIN_DEPOSIT = 0.0002 ether; // ~$0.80 at $4000/ETH (for ETH payments)
    uint256 public constant MIN_PROVEN_TOKENS = 100; // Minimum meaningful work
    address public usdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    NodeRegistryFAB public nodeRegistry;
    IReputationSystem public reputationSystem;
    IPaymentEscrow public paymentEscrow;
    HostEarnings public hostEarnings;
    
    mapping(uint256 => Job) private jobs;
    uint256 private nextJobId = 1;
    
    // Track total earnings credited per host for analytics
    mapping(address => uint256) public totalEarningsCredited;
    
    // New mappings for session support
    mapping(uint256 => SessionDetails) public sessions;
    mapping(uint256 => ProofSubmission[]) public sessionProofs;
    mapping(uint256 => JobType) public jobTypes;
    
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
    event HostEarningsUpdated(address indexed hostEarnings);
    event HostEarningsInitializationRequired(address indexed hostEarnings);
    
    // New events for session support
    event SessionJobCreated(
        uint256 indexed jobId,
        address indexed user,
        address indexed host,
        uint256 deposit,
        uint256 pricePerToken,
        uint256 maxDuration
    );
    
    event SessionProofRequirementSet(
        uint256 indexed jobId,
        uint256 checkpointInterval
    );
    
    constructor(address _nodeRegistry, address payable _hostEarnings) {
        nodeRegistry = NodeRegistryFAB(_nodeRegistry);
        hostEarnings = HostEarnings(_hostEarnings);
    }
    
    function setPaymentEscrow(address _paymentEscrow) external {
        require(address(paymentEscrow) == address(0));
        paymentEscrow = IPaymentEscrow(_paymentEscrow);
    }
    
    function setHostEarnings(address payable _hostEarnings) external {
        require(_hostEarnings != address(0));
        require(msg.sender == treasuryAddress || treasuryAddress == address(0));
        hostEarnings = HostEarnings(_hostEarnings);
        emit HostEarningsUpdated(_hostEarnings);
    }
    
    /**
     * @notice Initialize HostEarnings contract authorization
     * @dev Call this after deploying both contracts to enable earnings accumulation
     */
    function initializeHostEarnings() external {
        require(address(hostEarnings) != address(0));
        require(msg.sender == treasuryAddress || treasuryAddress == address(0));
        // This will need to be called on the HostEarnings contract to authorize this marketplace
        emit HostEarningsInitializationRequired(address(hostEarnings));
    }
    
    function setUsdcAddress(address _usdc) external {
        usdcAddress = _usdc;
    }
    
    function setReputationSystem(address _reputation) external {
        require(address(reputationSystem) == address(0));
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
        require(bytes(promptCID).length > 0);
        require(paymentToken == usdcAddress);
        require(paymentAmount > 0);
        require(address(paymentEscrow) != address(0));
        require(deadline > block.timestamp);
        
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
        require(bytes(details.promptCID).length > 0);
        require(paymentToken == usdcAddress);
        require(paymentAmount > 0);
        require(address(paymentEscrow) != address(0));
        
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
        require(job.renter != address(0));
        require(job.status == JobStatus.Posted);
        require(block.timestamp <= job.deadline);
        
        // If specific host was requested, only that host can claim
        if (job.assignedHost != address(0)) {
            require(job.assignedHost == msg.sender);
        }
        
        // Check if host is registered in NodeRegistryFAB
        (address operator, uint256 stakedAmount, bool active, ) = nodeRegistry.nodes(msg.sender);
        require(operator != address(0));
        require(active);
        require(stakedAmount >= nodeRegistry.MIN_STAKE());
        
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
        require(job.assignedHost == msg.sender);
        require(job.status == JobStatus.Claimed);
        require(block.timestamp <= job.deadline);
        require(bytes(_responseCID).length > 0);
        
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
    
    
    // Create session-based job with upfront deposit
    function createSessionJob(
        address host,
        uint256 deposit,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval
    ) external payable returns (uint256 jobId) {
        require(msg.value >= MIN_DEPOSIT);
        require(deposit >= MIN_DEPOSIT);
        require(deposit > 0);
        require(pricePerToken > 0);
        require(maxDuration > 0 && maxDuration <= 365 days);
        require(proofInterval > 0);
        require(host != address(0));
        require(msg.value >= deposit);
        require(deposit <= 1000 ether);
        
        // Validate host
        (address operator, uint256 stakedAmount, bool active, ) = nodeRegistry.nodes(host);
        require(operator != address(0));
        require(active);
        require(stakedAmount >= nodeRegistry.MIN_STAKE());
        
        // Validate proof requirements
        _validateProofRequirements(proofInterval, deposit, pricePerToken);
        
        jobId = nextJobId++;
        
        // Create Job struct for proper session tracking
        jobs[jobId] = Job({
            renter: msg.sender,
            status: JobStatus.Claimed,
            assignedHost: host,
            maxPrice: deposit,
            deadline: block.timestamp + maxDuration,
            completedAt: 0,
            paymentToken: address(0), // ETH payment
            escrowId: bytes32(jobId),
            modelId: "",
            promptCID: "",
            responseCID: ""
        });
        
        sessions[jobId] = SessionDetails({
            depositAmount: deposit,
            pricePerToken: pricePerToken,
            maxDuration: maxDuration,
            sessionStartTime: block.timestamp,
            assignedHost: host,
            status: SessionStatus.Active,
            provenTokens: 0,
            lastProofSubmission: 0,
            aggregateProofHash: bytes32(0),
            checkpointInterval: proofInterval,
            lastActivity: block.timestamp,
            disputeDeadline: 0
        });
        
        jobTypes[jobId] = JobType.Session;
        _lockSessionDeposit(jobId, deposit);
        
        emit SessionJobCreated(jobId, msg.sender, host, deposit, pricePerToken, maxDuration);
        emit SessionProofRequirementSet(jobId, proofInterval);
    }
    
    function _lockSessionDeposit(uint256 jobId, uint256 amount) internal {
        // Funds held in contract (ETH already transferred via msg.value)
    }
    
    function _validateProofRequirements(
        uint256 proofInterval,
        uint256 deposit,
        uint256 pricePerToken
    ) internal pure {
        require(proofInterval >= 100);
        require(proofInterval <= 1000000);
        uint256 maxTokens = deposit / pricePerToken;
        require(maxTokens >= 100);
        require(proofInterval <= maxTokens);
    }
    
    function getSessionRequirements(
        uint256 pricePerToken
    ) external pure returns (
        uint256 minDeposit,
        uint256 minProofInterval,
        uint256 maxDuration
    ) {
        minDeposit = pricePerToken * 100;
        if (minDeposit < 0.01 ether) minDeposit = 0.01 ether;
        minProofInterval = 100;
        maxDuration = 365 days;
    }
    
    // EZKL Proof submission events
    event ProofSubmitted(
        uint256 indexed jobId,
        address indexed host,
        uint256 tokensClaimed,
        bytes32 proofHash,
        bool verified
    );
    
    event BatchProofsSubmitted(
        uint256 indexed jobId,
        uint256 proofCount,
        uint256 totalTokens
    );
    
    IProofSystem public proofSystem;
    
    // Token payment support
    mapping(address => bool) public acceptedTokens;
    mapping(address => uint256) public tokenMinDeposits;
    
    // Event for token payments
    event SessionJobCreatedWithToken(
        uint256 indexed jobId,
        address indexed token,
        uint256 deposit
    );
    
    function setProofSystem(address _proofSystem) external {
        require(_proofSystem != address(0));
        proofSystem = IProofSystem(_proofSystem);
    }
    
    // Enable/disable token acceptance and set minimum deposit
    function setAcceptedToken(address token, bool accepted, uint256 minDeposit) external {
        acceptedTokens[token] = accepted;
        // Set minimum deposit (use 800000 as default for USDC-like tokens)
        if (accepted) {
            tokenMinDeposits[token] = minDeposit > 0 ? minDeposit : 800000;
        }
    }
    
    function submitProofOfWork(
        uint256 jobId,
        bytes calldata ekzlProof,
        uint256 tokensInBatch
    ) external returns (bool verified) {
        require(jobTypes[jobId] == JobType.Session);
        SessionDetails storage session = sessions[jobId];
        require(session.status == SessionStatus.Active);
        require(session.assignedHost == msg.sender);
        require(tokensInBatch >= MIN_PROVEN_TOKENS);
        require(tokensInBatch > 0);
        require(ekzlProof.length > 0);
        
        uint256 maxTokens = session.depositAmount / session.pricePerToken;
        require(session.provenTokens + tokensInBatch <= maxTokens);
        require(session.provenTokens < maxTokens);
        
        verified = _verifyAndRecordProof(jobId, ekzlProof, tokensInBatch);
        
        emit ProofSubmitted(jobId, msg.sender, tokensInBatch, keccak256(ekzlProof), verified);
        return verified;
    }
    
    function submitBatchProofs(
        uint256 jobId,
        bytes[] calldata proofs,
        uint256[] calldata tokenCounts
    ) external {
        require(proofs.length == tokenCounts.length);
        require(proofs.length > 0);
        
        uint256 totalTokens = 0;
        for (uint256 i = 0; i < proofs.length; i++) {
            _verifyAndRecordProof(jobId, proofs[i], tokenCounts[i]);
            totalTokens += tokenCounts[i];
            emit ProofSubmitted(jobId, msg.sender, tokenCounts[i], keccak256(proofs[i]), true);
        }
        
        emit BatchProofsSubmitted(jobId, proofs.length, totalTokens);
    }
    
    function _verifyAndRecordProof(
        uint256 jobId,
        bytes calldata proof,
        uint256 tokens
    ) internal returns (bool) {
        // Verify with ProofSystem if available (use verifyAndMarkComplete for replay prevention)
        bool verified = address(proofSystem) != address(0) ? 
            proofSystem.verifyAndMarkComplete(proof, msg.sender, tokens) : false;
        
        // Only record if verification passed
        if (verified) {
            ProofSubmission memory submission = ProofSubmission({
                proofHash: keccak256(proof),
                tokensClaimed: tokens,
                timestamp: block.timestamp,
                verified: true
            });
            
            sessionProofs[jobId].push(submission);
            
            SessionDetails storage session = sessions[jobId];
            session.provenTokens += tokens;
            session.lastProofSubmission = block.timestamp;
            session.lastActivity = block.timestamp;
            session.aggregateProofHash = keccak256(abi.encode(session.aggregateProofHash, submission.proofHash));
        }
        
        return verified;
    }
    
    function getProofSubmissions(uint256 jobId) external view returns (ProofSubmission[] memory) {
        return sessionProofs[jobId];
    }
    
    function getProvenTokens(uint256 jobId) external view returns (uint256) {
        return sessions[jobId].provenTokens;
    }
    
    
    function completeSession(uint256 jobId) external {
        SessionDetails storage session = sessions[jobId];
        require(session.assignedHost == msg.sender);
        require(session.status == SessionStatus.Active);
        session.status = SessionStatus.Completed;
    }
    
    // Test helper function for setting up sessions directly
    function createSessionForTesting(
        uint256 jobId,
        address renter,
        address host,
        uint256 deposit,
        uint256 pricePerToken
    ) external payable {
        // Only for testing - would add access control in production
        jobs[jobId] = Job({
            renter: renter,
            status: JobStatus.Posted,
            assignedHost: host,
            maxPrice: deposit,
            deadline: block.timestamp + 3600,
            completedAt: 0,
            paymentToken: address(0),
            escrowId: bytes32(0),
            modelId: "test",
            promptCID: "test",
            responseCID: ""
        });
        
        sessions[jobId] = SessionDetails({
            depositAmount: deposit,
            pricePerToken: pricePerToken,
            maxDuration: 3600,
            sessionStartTime: block.timestamp,
            assignedHost: host,
            status: SessionStatus.Active,
            provenTokens: 0,
            lastProofSubmission: 0,
            aggregateProofHash: bytes32(0),
            checkpointInterval: 100,
            lastActivity: block.timestamp,
            disputeDeadline: 0
        });
        
        jobTypes[jobId] = JobType.Session;
    }
    
    // Phase 1.4: Proof-Based Completion
    event SessionCompleted(
        uint256 indexed jobId,
        address indexed completedBy,
        uint256 tokensPaid,
        uint256 paymentAmount,
        uint256 refundAmount
    );

    event HostClaimedWithProof(
        uint256 indexed jobId,
        address indexed host,
        uint256 provenTokens,
        uint256 payment
    );
    
    event SessionTimedOut(
        uint256 indexed jobId,
        address indexed triggeredBy,
        uint256 provenTokens,
        uint256 payment
    );
    
    event SessionAbandoned(
        uint256 indexed jobId,
        uint256 inactivityPeriod
    );

    uint256 public constant TREASURY_FEE_PERCENT = 10;
    address public treasuryAddress;
    
    // Timeout constants
    uint256 public constant MIN_SESSION_DURATION = 1 hours;
    uint256 public constant ABANDONMENT_TIMEOUT = 24 hours;
    uint256 public constant DISPUTE_WINDOW = 1 hours;

    function setTreasuryAddress(address _treasury) external {
        treasuryAddress = _treasury;
    }
    
    // Create session with USDC or other ERC20 tokens
    function createSessionJobWithToken(
        address host, address token, uint256 deposit,
        uint256 pricePerToken, uint256 maxDuration, uint256 proofInterval
    ) external returns (uint256 jobId) {
        require(acceptedTokens[token]);
        // Use token-specific minimum deposit
        uint256 minRequired = tokenMinDeposits[token];
        require(minRequired > 0);
        require(deposit >= minRequired);
        require(deposit > 0);
        
        // Add missing validations (same as ETH version)
        require(pricePerToken > 0);
        require(maxDuration > 0 && maxDuration <= 365 days);
        require(proofInterval > 0);
        require(host != address(0));
        require(deposit <= 1000 ether);
        
        // Validate host registration
        (address operator, uint256 stakedAmount, bool active, ) = nodeRegistry.nodes(host);
        require(operator != address(0));
        require(active);
        require(stakedAmount >= nodeRegistry.MIN_STAKE());
        
        // Validate proof requirements
        _validateProofRequirements(proofInterval, deposit, pricePerToken);
        
        // Transfer tokens AFTER all validations pass
        IERC20(token).transferFrom(msg.sender, address(this), deposit);
        
        jobId = nextJobId++;
        jobs[jobId] = Job({
            renter: msg.sender, status: JobStatus.Claimed,
            assignedHost: host, maxPrice: deposit,
            deadline: block.timestamp + maxDuration, completedAt: 0,
            paymentToken: token, escrowId: bytes32(jobId),
            modelId: "", promptCID: "", responseCID: ""
        });
        
        sessions[jobId] = SessionDetails({
            depositAmount: deposit, pricePerToken: pricePerToken,
            maxDuration: maxDuration, sessionStartTime: block.timestamp,
            assignedHost: host, status: SessionStatus.Active,
            provenTokens: 0, lastProofSubmission: 0,
            aggregateProofHash: bytes32(0), checkpointInterval: proofInterval,
            lastActivity: block.timestamp, disputeDeadline: 0
        });
        
        jobTypes[jobId] = JobType.Session;
        emit SessionJobCreatedWithToken(jobId, token, deposit);
    }
    
    // Check if job uses tokens
    function isTokenJob(uint256 jobId) external view returns (bool) {
        // Check if job has a payment token set
        return jobs[jobId].paymentToken != address(0);
    }

    function completeSessionJob(uint256 jobId) external {
        SessionDetails storage session = sessions[jobId];
        require(msg.sender == jobs[jobId].renter);
        require(session.status == SessionStatus.Active);
        
        _processSessionPayment(jobId);
    }

    function claimWithProof(uint256 jobId) external {
        SessionDetails storage session = sessions[jobId];
        require(msg.sender == session.assignedHost);
        require(session.status == SessionStatus.Active);
        require(session.provenTokens > 0);
        
        _processProofBasedPayment(jobId);
    }

    function _calculateProvenPayment(
        uint256 provenTokens,
        uint256 pricePerToken
    ) internal pure returns (uint256 payment, uint256 treasuryFee) {
        uint256 totalPayment = provenTokens * pricePerToken;
        treasuryFee = (totalPayment * TREASURY_FEE_PERCENT) / 100;
        payment = totalPayment - treasuryFee;
    }

    function _processSessionPayment(uint256 jobId) internal {
        SessionDetails storage session = sessions[jobId];
        Job storage job = jobs[jobId];
        
        (uint256 payment, uint256 treasuryFee) = _calculateProvenPayment(
            session.provenTokens,
            session.pricePerToken
        );
        
        uint256 totalCost = session.provenTokens * session.pricePerToken;
        uint256 refund = session.depositAmount > totalCost ? session.depositAmount - totalCost : 0;
        
        _sendPayments(job, session.assignedHost, payment, treasuryFee, refund);
        
        session.status = SessionStatus.Completed;
        session.lastActivity = block.timestamp;
        session.disputeDeadline = block.timestamp + DISPUTE_WINDOW;
        emit SessionCompleted(jobId, msg.sender, session.provenTokens, payment, refund);
    }
    
    function _sendPayments(Job storage job, address host, uint256 payment, uint256 treasuryFee, uint256 refund) internal {
        if (job.paymentToken != address(0)) {
            IERC20 token = IERC20(job.paymentToken);
            
            // Host payment - use HostEarnings if available for gas savings
            if (payment > 0) {
                if (address(hostEarnings) != address(0)) {
                    // Transfer to HostEarnings contract for accumulation
                    require(token.transfer(address(hostEarnings), payment));
                    // Credit the host's balance in HostEarnings
                    hostEarnings.creditEarnings(host, payment, job.paymentToken);
                    emit EarningsCredited(host, payment, job.paymentToken);
                } else {
                    // Fallback to direct transfer if HostEarnings not configured
                    require(token.transfer(host, payment));
                }
            }
            
            if (treasuryFee > 0 && treasuryAddress != address(0)) {
                require(token.transfer(treasuryAddress, treasuryFee));
            }
            if (refund > 0) {
                require(token.transfer(job.renter, refund));
            }
        } else {
            // ETH payments - use HostEarnings if available for gas savings
            if (payment > 0) {
                if (address(hostEarnings) != address(0)) {
                    // Send ETH to HostEarnings contract for accumulation
                    (bool success, ) = payable(address(hostEarnings)).call{value: payment}("");
                    require(success);
                    // Credit the host's balance in HostEarnings
                    hostEarnings.creditEarnings(host, payment, address(0));
                    emit EarningsCredited(host, payment, address(0));
                } else {
                    // Fallback to direct transfer if HostEarnings not configured
                    (bool success, ) = payable(host).call{value: payment}("");
                    require(success);
                }
            }
            
            if (treasuryFee > 0 && treasuryAddress != address(0)) {
                (bool success, ) = payable(treasuryAddress).call{value: treasuryFee}("");
                require(success);
            }
            if (refund > 0) {
                (bool success, ) = payable(job.renter).call{value: refund}("");
                require(success);
            }
        }
    }

    function _processProofBasedPayment(uint256 jobId) internal {
        SessionDetails storage session = sessions[jobId];
        Job storage job = jobs[jobId];
        
        (uint256 payment, uint256 treasuryFee) = _calculateProvenPayment(
            session.provenTokens,
            session.pricePerToken
        );
        
        _sendPayments(job, session.assignedHost, payment, treasuryFee, 0);
        
        session.status = SessionStatus.Completed;
        emit HostClaimedWithProof(jobId, msg.sender, session.provenTokens, payment);
    }
    
    // Timeout & Abandonment Functions
    
    function triggerSessionTimeout(uint256 jobId) external {
        SessionDetails storage session = sessions[jobId];
        require(session.status == SessionStatus.Active);
        require(_isSessionExpired(jobId));
        
        _processTimeoutPayment(jobId);
    }
    
    function claimAbandonedSession(uint256 jobId) external {
        SessionDetails storage session = sessions[jobId];
        require(msg.sender == session.assignedHost);
        require(session.status == SessionStatus.Active);
        require(_isSessionAbandoned(jobId));
        require(session.provenTokens > 0);
        
        _processAbandonmentClaim(jobId);
    }
    
    function _isSessionExpired(uint256 jobId) internal view returns (bool) {
        SessionDetails storage session = sessions[jobId];
        if (session.maxDuration == 0) return false;
        
        return block.timestamp > session.sessionStartTime + session.maxDuration;
    }
    
    function _isSessionAbandoned(uint256 jobId) internal view returns (bool) {
        SessionDetails storage session = sessions[jobId];
        
        return block.timestamp > session.lastActivity + ABANDONMENT_TIMEOUT;
    }
    
    function _processTimeoutPayment(uint256 jobId) internal {
        SessionDetails storage session = sessions[jobId];
        Job storage job = jobs[jobId];
        uint256 payment = 0;
        
        if (session.provenTokens > 0) {
            (uint256 basePayment, uint256 treasuryFee) = _calculateProvenPayment(
                session.provenTokens,
                session.pricePerToken
            );
            payment = (basePayment * 90) / 100; // 10% penalty
            uint256 totalCost = session.provenTokens * session.pricePerToken;
            uint256 refund = session.depositAmount > totalCost ? session.depositAmount - totalCost : 0;
            _sendPayments(job, session.assignedHost, payment, treasuryFee, refund);
        } else {
            // No proven work, refund full deposit
            if (session.depositAmount > 0) {
                _sendPayments(job, address(0), 0, 0, session.depositAmount);
            }
        }
        
        session.status = SessionStatus.TimedOut;
        emit SessionTimedOut(jobId, msg.sender, session.provenTokens, payment);
    }
    
    function _processAbandonmentClaim(uint256 jobId) internal {
        SessionDetails storage session = sessions[jobId];
        Job storage job = jobs[jobId];
        
        (uint256 payment, uint256 treasuryFee) = _calculateProvenPayment(
            session.provenTokens,
            session.pricePerToken
        );
        
        uint256 totalCost = session.provenTokens * session.pricePerToken;
        uint256 refund = session.depositAmount > totalCost ? session.depositAmount - totalCost : 0;
        
        _sendPayments(job, session.assignedHost, payment, treasuryFee, refund);
        
        session.status = SessionStatus.Abandoned;
        emit SessionAbandoned(jobId, block.timestamp - session.lastActivity);
    }
    
    function getTokenBalance(address token) external view returns (uint256) {
        if (token == address(0)) return address(this).balance;
        return IERC20(token).balanceOf(address(this));
    }
    
    // Emergency withdrawal for stuck funds (simplified to save gas)
    event EmergencyWithdrawal(address indexed recipient, uint256 amount, address token);
    
    function emergencyWithdraw(address token) external nonReentrant {
        require(msg.sender == treasuryAddress);
        
        uint256 amount;
        if (token == address(0)) {
            amount = address(this).balance;
            require(amount > 0);
            (bool ok, ) = payable(treasuryAddress).call{value: amount}("");
            require(ok);
        } else {
            IERC20 t = IERC20(token);
            amount = t.balanceOf(address(this));
            require(amount > 0);
            require(t.transfer(treasuryAddress, amount));
        }
        
        emit EmergencyWithdrawal(treasuryAddress, amount, token);
    }
    
    // View functions for hosts (read-only, no gas costs)
    
    function getActiveSessionsForHost(address host) 
        external view returns (uint256[] memory jobIds) {
        uint256 count = 0;
        uint256 maxCheck = 1000; // Reasonable max for view function
        
        // Count active sessions
        for (uint256 i = 1; i <= maxCheck; i++) {
            if (sessions[i].assignedHost == host && 
                sessions[i].status == SessionStatus.Active) {
                count++;
            }
        }
        
        // Populate array
        jobIds = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= maxCheck; i++) {
            if (sessions[i].assignedHost == host && 
                sessions[i].status == SessionStatus.Active) {
                jobIds[index++] = i;
            }
        }
    }
}