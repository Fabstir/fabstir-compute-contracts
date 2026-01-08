// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./NodeRegistryWithModelsUpgradeable.sol";
import "./interfaces/IJobMarketplace.sol";
// REMOVED: import "./interfaces/IReputationSystem.sol"; (never used)
import "./HostEarningsUpgradeable.sol";
import "./utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Proof system interface
interface IProofSystemUpgradeable {
    function verifyEKZL(bytes calldata proof, address prover, uint256 claimedTokens) external view returns (bool);

    function verifyAndMarkComplete(bytes calldata proof, address prover, uint256 claimedTokens)
        external
        returns (bool);
}

/**
 * @title JobMarketplaceWithModelsUpgradeable
 * @dev UUPS upgradeable version of JobMarketplaceWithModels
 * @notice Stores prompts and responses as S5 CIDs with model validation support
 */
contract JobMarketplaceWithModelsUpgradeable is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // Session status enum
    // Note: Only Active, Completed, TimedOut are used. Disputed/Abandoned/Cancelled
    // were removed in Phase 7 cleanup as they were never implemented.
    enum SessionStatus {
        Active,
        Completed,
        TimedOut
    }

    // EZKL proof tracking structure
    struct ProofSubmission {
        bytes32 proofHash;
        uint256 tokensClaimed;
        uint256 timestamp;
        bool verified;
    }

    // Session job structure
    struct SessionJob {
        uint256 id;
        address depositor; // Tracks who deposited and who receives refunds
        address host;
        address paymentToken;
        uint256 deposit;
        uint256 pricePerToken;
        uint256 tokensUsed;
        uint256 maxDuration;
        uint256 startTime;
        uint256 lastProofTime;
        uint256 proofInterval;
        SessionStatus status;
        ProofSubmission[] proofs;
        uint256 withdrawnByHost;
        uint256 refundedToUser;
        string conversationCID;
        bytes32 lastProofHash; // S5: Hash of most recent proof (32 bytes)
        string lastProofCID; // S5: CID of most recent proof in S5 storage
    }

    // Chain configuration structure (Phase 4.1)
    struct ChainConfig {
        address nativeWrapper; // WETH on Base, WBNB on opBNB
        address stablecoin; // USDC address per chain
        uint256 minDeposit; // Chain-specific minimum
        string nativeTokenSymbol; // "ETH" or "BNB"
    }

    // Session creation parameters (Phase 5 - Code Deduplication)
    struct SessionParams {
        address host;
        address paymentToken;
        uint256 deposit;
        uint256 pricePerToken;
        uint256 maxDuration;
        uint256 proofInterval;
        bytes32 modelId;  // bytes32(0) if no model
    }

    // Constants (non-upgradeable)
    uint256 public constant MIN_DEPOSIT = 0.0001 ether; // ~$0.50 @ $5000/ETH
    uint256 public constant MIN_PROVEN_TOKENS = 100;
    // REMOVED: ABANDONMENT_TIMEOUT was defined but never used

    /// @notice Time window before non-depositor can complete session (default 30s)
    uint256 public disputeWindow;

    /// @notice Treasury fee in basis points (1000 = 10%)
    uint256 public feeBasisPoints;

    // State variables
    mapping(uint256 => SessionJob) public sessionJobs;
    mapping(address => uint256[]) public userSessions;
    mapping(address => uint256[]) public hostSessions;

    // Session model tracking (sessionId => modelId) - Phase 3.1
    mapping(uint256 => bytes32) public sessionModel;

    uint256 public nextJobId;
    address public treasuryAddress;
    address public usdcAddress;

    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    IProofSystemUpgradeable public proofSystem;
    HostEarningsUpgradeable public hostEarnings;

    // USDC-specific configuration
    uint256 public constant USDC_MIN_DEPOSIT = 500000; // 0.50 USDC

    // Price precision: prices are stored with 1000x precision for sub-cent granularity
    // Payment calculation: (tokensUsed * pricePerToken) / PRICE_PRECISION
    uint256 public constant PRICE_PRECISION = 1000;

    mapping(address => bool) public acceptedTokens;
    mapping(address => uint256) public tokenMinDeposits;

    // Treasury accumulation mappings
    uint256 public accumulatedTreasuryNative;
    mapping(address => uint256) public accumulatedTreasuryTokens;

    // Wallet-agnostic deposit tracking (Phase 1.1)
    mapping(address => uint256) public userDepositsNative;
    mapping(address => mapping(address => uint256)) public userDepositsToken;

    // Chain configuration storage (Phase 4.1)
    ChainConfig public chainConfig;

    // Storage gap for future upgrades
    uint256[35] private __gap;

    // Events
    event SessionJobCreated(uint256 indexed jobId, address indexed depositor, address indexed host, uint256 deposit);
    event ProofSubmitted(
        uint256 indexed jobId, address indexed host, uint256 tokensClaimed, bytes32 proofHash, string proofCID
    );
    event SessionCompleted(uint256 indexed jobId, uint256 totalTokensUsed, uint256 hostEarnings, uint256 userRefund);
    // New event that tracks who completed the session (Phase 3.1 - Anyone-can-complete pattern)
    event SessionCompletedBy(
        uint256 indexed jobId,
        address indexed completedBy,
        uint256 tokensUsed,
        uint256 paymentAmount,
        uint256 refundAmount
    );
    event SessionTimedOut(uint256 indexed jobId, uint256 hostEarnings, uint256 userRefund);
    // REMOVED in Phase 7: event SessionAbandoned - was never emitted
    event PaymentSent(address indexed recipient, uint256 amount);
    event TreasuryWithdrawal(address indexed token, uint256 amount);

    // Wallet-agnostic deposit events (Phase 1.1)
    event DepositReceived( // address(0) for native
    address indexed depositor, uint256 amount, address indexed token);

    event WithdrawalProcessed( // address(0) for native
    address indexed depositor, uint256 amount, address indexed token);

    // Session events using depositor terminology (Phase 2.1)
    event SessionCreatedByDepositor(
        uint256 indexed sessionId, address indexed depositor, address indexed host, uint256 deposit
    );

    // Token acceptance event (Phase 2.4)
    event TokenAccepted(address indexed token, uint256 minDeposit);
    event TokenMinDepositUpdated(address indexed token, uint256 oldMinDeposit, uint256 newMinDeposit);

    // Model-aware session event (Phase 3.2)
    event SessionJobCreatedForModel(
        uint256 indexed jobId, address indexed depositor, address indexed host, bytes32 modelId, uint256 deposit
    );

    // Pause events
    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);

    modifier onlyRegisteredHost(address host) {
        // Just check if host is registered by looking at operator
        // NodeRegistryWithModels has different return signature
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the upgradeable contract
     * @param _nodeRegistry Address of the NodeRegistryWithModels contract
     * @param _hostEarnings Address of the HostEarnings contract
     * @param _feeBasisPoints Treasury fee in basis points (e.g., 1000 = 10%)
     * @param _disputeWindow Dispute window duration in seconds
     */
    function initialize(
        address _nodeRegistry,
        address payable _hostEarnings,
        uint256 _feeBasisPoints,
        uint256 _disputeWindow
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        // Note: OZ 5.x UUPSUpgradeable doesn't require __UUPSUpgradeable_init()

        require(_nodeRegistry != address(0), "Invalid node registry");
        require(_hostEarnings != address(0), "Invalid host earnings");
        require(_feeBasisPoints <= 10000, "Fee cannot exceed 100%");
        require(_disputeWindow > 0 && _disputeWindow <= 7 days, "Invalid dispute window");

        feeBasisPoints = _feeBasisPoints;
        disputeWindow = _disputeWindow;
        nodeRegistry = NodeRegistryWithModelsUpgradeable(_nodeRegistry);
        hostEarnings = HostEarningsUpgradeable(_hostEarnings);

        // Set defaults
        nextJobId = 1;
        treasuryAddress = msg.sender;
        usdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

        // Initialize accepted tokens
        acceptedTokens[usdcAddress] = true;
        tokenMinDeposits[usdcAddress] = USDC_MIN_DEPOSIT;
    }

    /**
     * @notice Authorize upgrade (owner only)
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============================================================
    // Emergency Pause Functions
    // ============================================================

    /**
     * @notice Pause the contract (treasury or owner only)
     * @dev Blocks session creation and proof submission
     */
    function pause() external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Only treasury or owner");
        _pause();
        emit ContractPaused(msg.sender);
    }

    /**
     * @notice Unpause the contract (treasury or owner only)
     */
    function unpause() external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Only treasury or owner");
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    // ============================================================
    // Admin Functions
    // ============================================================

    function setProofSystem(address _proofSystem) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Only treasury or owner");
        proofSystem = IProofSystemUpgradeable(_proofSystem);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasuryAddress = _treasury;
    }

    function setUsdcAddress(address _usdc) external onlyOwner {
        require(_usdc != address(0), "Invalid USDC address");

        // Remove old USDC from accepted tokens if it exists
        if (usdcAddress != address(0) && acceptedTokens[usdcAddress]) {
            acceptedTokens[usdcAddress] = false;
        }

        // Set new USDC address and add to accepted tokens
        usdcAddress = _usdc;
        acceptedTokens[_usdc] = true;
        tokenMinDeposits[_usdc] = USDC_MIN_DEPOSIT;
    }

    // Initialize chain configuration (Phase 4.1)
    function initializeChainConfig(ChainConfig memory _config) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Only treasury or owner");
        require(chainConfig.nativeWrapper == address(0), "Already initialized");
        chainConfig = _config;
    }

    // ============================================================
    // Session Creation Functions
    // ============================================================

    function createSessionJob(address host, uint256 pricePerToken, uint256 maxDuration, uint256 proofInterval)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 jobId)
    {
        require(msg.value >= MIN_DEPOSIT, "Insufficient deposit");

        SessionParams memory params = SessionParams({
            host: host,
            paymentToken: address(0),
            deposit: msg.value,
            pricePerToken: pricePerToken,
            maxDuration: maxDuration,
            proofInterval: proofInterval,
            modelId: bytes32(0)
        });

        _validateSessionParams(params);

        // Validate price meets host's minimum for native token (ETH/BNB)
        uint256 hostMinPrice = nodeRegistry.getNodePricing(host, address(0));
        require(pricePerToken >= hostMinPrice, "Price below host minimum");

        jobId = nextJobId++;
        _initializeSession(jobId, params);

        emit SessionJobCreated(jobId, msg.sender, host, msg.value);
        emit SessionCreatedByDepositor(jobId, msg.sender, host, msg.value);

        return jobId;
    }

    /// @notice Create a session job for a specific model with native token payment
    function createSessionJobForModel(
        address host,
        bytes32 modelId,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval
    ) external payable nonReentrant whenNotPaused returns (uint256 jobId) {
        require(msg.value >= MIN_DEPOSIT, "Insufficient deposit");

        SessionParams memory params = SessionParams({
            host: host,
            paymentToken: address(0),
            deposit: msg.value,
            pricePerToken: pricePerToken,
            maxDuration: maxDuration,
            proofInterval: proofInterval,
            modelId: modelId
        });

        // Validates host registration before model check (security requirement)
        _validateSessionParams(params);

        // Model-specific validations
        require(nodeRegistry.nodeSupportsModel(host, modelId), "Host does not support model");

        // Get model-specific pricing (falls back to default if not set)
        uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, address(0));
        require(pricePerToken >= hostMinPrice, "Price below host minimum for model");

        jobId = nextJobId++;
        sessionModel[jobId] = modelId;
        _initializeSession(jobId, params);

        emit SessionJobCreated(jobId, msg.sender, host, msg.value);
        emit SessionJobCreatedForModel(jobId, msg.sender, host, modelId, msg.value);

        return jobId;
    }

    function createSessionJobWithToken(
        address host,
        address token,
        uint256 deposit,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval
    ) external nonReentrant whenNotPaused returns (uint256 jobId) {
        // Token-specific validations
        require(acceptedTokens[token], "Token not accepted");
        uint256 minRequired = tokenMinDeposits[token];
        require(minRequired > 0, "Token not configured");
        require(deposit >= minRequired, "Insufficient deposit");
        require(deposit > 0, "Zero deposit");

        SessionParams memory params = SessionParams({
            host: host,
            paymentToken: token,
            deposit: deposit,
            pricePerToken: pricePerToken,
            maxDuration: maxDuration,
            proofInterval: proofInterval,
            modelId: bytes32(0)
        });

        _validateSessionParams(params);

        // Validate price meets host's minimum for the specified token (USDC or other stablecoin)
        uint256 hostMinPrice = nodeRegistry.getNodePricing(host, token);
        require(pricePerToken >= hostMinPrice, "Price below host minimum");

        // Transfer tokens after all validations pass
        IERC20(token).safeTransferFrom(msg.sender, address(this), deposit);

        jobId = nextJobId++;
        _initializeSession(jobId, params);

        emit SessionJobCreated(jobId, msg.sender, host, deposit);
        emit SessionCreatedByDepositor(jobId, msg.sender, host, deposit);

        return jobId;
    }

    /// @notice Create a session job for a specific model with token payment
    function createSessionJobForModelWithToken(
        address host,
        bytes32 modelId,
        address token,
        uint256 deposit,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval
    ) external nonReentrant whenNotPaused returns (uint256 jobId) {
        // Token-specific validations
        require(acceptedTokens[token], "Token not accepted");
        uint256 minRequired = tokenMinDeposits[token];
        require(minRequired > 0, "Token not configured");
        require(deposit >= minRequired, "Insufficient deposit");
        require(deposit > 0, "Zero deposit");

        SessionParams memory params = SessionParams({
            host: host,
            paymentToken: token,
            deposit: deposit,
            pricePerToken: pricePerToken,
            maxDuration: maxDuration,
            proofInterval: proofInterval,
            modelId: modelId
        });

        // Validates host registration before model check (security requirement)
        _validateSessionParams(params);

        // Model-specific validations
        require(nodeRegistry.nodeSupportsModel(host, modelId), "Host does not support model");

        // Get model-specific pricing for this token (falls back to default stable if not set)
        uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, token);
        require(pricePerToken >= hostMinPrice, "Price below host minimum for model");

        // Transfer tokens after all validations pass
        IERC20(token).safeTransferFrom(msg.sender, address(this), deposit);

        jobId = nextJobId++;
        sessionModel[jobId] = modelId;
        _initializeSession(jobId, params);

        emit SessionJobCreated(jobId, msg.sender, host, deposit);
        emit SessionJobCreatedForModel(jobId, msg.sender, host, modelId, deposit);

        return jobId;
    }

    // ============================================================
    // Internal Validation Functions
    // ============================================================

    /**
     * @notice Validate that host is registered and active in NodeRegistry
     * @dev Queries NodeRegistry for host registration status and active flag
     * @param host Address of the host to validate
     */
    function _validateHostRegistration(address host) internal view {
        require(host != address(0), "Invalid host address");

        // Query NodeRegistry for host info
        (
            address operator,
            , // stakedAmount
            bool active,
            , // metadata
            , // apiUrl
            , // supportedModels
            , // minPricePerTokenNative
                // minPricePerTokenStable
        ) = nodeRegistry.getNodeFullInfo(host);

        require(operator != address(0), "Host not registered");
        require(active, "Host not active");
    }

    function _validateProofRequirements(uint256 proofInterval, uint256 deposit, uint256 pricePerToken) internal pure {
        // With PRICE_PRECISION: maxTokens = deposit * PRICE_PRECISION / pricePerToken
        uint256 maxTokens = (deposit * PRICE_PRECISION) / pricePerToken;
        uint256 tokensPerProof = proofInterval;
        require(tokensPerProof >= MIN_PROVEN_TOKENS, "Proof interval too small");
        require(maxTokens >= tokensPerProof, "Deposit too small for proof interval");
    }

    // ============================================================
    // Session Creation Helpers (Phase 5 - Code Deduplication)
    // ============================================================

    /**
     * @notice Validate common session parameters
     * @dev Checks price, duration, proof interval, and host address
     * @param params Session parameters to validate
     */
    function _validateSessionParams(SessionParams memory params) internal view {
        require(params.pricePerToken > 0, "Invalid price");
        require(params.maxDuration > 0 && params.maxDuration <= 365 days, "Invalid duration");
        require(params.proofInterval > 0, "Invalid proof interval");
        require(params.host != address(0), "Invalid host");
        require(params.deposit <= 1000 ether, "Deposit too large");

        _validateHostRegistration(params.host);
        _validateProofRequirements(params.proofInterval, params.deposit, params.pricePerToken);
    }

    /**
     * @notice Initialize session storage with common fields
     * @dev Sets all session fields and updates tracking mappings
     * @param jobId The job ID for the session
     * @param params Session parameters
     * @return session Storage pointer to the initialized session
     */
    function _initializeSession(
        uint256 jobId,
        SessionParams memory params
    ) internal returns (SessionJob storage session) {
        session = sessionJobs[jobId];
        session.id = jobId;
        session.depositor = msg.sender;
        session.host = params.host;
        session.paymentToken = params.paymentToken;
        session.deposit = params.deposit;
        session.pricePerToken = params.pricePerToken;
        session.maxDuration = params.maxDuration;
        session.startTime = block.timestamp;
        session.lastProofTime = block.timestamp;
        session.proofInterval = params.proofInterval;
        session.status = SessionStatus.Active;

        // Track session for user and host
        userSessions[msg.sender].push(jobId);
        hostSessions[params.host].push(jobId);

        return session;
    }

    // ============================================================
    // Proof Submission
    // ============================================================

    function submitProofOfWork(
        uint256 jobId,
        uint256 tokensClaimed,
        bytes32 proofHash,
        bytes calldata signature,
        string calldata proofCID
    ) external nonReentrant whenNotPaused {
        SessionJob storage session = sessionJobs[jobId];
        require(session.status == SessionStatus.Active, "Session not active");
        require(msg.sender == session.host, "Only host can submit proof");
        require(tokensClaimed >= MIN_PROVEN_TOKENS, "Must claim minimum tokens");
        require(signature.length == 65, "Invalid signature length");

        uint256 timeSinceLastProof = block.timestamp - session.lastProofTime;
        // Rate limit: 1000 tokens/sec base * 2x buffer = 2000 tokens/sec max
        uint256 expectedTokens = timeSinceLastProof * 1000;
        require(tokensClaimed <= expectedTokens * 2, "Excessive tokens claimed");

        uint256 newTotal = session.tokensUsed + tokensClaimed;
        // With PRICE_PRECISION: maxTokens = deposit * PRICE_PRECISION / pricePerToken
        uint256 maxTokens = (session.deposit * PRICE_PRECISION) / session.pricePerToken;
        require(newTotal <= maxTokens, "Exceeds deposit");

        // VERIFY PROOF via ProofSystem (Phase 6.2)
        bool verified = false;
        if (address(proofSystem) != address(0)) {
            // Construct 97-byte proof: proofHash (32) + signature (65)
            bytes memory proof = abi.encodePacked(proofHash, signature);
            require(
                proofSystem.verifyAndMarkComplete(proof, msg.sender, tokensClaimed),
                "Invalid proof signature"
            );
            verified = true;
        }

        // S5: Store proof hash and CID instead of full proof
        session.lastProofHash = proofHash;
        session.lastProofCID = proofCID;

        // Store proof submission with verification status
        session.proofs.push(
            ProofSubmission({
                proofHash: proofHash,
                tokensClaimed: tokensClaimed,
                timestamp: block.timestamp,
                verified: verified
            })
        );

        session.tokensUsed = newTotal;
        session.lastProofTime = block.timestamp;

        emit ProofSubmitted(jobId, msg.sender, tokensClaimed, proofHash, proofCID);
    }

    // ============================================================
    // Session Completion
    // ============================================================

    /**
     * @notice Complete an active session and settle payments
     * @dev Only the depositor or host can complete a session:
     *      - Depositor can complete immediately (no dispute window)
     *      - Host must wait for disputeWindow (default 30s) to complete
     *
     *      This restriction ensures only authorized parties can set the
     *      conversationCID (IPFS reference to conversation record).
     *
     *      PROOF-THEN-SETTLE ARCHITECTURE:
     *      - Proof of work happens in submitProofOfWork() which requires host signature
     *      - This function ONLY settles based on already-proven work (tokensUsed)
     *      - If no proofs were submitted, tokensUsed=0 and host receives $0
     *      - User receives refund of (deposit - payment to host)
     *
     *      Compare with triggerSessionTimeout() which handles forced endings
     *      and can be called by anyone when timeout conditions are met.
     *
     * @param jobId The session ID to complete
     * @param conversationCID IPFS CID of the conversation record (for audit trail)
     */
    function completeSessionJob(uint256 jobId, string calldata conversationCID) external nonReentrant {
        SessionJob storage session = sessionJobs[jobId];
        require(session.status == SessionStatus.Active, "Session not active");

        // Only depositor or host can complete and set conversationCID
        require(
            msg.sender == session.depositor || msg.sender == session.host,
            "Only depositor or host can complete"
        );

        // Dispute window only waived for the original depositor
        if (msg.sender != session.depositor) {
            require(block.timestamp >= session.startTime + disputeWindow, "Must wait dispute window");
        }

        session.status = SessionStatus.Completed;
        session.conversationCID = conversationCID;

        _settleSessionPayments(jobId, msg.sender);
    }

    function _settleSessionPayments(uint256 jobId, address completedBy) internal {
        SessionJob storage session = sessionJobs[jobId];

        // With PRICE_PRECISION: hostPayment = (tokensUsed * pricePerToken) / PRICE_PRECISION
        uint256 hostPayment = (session.tokensUsed * session.pricePerToken) / PRICE_PRECISION;
        uint256 userRefund = session.deposit > hostPayment ? session.deposit - hostPayment : 0;

        if (hostPayment > 0) {
            // Calculate fees based on feeBasisPoints
            uint256 treasuryFee = (hostPayment * feeBasisPoints) / 10000;
            uint256 netHostPayment = hostPayment - treasuryFee;

            if (session.paymentToken == address(0)) {
                accumulatedTreasuryNative += treasuryFee;
                // Send ETH to HostEarnings contract
                (bool sent,) = payable(address(hostEarnings)).call{value: netHostPayment}("");
                require(sent, "ETH transfer to HostEarnings failed");
                // Credit the host's earnings
                hostEarnings.creditEarnings(session.host, netHostPayment, address(0));
            } else {
                accumulatedTreasuryTokens[session.paymentToken] += treasuryFee;
                // Transfer tokens to HostEarnings
                IERC20(session.paymentToken).safeTransfer(address(hostEarnings), netHostPayment);
                // Credit the host's earnings
                hostEarnings.creditEarnings(session.host, netHostPayment, session.paymentToken);
            }

            session.withdrawnByHost = netHostPayment;
        }

        if (userRefund > 0) {
            if (session.paymentToken == address(0)) {
                (bool sent,) = payable(session.depositor).call{value: userRefund}("");
                require(sent, "ETH refund failed");
            } else {
                IERC20(session.paymentToken).safeTransfer(session.depositor, userRefund);
            }
            session.refundedToUser = userRefund;
        }

        // Emit both events for backward compatibility
        emit SessionCompleted(jobId, session.tokensUsed, session.withdrawnByHost, userRefund);
        // Emit new event showing who completed it (Phase 3.1)
        emit SessionCompletedBy(jobId, completedBy, session.tokensUsed, hostPayment, userRefund);
    }

    /**
     * @notice Force timeout of a session that has exceeded its limits
     * @dev Can be called by anyone when either condition is met:
     *      1. Session exceeded maxDuration since startTime
     *      2. No proof submitted for 3x proofInterval (host abandoned)
     *
     *      Uses same settlement logic as completeSessionJob():
     *      - Host receives payment for proven work (tokensUsed)
     *      - User receives refund of unused deposit
     *      - If no proofs submitted, host gets $0
     *
     *      KEY DIFFERENCE from completeSessionJob():
     *      - completeSessionJob: Voluntary ending (Completed status)
     *      - triggerSessionTimeout: Forced ending (TimedOut status)
     *      Both settle payments identically based on proven work.
     *
     * @param jobId The session ID to timeout
     */
    function triggerSessionTimeout(uint256 jobId) external nonReentrant {
        SessionJob storage session = sessionJobs[jobId];
        require(session.status == SessionStatus.Active, "Session not active");

        bool hasTimedOut = (block.timestamp > session.startTime + session.maxDuration)
            || (block.timestamp > session.lastProofTime + session.proofInterval * 3);

        require(hasTimedOut, "Session not timed out");

        session.status = SessionStatus.TimedOut;
        _settleSessionPayments(jobId, msg.sender);

        emit SessionTimedOut(jobId, session.withdrawnByHost, session.refundedToUser);
    }

    // ============================================================
    // Treasury Functions
    // ============================================================

    function withdrawTreasuryNative() external {
        require(msg.sender == treasuryAddress, "Only treasury");
        uint256 amount = accumulatedTreasuryNative;
        require(amount > 0, "No native tokens to withdraw");

        accumulatedTreasuryNative = 0;
        (bool sent,) = payable(treasuryAddress).call{value: amount}("");
        require(sent, "Native token transfer failed");

        emit TreasuryWithdrawal(address(0), amount);
    }

    function withdrawTreasuryTokens(address token) external {
        require(msg.sender == treasuryAddress, "Only treasury");
        uint256 amount = accumulatedTreasuryTokens[token];
        require(amount > 0, "No tokens to withdraw");

        accumulatedTreasuryTokens[token] = 0;
        IERC20(token).safeTransfer(treasuryAddress, amount);

        emit TreasuryWithdrawal(token, amount);
    }

    function withdrawAllTreasuryFees(address[] calldata tokens) external {
        require(msg.sender == treasuryAddress, "Only treasury");

        if (accumulatedTreasuryNative > 0) {
            uint256 ethAmount = accumulatedTreasuryNative;
            accumulatedTreasuryNative = 0;
            (bool sent,) = payable(treasuryAddress).call{value: ethAmount}("");
            require(sent, "Native token transfer failed");
            emit TreasuryWithdrawal(address(0), ethAmount);
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amount = accumulatedTreasuryTokens[tokens[i]];
            if (amount > 0) {
                accumulatedTreasuryTokens[tokens[i]] = 0;
                IERC20(tokens[i]).safeTransfer(treasuryAddress, amount);
                emit TreasuryWithdrawal(tokens[i], amount);
            }
        }
    }

    /**
     * @notice Add a new accepted stablecoin token (treasury only)
     */
    function addAcceptedToken(address token, uint256 minDeposit) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Only treasury or owner");
        require(!acceptedTokens[token], "Token already accepted");
        require(minDeposit > 0, "Invalid minimum deposit");
        require(token != address(0), "Invalid token address");

        acceptedTokens[token] = true;
        tokenMinDeposits[token] = minDeposit;

        emit TokenAccepted(token, minDeposit);
    }

    /**
     * @notice Update minimum deposit for an accepted token (treasury or owner only)
     * @param token The token address to update
     * @param minDeposit The new minimum deposit amount
     */
    function updateTokenMinDeposit(address token, uint256 minDeposit) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Only treasury or owner");
        require(acceptedTokens[token], "Token not accepted");
        require(minDeposit > 0, "Invalid minimum deposit");

        uint256 oldMinDeposit = tokenMinDeposits[token];
        tokenMinDeposits[token] = minDeposit;

        emit TokenMinDepositUpdated(token, oldMinDeposit, minDeposit);
    }

    // ============================================================
    // Wallet-Agnostic Deposit Functions
    // ============================================================

    function depositNative() external payable whenNotPaused {
        require(msg.value > 0, "Zero deposit");
        userDepositsNative[msg.sender] += msg.value;
        emit DepositReceived(msg.sender, msg.value, address(0));
    }

    function depositToken(address token, uint256 amount) external whenNotPaused {
        require(amount > 0, "Zero deposit");
        require(token != address(0), "Invalid token");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        userDepositsToken[msg.sender][token] += amount;
        emit DepositReceived(msg.sender, amount, token);
    }

    // ============================================================
    // Wallet-Agnostic Withdrawal Functions
    // ============================================================

    function withdrawNative(uint256 amount) external nonReentrant {
        require(userDepositsNative[msg.sender] >= amount, "Insufficient balance");

        userDepositsNative[msg.sender] -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit WithdrawalProcessed(msg.sender, amount, address(0));
    }

    function withdrawToken(address token, uint256 amount) external nonReentrant {
        require(userDepositsToken[msg.sender][token] >= amount, "Insufficient balance");

        userDepositsToken[msg.sender][token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit WithdrawalProcessed(msg.sender, amount, token);
    }

    // ============================================================
    // Balance Query Functions
    // ============================================================

    function getDepositBalance(address account, address token) external view returns (uint256) {
        if (token == address(0)) {
            return userDepositsNative[account];
        }
        return userDepositsToken[account][token];
    }

    function getDepositBalances(address account, address[] calldata tokens) external view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = tokens[i] == address(0) ? userDepositsNative[account] : userDepositsToken[account][tokens[i]];
        }
        return balances;
    }

    /**
     * @notice Get total funds locked in active sessions for a user (native token)
     * @dev Iterates through user's sessions to sum remaining deposits in active sessions
     * @param account User address
     * @return locked Total ETH/BNB locked in active sessions (deposit - tokensUsed*price)
     */
    function getLockedBalanceNative(address account) external view returns (uint256 locked) {
        uint256[] memory sessions = userSessions[account];
        for (uint256 i = 0; i < sessions.length; i++) {
            SessionJob storage session = sessionJobs[sessions[i]];
            if (session.status == SessionStatus.Active && session.paymentToken == address(0)) {
                // Calculate remaining deposit after proofs
                uint256 used = (session.tokensUsed * session.pricePerToken) / PRICE_PRECISION;
                if (session.deposit > used) {
                    locked += session.deposit - used;
                }
            }
        }
        return locked;
    }

    /**
     * @notice Get total funds locked in active sessions for a user (ERC20 token)
     * @dev Iterates through user's sessions to sum remaining deposits in active sessions
     * @param account User address
     * @param token ERC20 token address
     * @return locked Total tokens locked in active sessions
     */
    function getLockedBalanceToken(address account, address token) external view returns (uint256 locked) {
        uint256[] memory sessions = userSessions[account];
        for (uint256 i = 0; i < sessions.length; i++) {
            SessionJob storage session = sessionJobs[sessions[i]];
            if (session.status == SessionStatus.Active && session.paymentToken == token) {
                // Calculate remaining deposit after proofs
                uint256 used = (session.tokensUsed * session.pricePerToken) / PRICE_PRECISION;
                if (session.deposit > used) {
                    locked += session.deposit - used;
                }
            }
        }
        return locked;
    }

    /**
     * @notice Get total balance (withdrawable + locked) for a user (native token)
     * @param account User address
     * @return Total ETH/BNB balance (pre-deposit + locked in sessions)
     */
    function getTotalBalanceNative(address account) external view returns (uint256) {
        uint256 withdrawable = userDepositsNative[account];
        uint256 locked = this.getLockedBalanceNative(account);
        return withdrawable + locked;
    }

    /**
     * @notice Get total balance (withdrawable + locked) for a user (ERC20 token)
     * @param account User address
     * @param token ERC20 token address
     * @return Total token balance (pre-deposit + locked in sessions)
     */
    function getTotalBalanceToken(address account, address token) external view returns (uint256) {
        uint256 withdrawable = userDepositsToken[account][token];
        uint256 locked = this.getLockedBalanceToken(account, token);
        return withdrawable + locked;
    }

    /**
     * @notice Get a specific proof submission for a session
     * @param sessionId The session ID
     * @param proofIndex The index of the proof in the session's proofs array
     * @return proofHash The hash of the proof
     * @return tokensClaimed Number of tokens claimed in this proof
     * @return timestamp When the proof was submitted
     * @return verified Whether the proof was cryptographically verified
     */
    function getProofSubmission(uint256 sessionId, uint256 proofIndex)
        external
        view
        returns (bytes32 proofHash, uint256 tokensClaimed, uint256 timestamp, bool verified)
    {
        SessionJob storage session = sessionJobs[sessionId];
        require(proofIndex < session.proofs.length, "Proof index out of bounds");
        ProofSubmission storage proof = session.proofs[proofIndex];
        return (proof.proofHash, proof.tokensClaimed, proof.timestamp, proof.verified);
    }

    // ============================================================
    // Create Session From Deposit
    // ============================================================

    function createSessionFromDeposit(
        address host,
        address paymentToken,
        uint256 deposit,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval
    ) external nonReentrant whenNotPaused returns (uint256 sessionId) {
        require(pricePerToken > 0, "Invalid price");
        require(maxDuration > 0 && maxDuration <= 365 days, "Invalid duration");
        require(proofInterval > 0, "Invalid proof interval");
        require(host != address(0), "Invalid host");
        require(deposit > 0, "Zero deposit");
        require(deposit <= 1000 ether, "Deposit too large");

        _validateHostRegistration(host);
        _validateProofRequirements(proofInterval, deposit, pricePerToken);

        // Validate price meets host's minimum for the specified payment token
        uint256 hostMinPrice = nodeRegistry.getNodePricing(host, paymentToken);
        require(pricePerToken >= hostMinPrice, "Price below host minimum");

        // Verify user has sufficient pre-deposited balance
        if (paymentToken == address(0)) {
            require(deposit >= MIN_DEPOSIT, "Insufficient deposit");
            require(userDepositsNative[msg.sender] >= deposit, "Insufficient native balance");
            userDepositsNative[msg.sender] -= deposit;
        } else {
            require(acceptedTokens[paymentToken], "Token not accepted");
            uint256 minRequired = tokenMinDeposits[paymentToken];
            require(minRequired > 0, "Token not configured");
            require(deposit >= minRequired, "Insufficient deposit");
            require(userDepositsToken[msg.sender][paymentToken] >= deposit, "Insufficient token balance");
            userDepositsToken[msg.sender][paymentToken] -= deposit;
        }

        sessionId = nextJobId++;

        SessionJob storage session = sessionJobs[sessionId];
        session.id = sessionId;
        session.depositor = msg.sender;
        session.host = host;
        session.paymentToken = paymentToken;
        session.deposit = deposit;
        session.pricePerToken = pricePerToken;
        session.maxDuration = maxDuration;
        session.startTime = block.timestamp;
        session.lastProofTime = block.timestamp;
        session.proofInterval = proofInterval;
        session.status = SessionStatus.Active;

        userSessions[msg.sender].push(sessionId);
        hostSessions[host].push(sessionId);

        emit SessionJobCreated(sessionId, msg.sender, host, deposit);
        emit SessionCreatedByDepositor(sessionId, msg.sender, host, deposit);

        return sessionId;
    }
}
