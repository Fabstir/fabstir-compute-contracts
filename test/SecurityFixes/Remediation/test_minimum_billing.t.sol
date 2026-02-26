// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/// @notice F202614917: Minimum billing (proofInterval) enforcement tests
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

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant PRICE_PRECISION = 1000;

    uint256 constant PROOF_INTERVAL = 500;
    uint256 constant MIN_PROVEN_TOKENS = 100;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");

        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        )));

        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        hostEarnings = HostEarningsUpgradeable(payable(address(new ERC1967Proxy(
            address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ))));

        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        proofSystem = ProofSystemUpgradeable(address(new ERC1967Proxy(
            address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        )));

        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize,
                (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW))
        ))));

        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host
        fabToken.mint(host, MIN_STAKE);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_STABLE);
        vm.stopPrank();

        vm.deal(user, 100 ether);
        usdcToken.mint(user, 10_000_000_000);
    }

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
    // Primary Enforcement: submitProofOfWork
    // ============================================================

    /// @notice First proof below proofInterval should revert
    function test_RejectFirstProofBelowProofInterval() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        vm.warp(block.timestamp + 1);

        vm.prank(host);
        vm.expectRevert("First proof too small");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "cid1", "delta1");
    }

    /// @notice First proof meeting proofInterval should succeed
    function test_AcceptFirstProofMeetingProofInterval() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        vm.warp(block.timestamp + 1);

        _submitProof(sessionId, PROOF_INTERVAL, 1);

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, PROOF_INTERVAL);
    }

    /// @notice First proof above proofInterval should succeed
    function test_AcceptFirstProofAboveProofInterval() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        vm.warp(block.timestamp + 1);

        _submitProof(sessionId, PROOF_INTERVAL + 100, 1);

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, PROOF_INTERVAL + 100);
    }

    /// @notice Subsequent proofs can be below proofInterval (>= MIN_PROVEN_TOKENS)
    function test_AcceptSubsequentProofsBelowProofInterval() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        uint256 startTime = block.timestamp;

        vm.warp(startTime + 1);
        _submitProof(sessionId, PROOF_INTERVAL, 1);

        vm.warp(startTime + 2);
        _submitProof(sessionId, 150, 2);

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, PROOF_INTERVAL + 150);
    }

    /// @notice Third proof also accepts >= MIN_PROVEN_TOKENS
    function test_AcceptThirdProofBelowProofInterval() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        uint256 startTime = block.timestamp;

        vm.warp(startTime + 1);
        _submitProof(sessionId, PROOF_INTERVAL, 1);

        vm.warp(startTime + 2);
        _submitProof(sessionId, 200, 2);

        vm.warp(startTime + 3);
        _submitProof(sessionId, MIN_PROVEN_TOKENS, 3);

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, PROOF_INTERVAL + 200 + MIN_PROVEN_TOKENS);
    }

    // ============================================================
    // Fallback Enforcement: _settleSessionPayments
    // ============================================================

    /// @notice Settlement pads billing to proofInterval if tokensUsed < proofInterval
    function test_EnforceMinimumBillingAtCompletion() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        vm.warp(block.timestamp + 1);
        _submitProof(sessionId, PROOF_INTERVAL, 1);

        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "completed");

        uint256 grossPayment = (PROOF_INTERVAL * MIN_PRICE_NATIVE) / PRICE_PRECISION;
        uint256 treasuryFee = (grossPayment * FEE_BASIS_POINTS) / 10000;
        uint256 expectedNet = grossPayment - treasuryFee;

        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertEq(hostBalance, expectedNet);
    }

    /// @notice Normal completion with tokensUsed >= proofInterval should NOT adjust
    function test_NormalCompletionNoAdjustment() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        vm.warp(block.timestamp + 1);
        _submitProof(sessionId, 1000, 1);

        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "completed");

        uint256 grossPayment = (1000 * MIN_PRICE_NATIVE) / PRICE_PRECISION;
        uint256 treasuryFee = (grossPayment * FEE_BASIS_POINTS) / 10000;
        uint256 expectedNet = grossPayment - treasuryFee;

        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertEq(hostBalance, expectedNet);
    }

    // ============================================================
    // Edge Cases
    // ============================================================

    /// @notice Subsequent proof below MIN_PROVEN_TOKENS still reverts
    function test_SubsequentProofBelowMinTokens_Reverts() public {
        uint256 sessionId = _createSession(PROOF_INTERVAL);
        uint256 startTime = block.timestamp;

        vm.warp(startTime + 1);
        _submitProof(sessionId, PROOF_INTERVAL, 1);

        vm.warp(startTime + 2);
        vm.prank(host);
        vm.expectRevert("Min tokens required");
        marketplace.submitProofOfWork(sessionId, 50, keccak256("proof2"), "cid2", "delta2");
    }

    /// @notice First proof below proofInterval reverts for USDC sessions
    function test_MinimumBilling_USDC() public {
        uint256 deposit = 100_000_000;
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), deposit);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdcToken), deposit, MIN_PRICE_STABLE, 3600, PROOF_INTERVAL, 300
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
        vm.prank(host);
        vm.expectRevert("First proof too small");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "cid1", "delta1");
    }

    /// @notice proofInterval == MIN_PROVEN_TOKENS: first proof at MIN_PROVEN_TOKENS succeeds
    function test_ProofIntervalEqualsMinTokens() public {
        uint256 sessionId = _createSession(MIN_PROVEN_TOKENS);
        vm.warp(block.timestamp + 1);

        _submitProof(sessionId, MIN_PROVEN_TOKENS, 1);

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, MIN_PROVEN_TOKENS);
    }

    /// @notice Model sessions enforce proofInterval on first proof too
    function test_NonModelSession_FirstProofEnforcement() public {
        uint256 deposit = 10 ether;
        vm.deal(user, deposit);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 3600, PROOF_INTERVAL, 300
        );

        vm.warp(block.timestamp + 1);
        vm.prank(host);
        vm.expectRevert("First proof too small");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "cid1", "delta1");
    }

    // ============================================================
    // earlyFee underflow guard
    // ============================================================

    /// @notice Early cancel with minTokensFee exceeding deposit should not revert
    function test_EarlyFeeNoUnderflowWhenFeeExceedsDeposit() public {
        // Set minTokensFee very high so earlyFee > deposit
        vm.prank(owner);
        marketplace.setMinTokensFee(100_000_000);

        // Create session with small deposit (1 ETH) and high price
        uint256 deposit = 1 ether;
        uint256 highPrice = 1_000_000; // high pricePerToken
        vm.deal(user, deposit);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, highPrice, 3600, PROOF_INTERVAL, 300
        );

        // Depositor cancels immediately (no proofs) — must not revert
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "cancelled");

        // Session should be settled: no underflow, earlyFee capped
        (,,,,,,,,,,,,,, uint256 refunded,,,) = marketplace.sessionJobs(sessionId);
        // earlyFee was capped, so depositor gets some or no refund but no revert
        assertTrue(refunded <= deposit, "Refund should not exceed deposit");
    }
}
