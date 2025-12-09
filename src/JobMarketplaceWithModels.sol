// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./NodeRegistryWithModels.sol";
import "./interfaces/IJobMarketplace.sol";
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
 * @title JobMarketplaceWithModels
 * @dev JobMarketplace compatible with NodeRegistryWithModels and model governance
 * @notice Stores prompts and responses as S5 CIDs with model validation support
 */
contract JobMarketplaceWithModels is ReentrancyGuard {
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

    // Job details structure
    struct JobDetails {
        string promptS5CID;
        uint256 maxTokens;
    }

    // Job requirements structure
    struct JobRequirements {
        uint256 maxTimeToComplete;
    }

    // Job structure
    struct Job {
        uint256 id;
        address requester;
        address paymentToken;
        uint256 payment;
        JobDetails details;
        JobRequirements requirements;
        address claimedBy;
        JobStatus status;
        string responseS5CID;
        uint256 claimedAt;
        JobType jobType;
    }

    // Session job structure
    struct SessionJob {
        uint256 id;
        address depositor;      // NEW: tracks who deposited (EOA or Smart Account)
        address requester;      // DEPRECATED but kept for backward compatibility
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
        bytes32 lastProofHash;  // S5: Hash of most recent proof (32 bytes)
        string lastProofCID;    // S5: CID of most recent proof in S5 storage
    }

    // Chain configuration structure (Phase 4.1)
    struct ChainConfig {
        address nativeWrapper;     // WETH on Base, WBNB on opBNB
        address stablecoin;        // USDC address per chain
        uint256 minDeposit;        // Chain-specific minimum
        string nativeTokenSymbol;  // "ETH" or "BNB"
    }

    // Constants
    uint256 public constant MIN_DEPOSIT = 0.0002 ether;
    uint256 public constant MIN_PROVEN_TOKENS = 100;
    uint256 public constant ABANDONMENT_TIMEOUT = 24 hours;
    uint256 public immutable DISPUTE_WINDOW; // Configurable via constructor

    // State variables
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => SessionJob) public sessionJobs;
    mapping(address => uint256[]) public userJobs;
    mapping(address => uint256[]) public hostJobs;
    mapping(address => uint256[]) public userSessions;
    mapping(address => uint256[]) public hostSessions;

    uint256 public nextJobId = 1;
    // NOTE: This immutable value is set from TREASURY_FEE_PERCENTAGE env var during deployment
    // FEE_BASIS_POINTS = TREASURY_FEE_PERCENTAGE * 100 (e.g., 10% = 1000 basis points)
    // Host receives (10000 - FEE_BASIS_POINTS) / 100 percent (e.g., 90% with 10% treasury fee)
    uint256 public immutable FEE_BASIS_POINTS; // Treasury fee in basis points
    address public treasuryAddress = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;
    address public usdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    NodeRegistryWithModels public nodeRegistry;
    IReputationSystem public reputationSystem;
    IProofSystem public proofSystem;
    HostEarnings public hostEarnings;

    // USDC-specific configuration
    uint256 public constant USDC_MIN_DEPOSIT = 800000; // 0.80 USDC
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

    // Events
    event JobPosted(uint256 indexed jobId, address indexed requester, string promptS5CID);
    event JobClaimed(uint256 indexed jobId, address indexed host);
    event JobCompleted(uint256 indexed jobId, address indexed host, string responseS5CID);
    event SessionJobCreated(uint256 indexed jobId, address indexed requester, address indexed host, uint256 deposit);
    event ProofSubmitted(uint256 indexed jobId, address indexed host, uint256 tokensClaimed, bytes32 proofHash, string proofCID);
    event SessionCompleted(uint256 indexed jobId, uint256 totalTokensUsed, uint256 hostEarnings, uint256 userRefund);
    // New event that tracks who completed the session (Phase 3.1 - Anyone-can-complete pattern)
    event SessionCompleted(uint256 indexed jobId, address indexed completedBy, uint256 tokensUsed, uint256 paymentAmount, uint256 refundAmount);
    event SessionTimedOut(uint256 indexed jobId, uint256 hostEarnings, uint256 userRefund);
    event SessionAbandoned(uint256 indexed jobId, uint256 userRefund);
    event PaymentSent(address indexed recipient, uint256 amount);
    event TreasuryWithdrawal(address indexed token, uint256 amount);

    // Wallet-agnostic deposit events (Phase 1.1)
    // Deposit/Withdrawal events (Phase 1.4 - now properly indexed in Phase 3.3)
    event DepositReceived(
        address indexed depositor,
        uint256 amount,
        address indexed token  // address(0) for native
    );

    event WithdrawalProcessed(
        address indexed depositor,
        uint256 amount,
        address indexed token  // address(0) for native
    );

    // Session events using depositor terminology (Phase 2.1)
    event SessionCreatedByDepositor(
        uint256 indexed sessionId,
        address indexed depositor,
        address indexed host,
        uint256 deposit
    );

    // Token acceptance event (Phase 2.4)
    event TokenAccepted(address indexed token, uint256 minDeposit);

    modifier onlyRegisteredHost(address host) {
        // Just check if host is registered by looking at operator
        // NodeRegistryWithModels has different return signature
        _;
    }

    constructor(address _nodeRegistry, address payable _hostEarnings, uint256 _feeBasisPoints, uint256 _disputeWindow) {
        require(_feeBasisPoints <= 10000, "Fee cannot exceed 100%");
        require(_disputeWindow > 0 && _disputeWindow <= 7 days, "Invalid dispute window");
        FEE_BASIS_POINTS = _feeBasisPoints;
        DISPUTE_WINDOW = _disputeWindow;
        nodeRegistry = NodeRegistryWithModels(_nodeRegistry);
        hostEarnings = HostEarnings(_hostEarnings);

        // Initialize accepted tokens
        acceptedTokens[usdcAddress] = true;
        tokenMinDeposits[usdcAddress] = USDC_MIN_DEPOSIT;
    }

    function setProofSystem(address _proofSystem) external {
        require(msg.sender == treasuryAddress, "Only treasury");
        proofSystem = IProofSystem(_proofSystem);
    }

    // Initialize chain configuration (Phase 4.1)
    function initializeChainConfig(ChainConfig memory _config) external {
        require(msg.sender == treasuryAddress, "Only owner");
        require(chainConfig.nativeWrapper == address(0), "Already initialized");
        chainConfig = _config;
    }

    function createSessionJob(
        address host,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval
    ) external payable nonReentrant returns (uint256 jobId) {
        require(msg.value >= MIN_DEPOSIT, "Insufficient deposit");
        require(msg.value <= 1000 ether, "Deposit too large");
        require(pricePerToken > 0, "Invalid price");
        require(maxDuration > 0 && maxDuration <= 365 days, "Invalid duration");
        require(proofInterval > 0, "Invalid proof interval");
        require(host != address(0), "Invalid host");

        _validateProofRequirements(proofInterval, msg.value, pricePerToken);
        _validateHostRegistration(host);

        // Validate price meets host's minimum for native token (ETH/BNB)
        uint256 hostMinPrice = nodeRegistry.getNodePricing(host, address(0)); // address(0) = native token
        require(pricePerToken >= hostMinPrice, "Price below host minimum");

        jobId = nextJobId++;

        SessionJob storage session = sessionJobs[jobId];
        session.id = jobId;
        session.depositor = msg.sender;  // NEW: track depositor (wallet-agnostic)
        session.requester = msg.sender;  // DEPRECATED: keep for compatibility
        session.host = host;
        session.paymentToken = address(0);
        session.deposit = msg.value;
        session.pricePerToken = pricePerToken;
        session.maxDuration = maxDuration;
        session.startTime = block.timestamp;
        session.lastProofTime = block.timestamp;
        session.proofInterval = proofInterval;
        session.status = SessionStatus.Active;

        // Track inline deposit (Phase 2.3)
        userDepositsNative[msg.sender] += msg.value;

        userSessions[msg.sender].push(jobId);
        hostSessions[host].push(jobId);

        emit SessionJobCreated(jobId, msg.sender, host, msg.value);
        emit SessionCreatedByDepositor(jobId, msg.sender, host, msg.value);  // NEW event

        return jobId;
    }

    function createSessionJobWithToken(
        address host, address token, uint256 deposit,
        uint256 pricePerToken, uint256 maxDuration, uint256 proofInterval
    ) external returns (uint256 jobId) {
        require(acceptedTokens[token], "Token not accepted");
        uint256 minRequired = tokenMinDeposits[token];
        require(minRequired > 0, "Token not configured");
        require(deposit >= minRequired, "Insufficient deposit");
        require(deposit > 0, "Zero deposit");

        require(pricePerToken > 0, "Invalid price");
        require(maxDuration > 0 && maxDuration <= 365 days, "Invalid duration");
        require(proofInterval > 0, "Invalid proof interval");
        require(host != address(0), "Invalid host");
        require(deposit <= 1000 ether, "Deposit too large");

        _validateHostRegistration(host);
        _validateProofRequirements(proofInterval, deposit, pricePerToken);

        // Validate price meets host's minimum for the specified token (USDC or other stablecoin)
        uint256 hostMinPrice = nodeRegistry.getNodePricing(host, token);
        require(pricePerToken >= hostMinPrice, "Price below host minimum");

        IERC20(token).transferFrom(msg.sender, address(this), deposit);

        jobId = nextJobId++;

        SessionJob storage session = sessionJobs[jobId];
        session.id = jobId;
        session.depositor = msg.sender;  // NEW: track depositor (wallet-agnostic)
        session.requester = msg.sender;  // DEPRECATED: keep for compatibility
        session.host = host;
        session.paymentToken = token;
        session.deposit = deposit;
        session.pricePerToken = pricePerToken;
        session.maxDuration = maxDuration;
        session.startTime = block.timestamp;
        session.lastProofTime = block.timestamp;
        session.proofInterval = proofInterval;
        session.status = SessionStatus.Active;

        // Track inline token deposit (Phase 2.3)
        userDepositsToken[msg.sender][token] += deposit;

        userSessions[msg.sender].push(jobId);
        hostSessions[host].push(jobId);

        emit SessionJobCreated(jobId, msg.sender, host, deposit);
        emit SessionCreatedByDepositor(jobId, msg.sender, host, deposit);  // NEW event

        return jobId;
    }

    function _validateHostRegistration(address host) internal view {
        // For now, just check if host address is not zero
        // Full validation would require proper struct handling
        require(host != address(0), "Invalid host address");
        // TODO: Add proper validation once we handle the struct properly
    }

    function _validateProofRequirements(uint256 proofInterval, uint256 deposit, uint256 pricePerToken) internal pure {
        uint256 maxTokens = deposit / pricePerToken;
        uint256 tokensPerProof = proofInterval;
        require(tokensPerProof >= MIN_PROVEN_TOKENS, "Proof interval too small");
        require(maxTokens >= tokensPerProof, "Deposit too small for proof interval");
    }

    function submitProofOfWork(
        uint256 jobId,
        uint256 tokensClaimed,
        bytes32 proofHash,
        string calldata proofCID
    ) external nonReentrant {
        SessionJob storage session = sessionJobs[jobId];
        require(session.status == SessionStatus.Active, "Session not active");
        require(msg.sender == session.host, "Only host can submit proof");
        require(tokensClaimed >= MIN_PROVEN_TOKENS, "Must claim minimum tokens");

        uint256 timeSinceLastProof = block.timestamp - session.lastProofTime;
        uint256 expectedTokens = timeSinceLastProof * 10;
        require(tokensClaimed <= expectedTokens * 2, "Excessive tokens claimed");

        uint256 newTotal = session.tokensUsed + tokensClaimed;
        uint256 maxTokens = session.deposit / session.pricePerToken;
        require(newTotal <= maxTokens, "Exceeds deposit");

        // S5: Store proof hash and CID instead of full proof
        session.lastProofHash = proofHash;
        session.lastProofCID = proofCID;

        // Keep legacy proof tracking for compatibility
        session.proofs.push(ProofSubmission({
            proofHash: proofHash,
            tokensClaimed: tokensClaimed,
            timestamp: block.timestamp,
            verified: false  // No on-chain verification with S5 storage
        }));

        session.tokensUsed = newTotal;
        session.lastProofTime = block.timestamp;

        emit ProofSubmitted(jobId, msg.sender, tokensClaimed, proofHash, proofCID);
    }

    function completeSessionJob(uint256 jobId, string calldata conversationCID) external nonReentrant {
        SessionJob storage session = sessionJobs[jobId];
        require(session.status == SessionStatus.Active, "Session not active");
        // REMOVED: Authorization check - anyone can complete (enables gasless ending pattern)
        // This allows hosts to complete on behalf of users, reducing gas costs for users

        // Dispute window only waived for the original requester
        if (msg.sender != session.requester) {
            require(block.timestamp >= session.startTime + DISPUTE_WINDOW, "Must wait dispute window");
        }

        session.status = SessionStatus.Completed;
        session.conversationCID = conversationCID;

        _settleSessionPayments(jobId, msg.sender);
    }

    function _settleSessionPayments(uint256 jobId, address completedBy) internal {
        SessionJob storage session = sessionJobs[jobId];

        uint256 hostPayment = session.tokensUsed * session.pricePerToken;
        uint256 userRefund = session.deposit > hostPayment ? session.deposit - hostPayment : 0;

        if (hostPayment > 0) {
            // Calculate fees based on FEE_BASIS_POINTS (which should match TREASURY_FEE_PERCENTAGE from env)
            uint256 treasuryFee = (hostPayment * FEE_BASIS_POINTS) / 10000;
            uint256 netHostPayment = hostPayment - treasuryFee; // Host gets remainder (HOST_EARNINGS_PERCENTAGE)

            if (session.paymentToken == address(0)) {
                accumulatedTreasuryNative += treasuryFee;
                // Send ETH to HostEarnings contract
                (bool sent, ) = payable(address(hostEarnings)).call{value: netHostPayment}("");
                require(sent, "ETH transfer to HostEarnings failed");
                // Credit the host's earnings
                hostEarnings.creditEarnings(session.host, netHostPayment, address(0));
            } else {
                accumulatedTreasuryTokens[session.paymentToken] += treasuryFee;
                // Transfer tokens to HostEarnings
                IERC20(session.paymentToken).transfer(address(hostEarnings), netHostPayment);
                // Credit the host's earnings
                hostEarnings.creditEarnings(session.host, netHostPayment, session.paymentToken);
            }

            session.withdrawnByHost = netHostPayment;
        }

        if (userRefund > 0) {
            if (session.paymentToken == address(0)) {
                (bool sent, ) = payable(session.requester).call{value: userRefund}("");
                require(sent, "ETH refund failed");
            } else {
                IERC20(session.paymentToken).transfer(session.requester, userRefund);
            }
            session.refundedToUser = userRefund;
        }

        // Emit both events for backward compatibility
        emit SessionCompleted(jobId, session.tokensUsed, session.withdrawnByHost, userRefund);
        // Emit new event showing who completed it (Phase 3.1)
        emit SessionCompleted(jobId, completedBy, session.tokensUsed, hostPayment, userRefund);
    }

    function triggerSessionTimeout(uint256 jobId) external nonReentrant {
        SessionJob storage session = sessionJobs[jobId];
        require(session.status == SessionStatus.Active, "Session not active");

        bool hasTimedOut = (block.timestamp > session.startTime + session.maxDuration) ||
                          (block.timestamp > session.lastProofTime + session.proofInterval * 3);

        require(hasTimedOut, "Session not timed out");

        session.status = SessionStatus.TimedOut;
        _settleSessionPayments(jobId, msg.sender);

        emit SessionTimedOut(jobId, session.withdrawnByHost, session.refundedToUser);
    }

    function claimWithProof(
        uint256 jobId,
        bytes calldata proof,
        string calldata responseS5CID
    ) external nonReentrant {
        Job storage job = jobs[jobId];
        require(job.status == JobStatus.Claimed, "Job not claimed");
        require(job.claimedBy == msg.sender, "Not claimed by you");

        uint256 maxTokens = job.details.maxTokens;

        if (address(proofSystem) != address(0)) {
            bool verified = proofSystem.verifyAndMarkComplete(proof, msg.sender, maxTokens);
            require(verified, "Invalid proof");
        }

        job.status = JobStatus.Completed;
        job.responseS5CID = responseS5CID;

        uint256 payment = job.payment;
        // Calculate fees based on FEE_BASIS_POINTS (which should match TREASURY_FEE_PERCENTAGE from env)
        uint256 treasuryFee = (payment * FEE_BASIS_POINTS) / 10000;
        uint256 netPayment = payment - treasuryFee; // Host gets remainder (HOST_EARNINGS_PERCENTAGE)

        address paymentToken = job.paymentToken;

        if (paymentToken == address(0)) {
            accumulatedTreasuryNative += treasuryFee;
            // Send ETH to HostEarnings contract
            (bool sent, ) = payable(address(hostEarnings)).call{value: netPayment}("");
            require(sent, "ETH transfer to HostEarnings failed");
            // Credit the host's earnings
            hostEarnings.creditEarnings(msg.sender, netPayment, address(0));
        } else {
            accumulatedTreasuryTokens[paymentToken] += treasuryFee;
            // Transfer tokens to HostEarnings
            IERC20(paymentToken).transfer(address(hostEarnings), netPayment);
            // Credit the host's earnings
            hostEarnings.creditEarnings(msg.sender, netPayment, paymentToken);
        }

        emit JobCompleted(jobId, msg.sender, responseS5CID);
        emit PaymentSent(msg.sender, netPayment);
    }

    // Treasury withdrawal functions
    function withdrawTreasuryNative() external {
        require(msg.sender == treasuryAddress, "Only treasury");
        uint256 amount = accumulatedTreasuryNative;
        require(amount > 0, "No native tokens to withdraw");

        accumulatedTreasuryNative = 0;
        (bool sent, ) = payable(treasuryAddress).call{value: amount}("");
        require(sent, "Native token transfer failed");

        emit TreasuryWithdrawal(address(0), amount);
    }

    function withdrawTreasuryTokens(address token) external {
        require(msg.sender == treasuryAddress, "Only treasury");
        uint256 amount = accumulatedTreasuryTokens[token];
        require(amount > 0, "No tokens to withdraw");

        accumulatedTreasuryTokens[token] = 0;
        IERC20(token).transfer(treasuryAddress, amount);

        emit TreasuryWithdrawal(token, amount);
    }

    function withdrawAllTreasuryFees(address[] calldata tokens) external {
        require(msg.sender == treasuryAddress, "Only treasury");

        if (accumulatedTreasuryNative > 0) {
            uint256 ethAmount = accumulatedTreasuryNative;
            accumulatedTreasuryNative = 0;
            (bool sent, ) = payable(treasuryAddress).call{value: ethAmount}("");
            require(sent, "Native token transfer failed");
            emit TreasuryWithdrawal(address(0), ethAmount);
        }

        for (uint i = 0; i < tokens.length; i++) {
            uint256 amount = accumulatedTreasuryTokens[tokens[i]];
            if (amount > 0) {
                accumulatedTreasuryTokens[tokens[i]] = 0;
                IERC20(tokens[i]).transfer(treasuryAddress, amount);
                emit TreasuryWithdrawal(tokens[i], amount);
            }
        }
    }

    /**
     * @notice Add a new accepted stablecoin token (treasury only)
     * @dev Allows treasury to add support for new stablecoins (e.g., EUR stablecoin)
     * @param token The stablecoin token address to accept
     * @param minDeposit The minimum deposit required for sessions with this token
     */
    function addAcceptedToken(address token, uint256 minDeposit) external {
        require(msg.sender == treasuryAddress, "Only treasury");
        require(!acceptedTokens[token], "Token already accepted");
        require(minDeposit > 0, "Invalid minimum deposit");
        require(token != address(0), "Invalid token address");

        acceptedTokens[token] = true;
        tokenMinDeposits[token] = minDeposit;

        emit TokenAccepted(token, minDeposit);
    }

    // Wallet-agnostic deposit functions (Phase 1.2)

    /**
     * @notice Deposit native token (ETH on Base, BNB on opBNB) to user's account
     * @dev Works identically for EOA and Smart Account wallets
     */
    function depositNative() external payable {
        require(msg.value > 0, "Zero deposit");
        userDepositsNative[msg.sender] += msg.value;
        emit DepositReceived(msg.sender, msg.value, address(0));
    }

    /**
     * @notice Deposit ERC20 tokens to user's account
     * @dev msg.sender can be EOA or Smart Account
     * @param token Token address (USDC, etc.)
     * @param amount Amount to deposit
     */
    function depositToken(address token, uint256 amount) external {
        require(amount > 0, "Zero deposit");
        require(token != address(0), "Invalid token");

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        userDepositsToken[msg.sender][token] += amount;
        emit DepositReceived(msg.sender, amount, token);
    }

    // Wallet-agnostic withdrawal functions (Phase 1.3)

    /**
     * @notice Withdraw deposited native token (ETH on Base, BNB on opBNB)
     * @dev Returns funds to depositor (EOA or Smart Account)
     * @param amount Amount to withdraw
     */
    function withdrawNative(uint256 amount) external nonReentrant {
        require(userDepositsNative[msg.sender] >= amount, "Insufficient balance");

        userDepositsNative[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);

        emit WithdrawalProcessed(msg.sender, amount, address(0));
    }

    /**
     * @notice Withdraw deposited tokens
     * @dev Returns tokens to depositor (EOA or Smart Account)
     * @param token Token address
     * @param amount Amount to withdraw
     */
    function withdrawToken(address token, uint256 amount) external nonReentrant {
        require(userDepositsToken[msg.sender][token] >= amount, "Insufficient balance");

        userDepositsToken[msg.sender][token] -= amount;
        IERC20(token).transfer(msg.sender, amount);

        emit WithdrawalProcessed(msg.sender, amount, token);
    }

    // Balance query functions (Phase 1.4)

    /**
     * @notice Get deposit balance for an account
     * @dev Works for any address type (EOA or Smart Account)
     * @param account The account to query
     * @param token Token address (address(0) for native)
     * @return The deposit balance
     */
    function getDepositBalance(address account, address token) external view returns (uint256) {
        if (token == address(0)) {
            return userDepositsNative[account];
        }
        return userDepositsToken[account][token];
    }

    /**
     * @notice Get multiple deposit balances for an account
     * @dev Batch query for efficiency
     * @param account The account to query
     * @param tokens Array of token addresses (address(0) for native)
     * @return Array of balances in same order as tokens
     */
    function getDepositBalances(address account, address[] calldata tokens)
        external view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = tokens[i] == address(0)
                ? userDepositsNative[account]
                : userDepositsToken[account][tokens[i]];
        }
        return balances;
    }

    /**
     * @notice Create session using deposited funds (Phase 2.2)
     * @dev Uses pre-deposited funds instead of requiring payment
     * @param host Host address for the session
     * @param paymentToken Token address (address(0) for native)
     * @param deposit Amount to allocate for session
     * @param pricePerToken Price per token
     * @param maxDuration Maximum session duration
     * @param proofInterval Proof submission interval
     * @return sessionId ID of created session
     */
    function createSessionFromDeposit(
        address host,
        address paymentToken,
        uint256 deposit,
        uint256 pricePerToken,
        uint256 maxDuration,
        uint256 proofInterval
    ) external nonReentrant returns (uint256 sessionId) {
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
        session.requester = msg.sender;
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

    receive() external payable {}
    fallback() external payable {}
}