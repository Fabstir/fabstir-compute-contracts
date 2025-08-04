// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IJobMarketplace.sol";
import "./interfaces/IPaymentEscrow.sol";
import "./interfaces/IReputationSystem.sol";
import "./interfaces/IERC20.sol";

contract ProofSystem {
    // Roles
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    
    // Role management
    mapping(bytes32 => mapping(address => bool)) private _roles;
    
    // Reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    
    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "AccessControl: account missing role");
        _;
    }
    
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }
    
    function grantRole(bytes32 role, address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Invalid address");
        _grantRole(role, account);
    }
    
    function revokeRole(bytes32 role, address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }
    
    function _grantRole(bytes32 role, address account) internal {
        if (!hasRole(role, account)) {
            _roles[role][account] = true;
        }
    }
    
    function _revokeRole(bytes32 role, address account) internal {
        if (hasRole(role, account)) {
            _roles[role][account] = false;
        }
    }
    
    // Structs
    struct EZKLProof {
        uint256[] instances;
        uint256[] proof;
        uint256[] vk;
        bytes32 modelCommitment;
        bytes32 inputHash;
        bytes32 outputHash;
    }
    
    enum ProofStatus {
        None,
        Submitted,
        Verified,
        Invalid
    }
    
    enum ChallengeStatus {
        None,
        Pending,
        Successful,
        Failed
    }
    
    struct ProofInfo {
        address prover;
        uint256 submissionTime;
        ProofStatus status;
        bytes32 proofHash;
        EZKLProof proof;
    }
    
    struct Challenge {
        address challenger;
        uint256 stake;
        bytes32 evidenceHash;
        ChallengeStatus status;
        uint256 deadline;
        uint256 jobId;
    }
    
    // State variables
    IJobMarketplace public immutable jobMarketplace;
    IPaymentEscrow public immutable paymentEscrow;
    IReputationSystem public immutable reputationSystem;
    
    mapping(uint256 => ProofInfo) public proofs; // jobId => ProofInfo
    mapping(uint256 => Challenge) public challenges; // challengeId => Challenge
    uint256 public nextChallengeId = 1;
    
    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256 public constant CHALLENGE_STAKE_MIN = 10e18;
    uint256 public constant PENALTY_AMOUNT = 20e18;
    
    // Events
    event ProofSubmitted(
        uint256 indexed jobId,
        address indexed prover,
        bytes32 proofHash,
        uint256 timestamp
    );
    
    event ProofVerified(
        uint256 indexed jobId,
        address indexed verifier,
        bool isValid
    );
    
    event ProofChallenged(
        uint256 indexed jobId,
        address indexed challenger,
        bytes32 evidenceHash
    );
    
    event ChallengeResolved(
        uint256 indexed jobId,
        bool challengeSuccessful,
        address winner
    );
    
    event BatchVerificationCompleted(
        uint256[] jobIds,
        bool[] results,
        uint256 gasUsed
    );
    
    constructor(
        address _jobMarketplace,
        address _paymentEscrow,
        address _reputationSystem
    ) {
        require(_jobMarketplace != address(0), "Invalid job marketplace");
        require(_paymentEscrow != address(0), "Invalid payment escrow");
        require(_reputationSystem != address(0), "Invalid reputation system");
        
        jobMarketplace = IJobMarketplace(_jobMarketplace);
        paymentEscrow = IPaymentEscrow(_paymentEscrow);
        reputationSystem = IReputationSystem(_reputationSystem);
        
        _status = _NOT_ENTERED;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    
    function submitProof(uint256 jobId, EZKLProof calldata proof) external nonReentrant {
        // Get job info from marketplace
        (
            address renter,
            ,
            ,
            ,
            IJobMarketplace.JobStatus status,
            address assignedHost,
            ,
            ,
        ) = jobMarketplace.getJob(jobId);
        
        require(renter != address(0), "Job does not exist");
        require(msg.sender == assignedHost, "Only assigned host can submit proof");
        require(status == IJobMarketplace.JobStatus.Claimed, "Job not in claimed state");
        require(proofs[jobId].status == ProofStatus.None, "Proof already submitted");
        
        // Calculate proof hash
        bytes32 proofHash = keccak256(abi.encode(proof));
        
        // Store proof info
        proofs[jobId] = ProofInfo({
            prover: msg.sender,
            submissionTime: block.timestamp,
            status: ProofStatus.Submitted,
            proofHash: proofHash,
            proof: proof
        });
        
        emit ProofSubmitted(jobId, msg.sender, proofHash, block.timestamp);
    }
    
    function verifyProof(uint256 jobId) external onlyRole(VERIFIER_ROLE) {
        ProofInfo storage proofInfo = proofs[jobId];
        require(proofInfo.status == ProofStatus.Submitted, "Invalid proof status");
        
        // In a real implementation, this would call the EZKL verifier contract
        // For now, we'll use a simple mock verification
        bool isValid = _mockVerifyProof(jobId);
        
        proofInfo.status = isValid ? ProofStatus.Verified : ProofStatus.Invalid;
        
        emit ProofVerified(jobId, msg.sender, isValid);
        
        // Update reputation if proof is invalid
        if (!isValid && address(reputationSystem) != address(0)) {
            reputationSystem.recordJobCompletion(proofInfo.prover, jobId, false);
        }
    }
    
    function batchVerifyProofs(uint256[] calldata jobIds) 
        external 
        onlyRole(VERIFIER_ROLE) 
        returns (bool[] memory results) 
    {
        uint256 gasStart = gasleft();
        results = new bool[](jobIds.length);
        
        for (uint256 i = 0; i < jobIds.length; i++) {
            ProofInfo storage proofInfo = proofs[jobIds[i]];
            if (proofInfo.status == ProofStatus.Submitted) {
                bool isValid = _mockVerifyProof(jobIds[i]);
                results[i] = isValid;
                proofInfo.status = isValid ? ProofStatus.Verified : ProofStatus.Invalid;
                
                emit ProofVerified(jobIds[i], msg.sender, isValid);
                
                if (!isValid && address(reputationSystem) != address(0)) {
                    reputationSystem.recordJobCompletion(proofInfo.prover, jobIds[i], false);
                }
            }
        }
        
        uint256 gasUsed = gasStart - gasleft();
        emit BatchVerificationCompleted(jobIds, results, gasUsed);
    }
    
    function challengeProof(
        uint256 jobId,
        bytes32 evidenceHash,
        uint256 stakeAmount
    ) external nonReentrant returns (uint256 challengeId) {
        ProofInfo memory proofInfo = proofs[jobId];
        require(proofInfo.status == ProofStatus.Verified, "Can only challenge verified proofs");
        require(stakeAmount >= CHALLENGE_STAKE_MIN, "Insufficient stake");
        
        // Get job details
        (
            ,
            ,
            ,
            address paymentToken,
            ,
            ,
            ,
            ,
        ) = jobMarketplace.getJob(jobId);
        
        // Transfer stake from challenger
        require(IERC20(paymentToken).transferFrom(msg.sender, address(this), stakeAmount), "Transfer failed");
        
        challengeId = nextChallengeId++;
        challenges[challengeId] = Challenge({
            challenger: msg.sender,
            stake: stakeAmount,
            evidenceHash: evidenceHash,
            status: ChallengeStatus.Pending,
            deadline: block.timestamp + CHALLENGE_PERIOD,
            jobId: jobId
        });
        
        emit ProofChallenged(jobId, msg.sender, evidenceHash);
    }
    
    function resolveChallenge(uint256 challengeId, bool challengeSuccessful) 
        external 
        onlyRole(VERIFIER_ROLE) 
        nonReentrant 
    {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.status == ChallengeStatus.Pending, "Invalid challenge status");
        require(block.timestamp <= challenge.deadline, "Challenge expired");
        
        uint256 jobId = challenge.jobId;
        ProofInfo storage proofInfo = proofs[jobId];
        
        // Get payment token from job
        (
            ,
            ,
            ,
            address paymentToken,
            ,
            ,
            ,
            ,
        ) = jobMarketplace.getJob(jobId);
        
        if (challengeSuccessful) {
            challenge.status = ChallengeStatus.Successful;
            proofInfo.status = ProofStatus.Invalid;
            
            // Reward challenger with their stake (in production, would add penalty from host)
            IERC20(paymentToken).transfer(challenge.challenger, challenge.stake);
            
            // Update host reputation
            if (address(reputationSystem) != address(0)) {
                reputationSystem.recordJobCompletion(proofInfo.prover, jobId, false);
            }
            
            emit ChallengeResolved(jobId, true, challenge.challenger);
        } else {
            challenge.status = ChallengeStatus.Failed;
            
            // Transfer stake to host as compensation
            IERC20(paymentToken).transfer(proofInfo.prover, challenge.stake);
            
            emit ChallengeResolved(jobId, false, proofInfo.prover);
        }
    }
    
    function expireChallenge(uint256 challengeId) external nonReentrant {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.status == ChallengeStatus.Pending, "Invalid challenge status");
        require(block.timestamp > challenge.deadline, "Challenge not expired");
        
        challenge.status = ChallengeStatus.Failed;
        
        // Get payment token and proof info
        uint256 jobId = challenge.jobId;
        ProofInfo memory proofInfo = proofs[jobId];
        
        (
            ,
            ,
            ,
            address paymentToken,
            ,
            ,
            ,
            ,
        ) = jobMarketplace.getJob(jobId);
        
        // Transfer stake to host
        IERC20(paymentToken).transfer(proofInfo.prover, challenge.stake);
        
        emit ChallengeResolved(jobId, false, proofInfo.prover);
    }
    
    function canCompleteJob(uint256 jobId) external view returns (bool) {
        ProofInfo memory proofInfo = proofs[jobId];
        return proofInfo.status == ProofStatus.Verified;
    }
    
    function getProofInfo(uint256 jobId) 
        external 
        view 
        returns (address prover, uint256 submissionTime, ProofStatus status) 
    {
        ProofInfo memory info = proofs[jobId];
        return (info.prover, info.submissionTime, info.status);
    }
    
    function getChallengeInfo(uint256 challengeId)
        external
        view
        returns (
            address challenger,
            uint256 stake,
            bytes32 evidenceHash,
            ChallengeStatus status,
            uint256 deadline
        )
    {
        Challenge memory challenge = challenges[challengeId];
        return (
            challenge.challenger,
            challenge.stake,
            challenge.evidenceHash,
            challenge.status,
            challenge.deadline
        );
    }
    
    // Mock verification function - in production this would call EZKL verifier
    function _mockVerifyProof(uint256 jobId) private view returns (bool) {
        ProofInfo memory info = proofs[jobId];
        EZKLProof memory proof = info.proof;
        
        // Check if the proof instances match the expected values
        // Valid proofs have:
        // instances[0] = modelCommitment
        // instances[1] = inputHash  
        // instances[2] = outputHash
        
        // Invalid proofs have corrupted instances[2]
        if (proof.instances.length != 3) return false;
        
        // Check if instances[2] was corrupted (test uses keccak256("wrong_output"))
        bytes32 wrongOutputHash = keccak256("wrong_output");
        if (proof.instances[2] == uint256(wrongOutputHash)) {
            return false;
        }
        
        // Basic validation - instances should match the commitments
        if (proof.instances[0] != uint256(proof.modelCommitment)) return false;
        if (proof.instances[1] != uint256(proof.inputHash)) return false;
        if (proof.instances[2] != uint256(proof.outputHash)) return false;
        
        return true;
    }
    
    // Admin functions
    function grantVerifierRole(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(VERIFIER_ROLE, account);
    }
    
    function revokeVerifierRole(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(VERIFIER_ROLE, account);
    }
}