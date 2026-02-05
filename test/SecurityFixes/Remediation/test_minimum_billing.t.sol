// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title Minimum Billing (proofInterval) Enforcement Tests
 * @notice Tests for enforcing minimum billing on first proof submission
 * @dev Issue: Contract accepts tokensClaimed >= 100 (MIN_PROVEN_TOKENS)
 *      Expected: First proof must bill at least proofInterval tokens
 */
contract MinimumBillingTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public user = address(0x3);
    address public treasury = address(0x4);

    bytes32 public modelId;

    // Constants matching contract values
    uint256 constant FEE_BASIS_POINTS = 1000; // 10%
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant PRICE_PRECISION = 1000; // Must match contract

    // Test-specific constants
    uint256 constant PROOF_INTERVAL = 500; // Session proofInterval for tests
    uint256 constant MIN_PROVEN_TOKENS = 100; // Contract minimum
    uint256 constant DEFAULT_RATE_LIMIT = 2000; // tokens/second

    function setUp() public {
        vm.startPrank(owner);

        // Deploy tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        )));

        // Deploy HostEarnings
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        hostEarnings = HostEarningsUpgradeable(payable(address(new ERC1967Proxy(
            address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ))));

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        proofSystem = ProofSystemUpgradeable(address(new ERC1967Proxy(
            address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        )));

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize,
                (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW))
        ))));

        // Configure marketplace
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        // Authorize marketplace in dependent contracts
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host with stake
        fabToken.mint(host, MIN_STAKE);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();

        // Fund user
        vm.deal(user, 100 ether);
        usdcToken.mint(user, 10_000_000_000);
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    function _createSession(uint256 proofInterval) internal returns (uint256 sessionId) {
        uint256 deposit = 10 ether;
        vm.deal(user, deposit);
        vm.prank(user);
        sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 3600, proofInterval, 300
        );
    }

    function _submitProof(uint256 sessionId, uint256 tokensClaimed, uint256 proofNonce) internal {
        bytes32 proofHash = keccak256(abi.encodePacked("proof", proofNonce));
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "cid", "delta");
    }

    // ============================================================
    // Primary Enforcement Tests (submitProofOfWork)
    // ============================================================

    /**
     * @notice First proof below proofInterval should revert
     * @dev Expected failure in RED phase: Currently accepts 100 tokens
     */
    function test_RejectFirstProofBelowProofInterval() public {
        // Create session with proofInterval = 500
        uint256 sessionId = _createSession(PROOF_INTERVAL);

        // Advance time to satisfy rate limit (1 second per 2000 tokens default)
        vm.warp(block.timestamp + 1);

        // Try to submit first proof with 100 tokens (below proofInterval of 500)
        vm.prank(host);
        vm.expectRevert("First proof must meet proofInterval minimum");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "cid1", "delta1");
    }

    /**
     * @notice First proof meeting proofInterval should succeed
     */
    function test_AcceptFirstProofMeetingProofInterval() public {
        // Create session with proofInterval = 500
        uint256 sessionId = _createSession(PROOF_INTERVAL);

        // Advance time
        vm.warp(block.timestamp + 1);

        // Submit first proof with exactly proofInterval tokens
        _submitProof(sessionId, PROOF_INTERVAL, 1);

        // Verify tokens recorded
        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, PROOF_INTERVAL, "Tokens should match proofInterval");
    }

    /**
     * @notice First proof above proofInterval should succeed
     */
    function test_AcceptFirstProofAboveProofInterval() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        vm.warp(block.timestamp + 1);

        // Submit first proof with MORE than proofInterval
        _submitProof(sessionId, PROOF_INTERVAL + 100, 1);

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, PROOF_INTERVAL + 100, "Tokens should exceed proofInterval");
    }

    /**
     * @notice Subsequent proofs can be below proofInterval (>= MIN_PROVEN_TOKENS)
     */
    function test_AcceptSubsequentProofsBelowProofInterval() public {
        // Create session with proofInterval = 500
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        uint256 startTime = block.timestamp;

        // Submit first proof meeting proofInterval (need enough time for rate limit: 500/2000 = 0.25s, use 1s)
        vm.warp(startTime + 1);
        _submitProof(sessionId, PROOF_INTERVAL, 1);

        // Submit second proof below proofInterval but >= MIN_PROVEN_TOKENS
        // Need enough time for 150 tokens at 2000/s rate: 150/2000 = 0.075s
        vm.warp(startTime + 2);
        _submitProof(sessionId, 150, 2); // 150 >= 100, but < 500

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, PROOF_INTERVAL + 150, "Total should be 650");
    }

    /**
     * @notice Third and later proofs also accept >= MIN_PROVEN_TOKENS
     */
    function test_AcceptThirdProofBelowProofInterval() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        uint256 startTime = block.timestamp;

        // First proof (500 tokens, need 500/2000 = 0.25s)
        vm.warp(startTime + 1);
        _submitProof(sessionId, PROOF_INTERVAL, 1);

        // Second proof (200 tokens, need 200/2000 = 0.1s)
        vm.warp(startTime + 2);
        _submitProof(sessionId, 200, 2);

        // Third proof (100 tokens, need 100/2000 = 0.05s)
        vm.warp(startTime + 3);
        _submitProof(sessionId, MIN_PROVEN_TOKENS, 3); // Exactly MIN_PROVEN_TOKENS

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, PROOF_INTERVAL + 200 + MIN_PROVEN_TOKENS, "Total should be 800");
    }

    // ============================================================
    // Fallback Enforcement Tests (_settleSessionPayments)
    // ============================================================

    /**
     * @notice Completion should pad billing to proofInterval if tokensUsed < proofInterval
     * @dev This is a fallback for edge cases - shouldn't happen with primary enforcement
     *      Expected failure in RED phase: hostPayment based on tokensUsed, not padded
     */
    function test_EnforceMinimumBillingAtCompletion() public {
        // Create session with proofInterval = 500
        uint256 sessionId = _createSession(PROOF_INTERVAL);

        // Submit first proof meeting proofInterval
        vm.warp(block.timestamp + 1);
        _submitProof(sessionId, PROOF_INTERVAL, 1);

        // Complete session
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "completed");

        // Calculate expected host payment: proofInterval * pricePerToken / PRICE_PRECISION
        // With 10% treasury fee deducted
        uint256 grossPayment = (PROOF_INTERVAL * MIN_PRICE_NATIVE) / PRICE_PRECISION;
        uint256 treasuryFee = (grossPayment * FEE_BASIS_POINTS) / 10000;
        uint256 expectedNet = grossPayment - treasuryFee;

        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertEq(hostBalance, expectedNet, "Host should receive minimum billing payment");
    }

    /**
     * @notice Normal completion with tokensUsed >= proofInterval should NOT adjust
     */
    function test_NormalCompletionNoAdjustment() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);

        // Submit proof with tokens > proofInterval
        vm.warp(block.timestamp + 1);
        _submitProof(sessionId, 1000, 1);

        // Complete session
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "completed");

        // Host payment should be based on 1000 tokens (not padded to proofInterval)
        uint256 grossPayment = (1000 * MIN_PRICE_NATIVE) / PRICE_PRECISION;
        uint256 treasuryFee = (grossPayment * FEE_BASIS_POINTS) / 10000;
        uint256 expectedNet = grossPayment - treasuryFee;

        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertEq(hostBalance, expectedNet, "Host payment based on actual tokensUsed");
    }

    /**
     * @notice Early cancellation (no proofs) should use minTokensFee, NOT proofInterval padding
     */
    function test_EarlyCancellationUnaffected() public {
        // Set early cancellation fee
        vm.prank(owner);
        marketplace.setMinTokensFee(200); // Less than proofInterval

        uint256 sessionId = _createSession(PROOF_INTERVAL);

        // Complete WITHOUT submitting any proofs (early cancel by depositor)
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "cancelled-early");

        // Host should receive early cancel fee based on minTokensFee (200), NOT proofInterval (500)
        // Note: Treasury fee only applies to proven work (hostPayment), not to earlyFee
        // Since there are no proofs, hostPayment = 0, so treasuryFee = 0
        uint256 earlyFee = (200 * MIN_PRICE_NATIVE) / PRICE_PRECISION;
        // No treasury fee on early cancel! Full earlyFee goes to host.

        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertEq(hostBalance, earlyFee, "Should use minTokensFee, not proofInterval");
    }

    /**
     * @notice Host completing with no proofs should result in zero payment (no early fee)
     */
    function test_HostCompleteNoProofs_NoPayment() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(200);

        uint256 sessionId = _createSession(PROOF_INTERVAL);

        // Wait for dispute window
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Host completes (should not get early cancel fee - only depositor gets that)
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "host-completed");

        // Host should receive nothing (no proofs, not early cancel by depositor)
        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertEq(hostBalance, 0, "Host should receive nothing");
    }

    // ============================================================
    // Edge Case Tests
    // ============================================================

    /**
     * @notice Verify MIN_PROVEN_TOKENS check still works for subsequent proofs
     */
    function test_SubsequentProofBelowMinTokens_Reverts() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        uint256 startTime = block.timestamp;

        // First proof succeeds
        vm.warp(startTime + 1);
        _submitProof(sessionId, PROOF_INTERVAL, 1);

        // Second proof with < MIN_PROVEN_TOKENS should still revert
        vm.warp(startTime + 2);
        vm.prank(host);
        vm.expectRevert("Min tokens required");
        marketplace.submitProofOfWork(sessionId, 50, keccak256("proof2"), "cid2", "delta2");
    }

    /**
     * @notice Test with USDC payment token
     */
    function test_MinimumBilling_USDC() public {
        uint256 deposit = 100_000_000; // 100 USDC (6 decimals)
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), deposit);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdcToken), deposit, MIN_PRICE_STABLE, 3600, PROOF_INTERVAL, 300
        );
        vm.stopPrank();

        // First proof below proofInterval should revert
        vm.warp(block.timestamp + 1);
        vm.prank(host);
        vm.expectRevert("First proof must meet proofInterval minimum");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "cid1", "delta1");
    }

    /**
     * @notice Test with proofInterval exactly equal to MIN_PROVEN_TOKENS
     */
    function test_ProofIntervalEqualsMinTokens() public {
        // Create session with proofInterval = MIN_PROVEN_TOKENS
        uint256 sessionId = _createSession(MIN_PROVEN_TOKENS);

        vm.warp(block.timestamp + 1);

        // Submit exactly MIN_PROVEN_TOKENS (which equals proofInterval)
        _submitProof(sessionId, MIN_PROVEN_TOKENS, 1);

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, MIN_PROVEN_TOKENS, "Should accept MIN_PROVEN_TOKENS");
    }

    /**
     * @notice Non-model sessions should also enforce proofInterval on first proof
     */
    function test_NonModelSession_FirstProofEnforcement() public {
        // Create non-model session
        uint256 deposit = 10 ether;
        vm.deal(user, deposit);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: deposit}(
            host, MIN_PRICE_NATIVE, 3600, PROOF_INTERVAL, 300
        );

        vm.warp(block.timestamp + 1);

        // First proof below proofInterval should revert
        vm.prank(host);
        vm.expectRevert("First proof must meet proofInterval minimum");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "cid1", "delta1");
    }
}
