// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "./NodeRegistryWithModelsUpgradeable.sol";
import "./interfaces/IJobMarketplace.sol";
import "./HostEarningsUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Proof system interface
interface IProofSystemUpgradeable {
    function markProofUsed(bytes32 proofHash, address prover, uint256 claimedTokens, bytes32 modelId)
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
    ReentrancyGuardTransient,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // Session status enum (Active, Completed, TimedOut)
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
        bool verified;  /// @dev DEPRECATED: Always true. Retained for storage layout.
        string deltaCID;  // Delta CID for incremental proof storage
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
        uint256 proofTimeoutWindow; // F202614911: Time in seconds before timeout (separate from token count)
        SessionStatus status;
        ProofSubmission[] proofs;
        uint256 withdrawnByHost;
        uint256 refundedToUser;
        string conversationCID;
        bytes32 lastProofHash; // S5: Hash of most recent proof (32 bytes)
        string lastProofCID; // S5: CID of most recent proof in S5 storage
    }

    // Chain configuration structure
    struct ChainConfig {
        address nativeWrapper; // WETH on Base, WBNB on opBNB
        address stablecoin; // USDC address per chain
        uint256 minDeposit; // Chain-specific minimum
        string nativeTokenSymbol; // "ETH" or "BNB"
    }

    // F202615255+F202615256: Configurable delegate authorization
    struct DelegateConfig {
        uint128 maxPerSession;   // 0 = unlimited
        uint128 totalCap;        // 0 = unlimited
        uint128 spent;           // Cumulative spent
        uint64 validUntil;       // 0 = no expiry
        bool active;
        address allowedHost;     // address(0) = any
        bytes32 allowedModel;    // bytes32(0) = any
    }

    // Session creation parameters
    struct SessionParams {
        address host;
        address paymentToken;
        uint256 deposit;
        uint256 pricePerToken;
        uint256 maxDuration;
        uint256 proofInterval;
        uint256 proofTimeoutWindow; // F202614911: Time in seconds before timeout
        bytes32 modelId;  // bytes32(0) if no model
    }

    // Constants (non-upgradeable)
    uint256 public constant MIN_DEPOSIT = 0.0001 ether; // ~$0.50 @ $5000/ETH
    uint256 public constant MIN_PROVEN_TOKENS = 100;

    // F202614911: Proof timeout constants (in seconds)
    uint256 public constant DEFAULT_PROOF_TIMEOUT = 300;  // 5 minutes default
    uint256 public constant MIN_PROOF_TIMEOUT = 60;       // 1 minute minimum
    uint256 public constant MAX_PROOF_TIMEOUT = 3600;     // 1 hour maximum
    uint256 public constant MAX_MIN_TOKENS_FEE = 10000;   // F202615258: cap for minTokensFee

    /// @notice Time window before non-depositor can complete session (default 30s)
    uint256 public disputeWindow;

    /// @notice Treasury fee in basis points (1000 = 10%)
    uint256 public feeBasisPoints;

    // State variables
    mapping(uint256 => SessionJob) public sessionJobs;
    mapping(address => uint256[]) public userSessions;
    mapping(address => uint256[]) public hostSessions;

    // Session model tracking (sessionId => modelId)
    mapping(uint256 => bytes32) public sessionModel;

    uint256 public nextJobId;
    address public treasuryAddress;
    address public usdcAddress;

    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    IProofSystemUpgradeable public proofSystem;
    HostEarningsUpgradeable public hostEarnings;

    // USDC-specific configuration
    uint256 public constant USDC_MIN_DEPOSIT = 500000; // 0.50 USDC
    uint256 public constant USDC_MAX_DEPOSIT = 1_000_000 * 10**6; // 1M USDC cap

    // Price precision: prices are stored with 1000x precision for sub-cent granularity
    // Payment calculation: (tokensUsed * pricePerToken) / PRICE_PRECISION
    uint256 public constant PRICE_PRECISION = 1000;

    mapping(address => bool) public acceptedTokens;
    mapping(address => uint256) public tokenMinDeposits;
    mapping(address => uint256) public tokenMaxDeposits;

    // Treasury accumulation mappings
    uint256 public accumulatedTreasuryNative;
    mapping(address => uint256) public accumulatedTreasuryTokens;

    // Wallet-agnostic deposit tracking
    mapping(address => uint256) public userDepositsNative;
    mapping(address => mapping(address => uint256)) public userDepositsToken;

    // Chain configuration storage
    ChainConfig public chainConfig;

    /// @notice Min tokens charged on early cancel (before first proof)
    uint256 public minTokensFee;

    /// @dev DEPRECATED: Replaced by delegateConfigs. Retained for storage layout.
    mapping(address => mapping(address => bool)) public _isAuthorizedDelegate;

    // F202615255+F202615256: Configurable delegate authorization
    mapping(address => mapping(address => DelegateConfig)) public delegateConfigs;

    // Storage gap for future upgrades (reduced by 3: minTokensFee + _isAuthorizedDelegate + delegateConfigs)
    uint256[32] private __gap;

    // Events
    event SessionJobCreated(uint256 indexed jobId, address indexed depositor, address indexed host, uint256 deposit);
    event ProofSubmitted(
        uint256 indexed jobId, address indexed host, uint256 tokensClaimed, bytes32 proofHash, string proofCID, string deltaCID
    );
    event SessionCompleted(uint256 indexed jobId, uint256 totalTokensUsed, uint256 hostEarnings, uint256 userRefund);
    // Event that tracks who completed the session (anyone-can-complete pattern)
    event SessionCompletedBy(
        uint256 indexed jobId,
        address indexed completedBy,
        uint256 tokensUsed,
        uint256 paymentAmount,
        uint256 refundAmount
    );
    event SessionTimedOut(uint256 indexed jobId, uint256 hostEarnings, uint256 userRefund);
    event PaymentSent(address indexed recipient, uint256 amount);
    event TreasuryWithdrawal(address indexed token, uint256 amount);

    // Wallet-agnostic deposit events
    event DepositReceived( // address(0) for native
    address indexed depositor, uint256 amount, address indexed token);

    event WithdrawalProcessed( // address(0) for native
    address indexed depositor, uint256 amount, address indexed token);

    // Session events using depositor terminology
    event SessionCreatedByDepositor(
        uint256 indexed sessionId, address indexed depositor, address indexed host, uint256 deposit
    );

    // Token acceptance event
    event TokenAccepted(address indexed token, uint256 minDeposit, uint256 maxDeposit);
    event TokenMinDepositUpdated(address indexed token, uint256 oldMinDeposit, uint256 newMinDeposit);
    event TokenMaxDepositUpdated(address indexed token, uint256 oldMaxDeposit, uint256 newMaxDeposit);

    // Model-aware session event
    event SessionJobCreatedForModel(
        uint256 indexed jobId, address indexed depositor, address indexed host, bytes32 modelId, uint256 deposit
    );

    // Settlement pull pattern event (F202614898)
    event RefundCreditedToDeposit(
        uint256 indexed jobId, address indexed depositor, uint256 amount, address indexed token
    );

    // Fee events
    event MinTokensFeeUpdated(uint256 oldFee, uint256 newFee);

    // Pause events
    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);

    // V2 Delegation events (Coinbase Smart Wallet sub-account support)
    event DelegateAuthorized(address indexed depositor, address indexed delegate, bool authorized);
    event DelegateConfigured(address indexed depositor, address indexed delegate, uint128 maxPerSession, uint128 totalCap, uint64 validUntil, address allowedHost, bytes32 allowedModel);
    event SessionCreatedByDelegate(
        uint256 indexed sessionId,
        address indexed payer,
        address indexed delegate,
        address host,
        bytes32 modelId,
        uint256 amount
    );

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
        __Pausable_init();
        // Note: ReentrancyGuardTransient uses transient storage, no init needed
        // Note: OZ 5.x UUPSUpgradeable doesn't require __UUPSUpgradeable_init()

        require(_nodeRegistry != address(0), "Zero addr");
        require(_hostEarnings != address(0), "Zero addr");
        require(_feeBasisPoints <= 10000, "Bad fee");
        require(_disputeWindow > 0 && _disputeWindow <= 7 days, "Bad window");

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
        tokenMaxDeposits[usdcAddress] = USDC_MAX_DEPOSIT;
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
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Not admin");
        _pause();
        emit ContractPaused(msg.sender);
    }

    /**
     * @notice Unpause the contract (treasury or owner only)
     */
    function unpause() external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Not admin");
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    // ============================================================
    // Admin Functions
    // ============================================================

    function setProofSystem(address _proofSystem) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Not admin");
        require(_proofSystem != address(0), "Zero addr");
        proofSystem = IProofSystemUpgradeable(_proofSystem);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Zero addr");
        treasuryAddress = _treasury;
    }

    function setUsdcAddress(address _usdc) external onlyOwner {
        require(_usdc != address(0), "Zero addr");

        // Remove old USDC from accepted tokens if it exists
        if (usdcAddress != address(0) && acceptedTokens[usdcAddress]) {
            acceptedTokens[usdcAddress] = false;
        }

        // Set new USDC address and add to accepted tokens
        usdcAddress = _usdc;
        acceptedTokens[_usdc] = true;
        tokenMinDeposits[_usdc] = USDC_MIN_DEPOSIT;
        tokenMaxDeposits[_usdc] = USDC_MAX_DEPOSIT;
    }

    /// @notice Set min token fee for early cancellation
    function setMinTokensFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_MIN_TOKENS_FEE, "Fee too high");
        uint256 oldFee = minTokensFee;
        minTokensFee = _fee;
        emit MinTokensFeeUpdated(oldFee, _fee);
    }

    // Initialize chain configuration
    function initializeChainConfig(ChainConfig memory _config) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Not admin");
        require(chainConfig.nativeWrapper == address(0), "Already init");
        chainConfig = _config;
    }

    // ============================================================
    // Session Creation Functions
    // ============================================================

    /// @notice Create a session job for a specific model with native token payment
    function createSessionJobForModel(
        address host,
        bytes32 modelId,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval,
        uint256 proofTimeoutWindow
    ) external payable nonReentrant whenNotPaused returns (uint256 jobId) {
        require(msg.value >= MIN_DEPOSIT, "Low deposit");

        SessionParams memory params = SessionParams({
            host: host,
            paymentToken: address(0),
            deposit: msg.value,
            pricePerToken: pricePerToken,
            maxDuration: maxDuration,
            proofInterval: proofInterval,
            proofTimeoutWindow: proofTimeoutWindow,
            modelId: modelId
        });

        // Validates host registration before model check (security requirement)
        _validateSessionParams(params);

        // Model-specific validations
        require(nodeRegistry.modelRegistry().isModelApproved(modelId), "Bad model");
        require(nodeRegistry.nodeSupportsModel(host, modelId), "No model");

        // Get model-specific pricing (falls back to default if not set)
        uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, address(0));
        require(pricePerToken >= hostMinPrice, "Low price");

        jobId = nextJobId++;
        sessionModel[jobId] = modelId;
        _initializeSession(jobId, params, msg.sender);

        emit SessionJobCreated(jobId, msg.sender, host, msg.value);
        emit SessionJobCreatedForModel(jobId, msg.sender, host, modelId, msg.value);

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
        uint256 proofInterval,
        uint256 proofTimeoutWindow
    ) external nonReentrant whenNotPaused returns (uint256 jobId) {
        // Token-specific validations
        require(acceptedTokens[token], "Bad token");
        uint256 minRequired = tokenMinDeposits[token];
        require(minRequired > 0, "Token not set");
        require(deposit >= minRequired, "Low deposit");
        require(deposit > 0, "Zero deposit");

        SessionParams memory params = SessionParams({
            host: host,
            paymentToken: token,
            deposit: deposit,
            pricePerToken: pricePerToken,
            maxDuration: maxDuration,
            proofInterval: proofInterval,
            proofTimeoutWindow: proofTimeoutWindow,
            modelId: modelId
        });

        // Validates host registration before model check (security requirement)
        _validateSessionParams(params);

        // Model-specific validations
        require(nodeRegistry.modelRegistry().isModelApproved(modelId), "Bad model");
        require(nodeRegistry.nodeSupportsModel(host, modelId), "No model");

        // Get model-specific pricing for this token (falls back to default stable if not set)
        uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, token);
        require(pricePerToken >= hostMinPrice, "Low price");

        // Transfer tokens after all validations pass
        IERC20(token).safeTransferFrom(msg.sender, address(this), deposit);

        jobId = nextJobId++;
        sessionModel[jobId] = modelId;
        _initializeSession(jobId, params, msg.sender);

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
        require(host != address(0), "No host");

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

        require(operator != address(0), "No host reg");
        require(active, "Host not active");
    }

    function _validateProofRequirements(uint256 proofInterval, uint256 deposit, uint256 pricePerToken) internal pure {
        // With PRICE_PRECISION: maxTokens = deposit * PRICE_PRECISION / pricePerToken
        uint256 maxTokens = (deposit * PRICE_PRECISION) / pricePerToken;
        uint256 tokensPerProof = proofInterval;
        require(tokensPerProof >= MIN_PROVEN_TOKENS, "Low interval");
        require(maxTokens >= tokensPerProof, "Low deposit");
    }

    // ============================================================
    // Session Creation Helpers
    // ============================================================

    /**
     * @notice Validate common session parameters
     * @dev Checks price, duration, proof interval, and host address
     * @param params Session parameters to validate
     */
    function _validateSessionParams(SessionParams memory params) internal view {
        require(params.pricePerToken > 0, "Bad price");
        require(params.maxDuration > 0 && params.maxDuration <= 365 days, "Bad dur");
        require(params.proofInterval > 0, "Bad interval");
        require(
            params.proofTimeoutWindow >= MIN_PROOF_TIMEOUT && params.proofTimeoutWindow <= MAX_PROOF_TIMEOUT,
            "Bad timeout"
        );
        require(params.host != address(0), "No host");

        // Token-specific max deposit validation
        if (params.paymentToken == address(0)) {
            require(params.deposit <= 1000 ether, "Over max");
        } else {
            uint256 maxAllowed = tokenMaxDeposits[params.paymentToken];
            require(maxAllowed > 0, "No max set");
            require(params.deposit <= maxAllowed, "Over max");
        }

        _validateHostRegistration(params.host);
        _validateProofRequirements(params.proofInterval, params.deposit, params.pricePerToken);
    }

    /**
     * @notice Initialize session storage with common fields
     * @dev Sets all session fields and updates tracking mappings
     * @param jobId The job ID for the session
     * @param params Session parameters
     * @param depositor Address of the depositor (msg.sender for direct, payer for delegate)
     * @return session Storage pointer to the initialized session
     */
    function _initializeSession(
        uint256 jobId,
        SessionParams memory params,
        address depositor
    ) internal returns (SessionJob storage session) {
        session = sessionJobs[jobId];
        session.id = jobId;
        session.depositor = depositor;
        session.host = params.host;
        session.paymentToken = params.paymentToken;
        session.deposit = params.deposit;
        session.pricePerToken = params.pricePerToken;
        session.maxDuration = params.maxDuration;
        session.startTime = block.timestamp;
        session.lastProofTime = block.timestamp;
        session.proofInterval = params.proofInterval;
        session.proofTimeoutWindow = params.proofTimeoutWindow;
        session.status = SessionStatus.Active;

        // Track session for user and host
        userSessions[depositor].push(jobId);
        hostSessions[params.host].push(jobId);

        return session;
    }

    /**
     * @notice Deduct deposit from user's pre-deposited balance with validation
     * @dev AUDIT-F18: Shared helper for createSessionFromDepositForModel functions
     * @param depositor Address of the depositor
     * @param paymentToken address(0) for ETH, token address for ERC20
     * @param deposit Amount to deduct
     */
    function _deductFromDeposit(address depositor, address paymentToken, uint256 deposit) internal {
        require(deposit > 0, "Zero deposit");
        if (paymentToken == address(0)) {
            require(deposit >= MIN_DEPOSIT, "Low deposit");
            require(userDepositsNative[depositor] >= deposit, "Low balance");
            userDepositsNative[depositor] -= deposit;
        } else {
            require(acceptedTokens[paymentToken], "Bad token");
            uint256 minRequired = tokenMinDeposits[paymentToken];
            require(minRequired > 0, "Token not set");
            require(deposit >= minRequired, "Low deposit");
            require(userDepositsToken[depositor][paymentToken] >= deposit, "Low balance");
            userDepositsToken[depositor][paymentToken] -= deposit;
        }
    }

    // ============================================================
    // Proof Submission
    // ============================================================

    function submitProofOfWork(
        uint256 jobId,
        uint256 tokensClaimed,
        bytes32 proofHash,
        string calldata proofCID,
        string calldata deltaCID
    ) external nonReentrant whenNotPaused {
        require(address(proofSystem) != address(0), "No proof sys");
        SessionJob storage session = sessionJobs[jobId];
        require(session.status == SessionStatus.Active, "Not active");
        require(msg.sender == session.host, "Not host");
        require(nodeRegistry.isActiveNode(session.host), "Host not active");
        require(tokensClaimed >= MIN_PROVEN_TOKENS, "Min tokens");

        // First proof must meet proofInterval for minimum billing
        if (session.tokensUsed == 0) {
            require(tokensClaimed >= session.proofInterval, "Low first");
        }

        uint256 timeSinceLastProof = block.timestamp - session.lastProofTime;
        // Per-model rate limit (default 2000 tokens/sec for non-model sessions)
        bytes32 modelId = sessionModel[jobId];
        uint256 maxRate = nodeRegistry.modelRegistry().getModelRateLimit(modelId);
        uint256 expectedTokens = timeSinceLastProof * maxRate;
        require(tokensClaimed <= expectedTokens, "Too many");

        uint256 newTotal = session.tokensUsed + tokensClaimed;
        // With PRICE_PRECISION: maxTokens = deposit * PRICE_PRECISION / pricePerToken
        uint256 maxTokens = (session.deposit * PRICE_PRECISION) / session.pricePerToken;
        require(newTotal <= maxTokens, "Over dep");

        // Mark proof as used via ProofSystem (replay protection)
        require(
            proofSystem.markProofUsed(proofHash, msg.sender, tokensClaimed, modelId),
            "Proof already used"
        );
        // S5: Store proof hash and CID instead of full proof
        session.lastProofHash = proofHash;
        session.lastProofCID = proofCID;

        // Store proof submission with verification status
        session.proofs.push(
            ProofSubmission({
                proofHash: proofHash,
                tokensClaimed: tokensClaimed,
                timestamp: block.timestamp,
                verified: true,  // DEPRECATED: always true
                deltaCID: deltaCID
            })
        );

        session.tokensUsed = newTotal;
        session.lastProofTime = block.timestamp;

        emit ProofSubmitted(jobId, msg.sender, tokensClaimed, proofHash, proofCID, deltaCID);
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
     *      conversationCID (S5 reference to conversation record).
     *
     *      PROOF-THEN-SETTLE ARCHITECTURE:
     *      - Proof of work happens in submitProofOfWork() which requires msg.sender == host
     *      - This function ONLY settles based on already-proven work (tokensUsed)
     *      - If no proofs were submitted, tokensUsed=0 and host receives $0
     *      - User receives refund of (deposit - payment to host)
     *
     *      Compare with triggerSessionTimeout() which handles forced endings
     *      and can be called by anyone when timeout conditions are met.
     *
     * @param jobId The session ID to complete
     * @param conversationCID S5 CID of the conversation record (for audit trail)
     */
    function completeSessionJob(uint256 jobId, string calldata conversationCID) external nonReentrant {
        SessionJob storage session = sessionJobs[jobId];
        require(session.status == SessionStatus.Active, "Not active");

        // Only depositor or host can complete and set conversationCID
        require(
            msg.sender == session.depositor || msg.sender == session.host,
            "Not depositor or host"
        );

        // Dispute window only waived for the original depositor
        if (msg.sender != session.depositor) {
            require(block.timestamp >= session.lastProofTime + disputeWindow, "Dispute wait");
        }

        session.status = SessionStatus.Completed;
        session.conversationCID = conversationCID;

        _settleSessionPayments(jobId, msg.sender);
    }

    function _settleSessionPayments(uint256 jobId, address completedBy) internal {
        SessionJob storage session = sessionJobs[jobId];

        // Enforce minimum billing at completion (fallback for edge cases)
        uint256 billableTokens = session.tokensUsed;
        if (billableTokens < session.proofInterval && session.proofs.length > 0) {
            billableTokens = session.proofInterval;
        }

        uint256 hostPayment = (billableTokens * session.pricePerToken) / PRICE_PRECISION;
        uint256 earlyFee;
        // Early cancel fee: depositor cancels before any proofs (F202615257: not on timeout)
        if (completedBy == session.depositor && session.status == SessionStatus.Completed && session.proofs.length == 0 && minTokensFee > 0) {
            earlyFee = (minTokensFee * session.pricePerToken) / PRICE_PRECISION;
            if (hostPayment >= session.deposit) {
                earlyFee = 0;
            } else if (earlyFee > session.deposit - hostPayment) {
                earlyFee = session.deposit - hostPayment;
            }
        }
        uint256 totalHostAmount = hostPayment + earlyFee;
        uint256 userRefund = session.deposit > totalHostAmount ? session.deposit - totalHostAmount : 0;

        if (totalHostAmount > 0) {
            // Treasury fee only on proven work, not on early cancel fee
            uint256 treasuryFee = (hostPayment * feeBasisPoints) / 10000;
            uint256 netToHost = totalHostAmount - treasuryFee;

            if (session.paymentToken == address(0)) {
                accumulatedTreasuryNative += treasuryFee;
                (bool sent,) = payable(address(hostEarnings)).call{value: netToHost}("");
                require(sent, "Tx fail");
                hostEarnings.creditEarnings(session.host, netToHost, address(0));
            } else {
                accumulatedTreasuryTokens[session.paymentToken] += treasuryFee;
                IERC20(session.paymentToken).safeTransfer(address(hostEarnings), netToHost);
                hostEarnings.creditEarnings(session.host, netToHost, session.paymentToken);
            }

            session.withdrawnByHost = netToHost;
        }

        if (userRefund > 0) {
            session.refundedToUser = userRefund;
            if (session.paymentToken == address(0)) {
                (bool sent,) = payable(session.depositor).call{value: userRefund}("");
                if (!sent) {
                    // F202614898: Credit to deposit balance on ETH refund failure
                    userDepositsNative[session.depositor] += userRefund;
                    emit RefundCreditedToDeposit(jobId, session.depositor, userRefund, address(0));
                }
            } else {
                // F202615254: Low-level call handles non-returning tokens (USDT)
                (bool callOk, bytes memory ret) = session.paymentToken.call(
                    abi.encodeCall(IERC20.transfer, (session.depositor, userRefund))
                );
                if (!(callOk && (ret.length == 0 || abi.decode(ret, (bool))))) {
                    userDepositsToken[session.depositor][session.paymentToken] += userRefund;
                    emit RefundCreditedToDeposit(jobId, session.depositor, userRefund, session.paymentToken);
                }
            }
        }

        // Emit both events for backward compatibility
        emit SessionCompleted(jobId, session.tokensUsed, session.withdrawnByHost, userRefund);
        // Emit event showing who completed the session
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
        require(session.status == SessionStatus.Active, "Not active");

        // Use proofTimeoutWindow for time-based timeout (F202614911 fix)
        // Fallback to DEFAULT_PROOF_TIMEOUT for legacy sessions where proofTimeoutWindow is 0
        uint256 timeoutWindow = session.proofTimeoutWindow > 0
            ? session.proofTimeoutWindow
            : DEFAULT_PROOF_TIMEOUT;

        bool hasTimedOut = (block.timestamp > session.startTime + session.maxDuration)
            || (block.timestamp > session.lastProofTime + timeoutWindow);

        require(hasTimedOut, "Not timeout");

        session.status = SessionStatus.TimedOut;
        _settleSessionPayments(jobId, msg.sender);

        emit SessionTimedOut(jobId, session.withdrawnByHost, session.refundedToUser);
    }

    // ============================================================
    // Treasury Functions
    // ============================================================

    function withdrawTreasuryNative() external nonReentrant {
        require(msg.sender == treasuryAddress, "Only treasury");
        uint256 amount = accumulatedTreasuryNative;
        require(amount > 0, "No balance");

        accumulatedTreasuryNative = 0;
        (bool sent,) = payable(treasuryAddress).call{value: amount}("");
        require(sent, "Tx fail");

        emit TreasuryWithdrawal(address(0), amount);
    }

    function withdrawTreasuryTokens(address token) external nonReentrant {
        require(msg.sender == treasuryAddress, "Only treasury");
        uint256 amount = accumulatedTreasuryTokens[token];
        require(amount > 0, "No tokens");

        accumulatedTreasuryTokens[token] = 0;
        IERC20(token).safeTransfer(treasuryAddress, amount);

        emit TreasuryWithdrawal(token, amount);
    }

    function withdrawAllTreasuryFees(address[] calldata tokens) external nonReentrant {
        require(msg.sender == treasuryAddress, "Only treasury");

        if (accumulatedTreasuryNative > 0) {
            uint256 ethAmount = accumulatedTreasuryNative;
            accumulatedTreasuryNative = 0;
            (bool sent,) = payable(treasuryAddress).call{value: ethAmount}("");
            require(sent, "Tx fail");
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
     * @param token The token address to accept
     * @param minDeposit Minimum deposit amount required
     * @param maxDeposit Maximum deposit amount allowed
     */
    function addAcceptedToken(address token, uint256 minDeposit, uint256 maxDeposit) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Not admin");
        require(!acceptedTokens[token], "Already set");
        require(minDeposit > 0, "Bad min");
        require(maxDeposit > minDeposit, "Max < min");
        require(token != address(0), "Zero addr");

        acceptedTokens[token] = true;
        tokenMinDeposits[token] = minDeposit;
        tokenMaxDeposits[token] = maxDeposit;

        emit TokenAccepted(token, minDeposit, maxDeposit);
    }

    /**
     * @notice Update minimum deposit for an accepted token (treasury or owner only)
     * @param token The token address to update
     * @param minDeposit The new minimum deposit amount
     */
    function updateTokenMinDeposit(address token, uint256 minDeposit) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Not admin");
        require(acceptedTokens[token], "Bad token");
        require(minDeposit > 0, "Bad min");

        uint256 oldMinDeposit = tokenMinDeposits[token];
        tokenMinDeposits[token] = minDeposit;

        emit TokenMinDepositUpdated(token, oldMinDeposit, minDeposit);
    }

    /**
     * @notice Update maximum deposit for an accepted token (treasury or owner only)
     * @param token The token address to update
     * @param maxDeposit The new maximum deposit amount
     */
    function updateTokenMaxDeposit(address token, uint256 maxDeposit) external {
        require(msg.sender == treasuryAddress || msg.sender == owner(), "Not admin");
        require(acceptedTokens[token], "Bad token");
        require(maxDeposit > tokenMinDeposits[token], "Max < min");

        uint256 oldMaxDeposit = tokenMaxDeposits[token];
        tokenMaxDeposits[token] = maxDeposit;

        emit TokenMaxDepositUpdated(token, oldMaxDeposit, maxDeposit);
    }

    // ============================================================
    // Wallet-Agnostic Deposit Functions
    // ============================================================

    function depositNative() external payable whenNotPaused {
        require(msg.value > 0, "Zero deposit");
        userDepositsNative[msg.sender] += msg.value;
        emit DepositReceived(msg.sender, msg.value, address(0));
    }

    function depositToken(address token, uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Zero deposit");
        require(token != address(0), "Bad token");
        require(acceptedTokens[token], "Bad token");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        userDepositsToken[msg.sender][token] += amount;
        emit DepositReceived(msg.sender, amount, token);
    }

    // ============================================================
    // Wallet-Agnostic Withdrawal Functions
    // ============================================================

    function withdrawNative(uint256 amount) external nonReentrant {
        require(userDepositsNative[msg.sender] >= amount, "Low balance");

        userDepositsNative[msg.sender] -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH failed");

        emit WithdrawalProcessed(msg.sender, amount, address(0));
    }

    function withdrawToken(address token, uint256 amount) external nonReentrant {
        require(userDepositsToken[msg.sender][token] >= amount, "Low balance");

        userDepositsToken[msg.sender][token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit WithdrawalProcessed(msg.sender, amount, token);
    }

    // ============================================================
    // V2 Delegation: Coinbase Smart Wallet Sub-Account Support
    // ============================================================

    /**
     * @notice Authorize or revoke a delegate to create sessions on behalf of caller.
     * When re-authorizing (authorized=true), clears any existing expiry (validUntil=0)
     * to prevent stale expiry from blocking re-activated delegates.
     * To preserve expiry, use configureDelegate() instead.
     * @param delegate Address to authorize (e.g., Smart Wallet sub-account)
     * @param authorized True to authorize, false to revoke
     */
    function authorizeDelegate(address delegate, bool authorized) external {
        require(delegate != address(0), "Zero addr");
        require(delegate != msg.sender, "Self deleg");

        delegateConfigs[msg.sender][delegate].active = authorized;
        if (authorized) delegateConfigs[msg.sender][delegate].validUntil = 0;
        emit DelegateAuthorized(msg.sender, delegate, authorized);
    }

    /**
     * @notice Configure a delegate with spending limits and scope restrictions
     * @dev Resets spent counter to 0. The depositor controls their own spending limits
     * and can reset at any time by reconfiguring. Call authorizeDelegate to toggle
     * active without resetting spent or other config fields.
     * @param delegate Address to authorize
     * @param maxPerSession Maximum amount per session (0 = unlimited)
     * @param totalCap Cumulative spending cap (0 = unlimited)
     * @param validUntil Expiration timestamp (0 = no expiry)
     * @param allowedHost Restrict to specific host (address(0) = any)
     * @param allowedModel Restrict to specific model (bytes32(0) = any)
     */
    function configureDelegate(
        address delegate,
        uint128 maxPerSession,
        uint128 totalCap,
        uint64 validUntil,
        address allowedHost,
        bytes32 allowedModel
    ) external {
        require(delegate != address(0), "Zero addr");
        require(delegate != msg.sender, "Self deleg");
        delegateConfigs[msg.sender][delegate] = DelegateConfig({
            maxPerSession: maxPerSession,
            totalCap: totalCap,
            spent: 0,
            validUntil: validUntil,
            active: true,
            allowedHost: allowedHost,
            allowedModel: allowedModel
        });
        emit DelegateAuthorized(msg.sender, delegate, true);
        emit DelegateConfigured(msg.sender, delegate, maxPerSession, totalCap, validUntil, allowedHost, allowedModel);
    }

    /**
     * @notice Check if a delegate is authorized for a depositor
     * @param depositor The depositor address (primary account)
     * @param delegate The delegate address (sub-account)
     * @return True if delegate is authorized
     */
    function isDelegateAuthorized(address depositor, address delegate) external view returns (bool) {
        return delegateConfigs[depositor][delegate].active;
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
     * @return verified DEPRECATED: Always true. Retained for ABI compatibility.
     * @return deltaCID The delta CID for incremental proof storage
     */
    function getProofSubmission(uint256 sessionId, uint256 proofIndex)
        external
        view
        returns (bytes32 proofHash, uint256 tokensClaimed, uint256 timestamp, bool verified, string memory deltaCID)
    {
        SessionJob storage session = sessionJobs[sessionId];
        require(proofIndex < session.proofs.length, "Bad index");
        ProofSubmission storage proof = session.proofs[proofIndex];
        return (proof.proofHash, proof.tokensClaimed, proof.timestamp, proof.verified, proof.deltaCID);
    }

    // ============================================================
    // Create Session From Deposit
    // ============================================================

    // ============================================================
    // Create Session From Deposit For Model (F202614916)
    // ============================================================

    /**
     * @notice Create a model-specific session from pre-deposited funds
     * @param modelId The approved model ID (must not be bytes32(0))
     * @param host The host to create the session with
     * @param paymentToken address(0) for ETH, token address for ERC20
     * @param deposit Amount to use from pre-deposited balance
     * @param pricePerToken Price per inference token
     * @param maxDuration Maximum session duration in seconds
     * @param proofInterval Minimum tokens per proof submission
     * @param proofTimeoutWindow Time in seconds before timeout
     * @return sessionId The created session ID
     */
    function createSessionFromDepositForModel(
        bytes32 modelId,
        address host,
        address paymentToken,
        uint256 deposit,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval,
        uint256 proofTimeoutWindow
    ) external nonReentrant whenNotPaused returns (uint256 sessionId) {
        require(modelId != bytes32(0), "Bad modelId");

        // Deposit-specific early checks (before _validateSessionParams)
        require(deposit > 0, "Zero deposit");
        if (paymentToken != address(0)) {
            require(acceptedTokens[paymentToken], "Bad token");
        }

        SessionParams memory params = SessionParams({
            host: host,
            paymentToken: paymentToken,
            deposit: deposit,
            pricePerToken: pricePerToken,
            maxDuration: maxDuration,
            proofInterval: proofInterval,
            proofTimeoutWindow: proofTimeoutWindow,
            modelId: modelId
        });

        _validateSessionParams(params);

        // Model-specific validation: model must be approved and host must support it
        require(nodeRegistry.modelRegistry().isModelApproved(modelId), "Bad model");
        require(nodeRegistry.nodeSupportsModel(host, modelId), "No model");

        // Model-specific pricing validation
        uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, paymentToken);
        require(pricePerToken >= hostMinPrice, "Low price");

        _deductFromDeposit(msg.sender, paymentToken, deposit);

        sessionId = nextJobId++;
        sessionModel[sessionId] = modelId;
        _initializeSession(sessionId, params, msg.sender);

        emit SessionJobCreated(sessionId, msg.sender, host, deposit);
        emit SessionCreatedByDepositor(sessionId, msg.sender, host, deposit);
        emit SessionJobCreatedForModel(sessionId, msg.sender, host, modelId, deposit);

        return sessionId;
    }

    // ============================================================
    // V2 Direct Payment Delegation (Coinbase Smart Wallet Support)
    // ============================================================

    /**
     * @notice Create a model-specific session as an authorized delegate
     * @param payer The address whose USDC will be pulled
     * @param modelId The model ID (must be approved)
     * @param host The host to create the session with
     * @param paymentToken ERC-20 token address (cannot be address(0))
     * @param amount Amount to pull from payer's wallet
     * @param pricePerToken Price per token (must meet host's model minimum)
     * @param maxDuration Maximum session duration in seconds
     * @param proofInterval Minimum tokens between proofs
     * @param proofTimeoutWindow Timeout window for proofs (60-3600 seconds)
     * @return sessionId The created session ID
     */
    function createSessionForModelAsDelegate(
        address payer,
        bytes32 modelId,
        address host,
        address paymentToken,
        uint256 amount,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval,
        uint256 proofTimeoutWindow
    ) external nonReentrant whenNotPaused returns (uint256 sessionId) {
        require(payer != address(0), "No payer");
        if (msg.sender != payer) {
            DelegateConfig storage dc = delegateConfigs[payer][msg.sender];
            require(dc.active, "Not delegate");
            if (dc.validUntil > 0) require(block.timestamp <= dc.validUntil, "Expired");
            if (dc.maxPerSession > 0) require(amount <= dc.maxPerSession, "Over limit");
            if (dc.totalCap > 0) require(dc.spent + amount <= dc.totalCap, "Over cap");
            if (dc.allowedHost != address(0)) require(host == dc.allowedHost, "Wrong host");
            if (dc.allowedModel != bytes32(0)) require(modelId == dc.allowedModel, "Wrong model");
            require(amount <= type(uint128).max, "Overflow");
            dc.spent += uint128(amount);
        }
        require(modelId != bytes32(0), "Bad modelId");
        require(paymentToken != address(0), "ERC20 only");
        require(acceptedTokens[paymentToken], "Bad token");
        require(amount > 0, "Zero amount");
        uint256 minRequired = tokenMinDeposits[paymentToken];
        require(minRequired > 0 && tokenMaxDeposits[paymentToken] > 0, "Token not set");
        require(amount >= minRequired, "Below min");

        SessionParams memory params = SessionParams({
            host: host,
            paymentToken: paymentToken,
            deposit: amount,
            pricePerToken: pricePerToken,
            maxDuration: maxDuration,
            proofInterval: proofInterval,
            proofTimeoutWindow: proofTimeoutWindow,
            modelId: modelId
        });

        _validateSessionParams(params);

        require(nodeRegistry.modelRegistry().isModelApproved(modelId), "Bad model");
        require(nodeRegistry.nodeSupportsModel(host, modelId), "No model");
        uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, paymentToken);
        require(pricePerToken >= hostMinPrice, "Low price");

        IERC20(paymentToken).safeTransferFrom(payer, address(this), amount);

        sessionId = nextJobId++;
        sessionModel[sessionId] = modelId;
        _initializeSession(sessionId, params, payer);

        emit SessionJobCreated(sessionId, payer, host, amount);
        emit SessionJobCreatedForModel(sessionId, payer, host, modelId, amount);
        emit SessionCreatedByDelegate(sessionId, payer, msg.sender, host, modelId, amount);

        return sessionId;
    }
}
