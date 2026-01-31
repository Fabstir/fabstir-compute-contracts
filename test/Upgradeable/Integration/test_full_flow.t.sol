// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Upgradeable contracts
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";

import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title End-to-End Integration Test for All Upgradeable Contracts
 * @dev Tests the complete flow: deployment, registration, session creation,
 *      proof submission, completion, and earnings withdrawal
 */
contract FullFlowIntegrationTest is Test {
    // Implementations
    ModelRegistryUpgradeable public modelRegistryImpl;
    ProofSystemUpgradeable public proofSystemImpl;
    HostEarningsUpgradeable public hostEarningsImpl;
    NodeRegistryWithModelsUpgradeable public nodeRegistryImpl;
    JobMarketplaceWithModelsUpgradeable public jobMarketplaceImpl;

    // Proxies (cast to implementation types for easy access)
    ModelRegistryUpgradeable public modelRegistry;
    ProofSystemUpgradeable public proofSystem;
    HostEarningsUpgradeable public hostEarnings;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    JobMarketplaceWithModelsUpgradeable public jobMarketplace;

    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public deployer = address(0x1);
    address public treasury = address(0x2);
    // Host addresses derived from private keys for signature verification
    uint256 public host1PrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    uint256 public host2PrivateKey = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;
    address public host1;
    address public host2;
    address public user1 = address(0x200);
    address public user2 = address(0x201);

    bytes32 public modelId1;
    bytes32 public modelId2;

    uint256 constant feeBasisPoints = 1000; // 10%
    uint256 constant disputeWindow = 30; // 30 seconds
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Derive host addresses from private keys (required for signature verification)
        host1 = vm.addr(host1PrivateKey);
        host2 = vm.addr(host2PrivateKey);

        vm.startPrank(deployer);

        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // ============================================================
        // Deploy ModelRegistry Upgradeable
        // ============================================================
        modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add approved models
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelRegistry.addTrustedModel("Model2/Repo", "model2.gguf", bytes32(uint256(2)));
        modelId1 = modelRegistry.getModelId("Model1/Repo", "model1.gguf");
        modelId2 = modelRegistry.getModelId("Model2/Repo", "model2.gguf");

        // ============================================================
        // Deploy ProofSystem Upgradeable
        // ============================================================
        proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(new ERC1967Proxy(
            address(proofSystemImpl),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        ));
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // ============================================================
        // Deploy HostEarnings Upgradeable
        // ============================================================
        hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(new ERC1967Proxy(
            address(hostEarningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // ============================================================
        // Deploy NodeRegistry Upgradeable
        // ============================================================
        nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (
                address(fabToken),
                address(modelRegistry)
            ))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // ============================================================
        // Deploy JobMarketplace Upgradeable
        // ============================================================
        jobMarketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address jobMarketplaceProxy = address(new ERC1967Proxy(
            address(jobMarketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                feeBasisPoints,
                disputeWindow
            ))
        ));
        jobMarketplace = JobMarketplaceWithModelsUpgradeable(payable(jobMarketplaceProxy));

        // ============================================================
        // Configure Cross-Contract References
        // ============================================================

        // Authorize JobMarketplace to credit earnings
        hostEarnings.setAuthorizedCaller(address(jobMarketplace), true);

        // Configure ProofSystem in JobMarketplace (AUDIT-F2: now required for proof submission)
        jobMarketplace.setProofSystem(address(proofSystem));

        // Set treasury
        jobMarketplace.setTreasury(treasury);

        vm.stopPrank();

        // ============================================================
        // Setup Test Accounts
        // ============================================================

        // Mint FAB tokens to hosts for staking
        fabToken.mint(host1, 10000 * 10**18);
        fabToken.mint(host2, 10000 * 10**18);

        // Approve FAB spending for hosts
        vm.prank(host1);
        fabToken.approve(address(nodeRegistry), type(uint256).max);
        vm.prank(host2);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        // Give ETH to users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Give USDC to users
        usdcToken.mint(user1, 10000 * 10**6);
        usdcToken.mint(user2, 10000 * 10**6);

        vm.prank(user1);
        usdcToken.approve(address(jobMarketplace), type(uint256).max);
        vm.prank(user2);
        usdcToken.approve(address(jobMarketplace), type(uint256).max);
    }

    // ============================================================
    // Deployment Verification Tests
    // ============================================================

    function test_AllProxiesDeployed() public view {
        assertTrue(address(proofSystem) != address(0), "ProofSystem proxy deployed");
        assertTrue(address(hostEarnings) != address(0), "HostEarnings proxy deployed");
        assertTrue(address(nodeRegistry) != address(0), "NodeRegistry proxy deployed");
        assertTrue(address(jobMarketplace) != address(0), "JobMarketplace proxy deployed");
    }

    function test_ProxiesHaveCorrectOwner() public view {
        assertEq(proofSystem.owner(), deployer, "ProofSystem owner");
        assertEq(hostEarnings.owner(), deployer, "HostEarnings owner");
        assertEq(nodeRegistry.owner(), deployer, "NodeRegistry owner");
        assertEq(jobMarketplace.owner(), deployer, "JobMarketplace owner");
    }

    function test_CrossContractReferencesConfigured() public view {
        assertEq(address(jobMarketplace.nodeRegistry()), address(nodeRegistry), "JobMarketplace -> NodeRegistry");
        assertEq(address(jobMarketplace.hostEarnings()), address(hostEarnings), "JobMarketplace -> HostEarnings");
        assertTrue(hostEarnings.authorizedCallers(address(jobMarketplace)), "HostEarnings authorized JobMarketplace");
    }

    // ============================================================
    // Full Flow Test: Host Registration
    // ============================================================

    function test_HostRegistrationThroughProxy() public {
        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId1;
        models[1] = modelId2;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU A100", "vram": "80GB"}',
            "https://api.host1.example.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        assertTrue(nodeRegistry.isActiveNode(host1), "Host1 should be active");
        assertTrue(nodeRegistry.nodeSupportsModel(host1, modelId1), "Host1 supports model1");
        assertTrue(nodeRegistry.nodeSupportsModel(host1, modelId2), "Host1 supports model2");
    }

    // ============================================================
    // Full Flow Test: Session Creation & Completion
    // ============================================================

    function test_CompleteSessionFlow() public {
        // Step 1: Register host
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        // Step 2: Create session
        vm.prank(user1);
        uint256 sessionId = jobMarketplace.createSessionJob{value: 1 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );
        assertEq(sessionId, 1, "Session ID should be 1");

        // Step 3: Submit proofs (with valid signatures)
        vm.warp(block.timestamp + 1); // Advance time

        bytes32 proofHash1 = bytes32(uint256(123));
        bytes memory sig1 = _generateSignature(host1PrivateKey, host1, proofHash1, 1000);
        vm.prank(host1);
        jobMarketplace.submitProofOfWork(sessionId, 1000, proofHash1, sig1, "QmProof1", "");

        vm.warp(block.timestamp + 2);

        bytes32 proofHash2 = bytes32(uint256(456));
        bytes memory sig2 = _generateSignature(host1PrivateKey, host1, proofHash2, 500);
        vm.prank(host1);
        jobMarketplace.submitProofOfWork(sessionId, 500, proofHash2, sig2, "QmProof2", "");

        // Step 4: Complete session
        vm.prank(user1);
        jobMarketplace.completeSessionJob(sessionId, "QmConversationCID");

        // Step 5: Verify host earnings credited
        uint256 hostBalance = hostEarnings.getBalance(host1, address(0));
        assertTrue(hostBalance > 0, "Host should have earnings");

        // Step 6: Withdraw earnings
        uint256 host1BalanceBefore = host1.balance;

        vm.prank(host1);
        hostEarnings.withdraw(hostBalance, address(0));

        assertEq(host1.balance, host1BalanceBefore + hostBalance, "Host should receive earnings");
    }

    // ============================================================
    // Full Flow Test: Multiple Sessions
    // ============================================================

    function test_MultipleSessionsMultipleHosts() public {
        // Register both hosts
        bytes32[] memory models1 = new bytes32[](1);
        models1[0] = modelId1;

        bytes32[] memory models2 = new bytes32[](2);
        models2[0] = modelId1;
        models2[1] = modelId2;

        vm.prank(host1);
        nodeRegistry.registerNode('{"hardware": "GPU1"}', "https://host1.com", models1, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        vm.prank(host2);
        nodeRegistry.registerNode('{"hardware": "GPU2"}', "https://host2.com", models2, MIN_PRICE_NATIVE * 2, MIN_PRICE_STABLE * 2);

        // User1 creates session with host1
        vm.prank(user1);
        uint256 session1 = jobMarketplace.createSessionJob{value: 0.5 ether}(host1, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        // User2 creates session with host2
        vm.prank(user2);
        uint256 session2 = jobMarketplace.createSessionJob{value: 0.5 ether}(host2, MIN_PRICE_NATIVE * 2, 1 days, 1000, 300);

        assertEq(session1, 1, "Session 1 ID");
        assertEq(session2, 2, "Session 2 ID");

        // Both hosts submit proofs (with valid signatures)
        vm.warp(block.timestamp + 1);

        bytes32 proof1Hash = bytes32(uint256(1));
        bytes memory proof1Sig = _generateSignature(host1PrivateKey, host1, proof1Hash, 500);
        vm.prank(host1);
        jobMarketplace.submitProofOfWork(session1, 500, proof1Hash, proof1Sig, "QmProof1", "");

        bytes32 proof2Hash = bytes32(uint256(2));
        bytes memory proof2Sig = _generateSignature(host2PrivateKey, host2, proof2Hash, 500);
        vm.prank(host2);
        jobMarketplace.submitProofOfWork(session2, 500, proof2Hash, proof2Sig, "QmProof2", "");

        // Complete both sessions
        vm.prank(user1);
        jobMarketplace.completeSessionJob(session1, "QmConv1");

        vm.prank(user2);
        jobMarketplace.completeSessionJob(session2, "QmConv2");

        // Verify both hosts have earnings
        assertTrue(hostEarnings.getBalance(host1, address(0)) > 0, "Host1 has earnings");
        assertTrue(hostEarnings.getBalance(host2, address(0)) > 0, "Host2 has earnings");
    }

    // ============================================================
    // Full Flow Test: Model-Specific Session
    // ============================================================

    function test_ModelSpecificSessionFlow() public {
        // Register host with model
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode('{"hardware": "GPU"}', "https://host1.com", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        // Create model-specific session
        vm.prank(user1);
        uint256 sessionId = jobMarketplace.createSessionJobForModel{value: 0.5 ether}(
            host1,
            modelId1,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );

        // Verify model is tracked
        assertEq(jobMarketplace.sessionModel(sessionId), modelId1, "Session model should be tracked");

        // Complete flow (with valid signature)
        vm.warp(block.timestamp + 1);
        bytes32 modelProofHash = bytes32(uint256(1));
        bytes memory modelProofSig = _generateSignature(host1PrivateKey, host1, modelProofHash, 500);
        vm.prank(host1);
        jobMarketplace.submitProofOfWork(sessionId, 500, modelProofHash, modelProofSig, "QmProof", "");

        vm.prank(user1);
        jobMarketplace.completeSessionJob(sessionId, "QmConv");

        assertTrue(hostEarnings.getBalance(host1, address(0)) > 0, "Host has earnings");
    }

    // ============================================================
    // Full Flow Test: Treasury Fee Collection
    // ============================================================

    function test_TreasuryFeeCollection() public {
        // Register host
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode('{"hardware": "GPU"}', "https://host1.com", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        // Create and complete session
        vm.prank(user1);
        uint256 sessionId = jobMarketplace.createSessionJob{value: 1 ether}(host1, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        vm.warp(block.timestamp + 1);
        bytes32 treasuryProofHash = bytes32(uint256(1));
        bytes memory treasuryProofSig = _generateSignature(host1PrivateKey, host1, treasuryProofHash, 1000);
        vm.prank(host1);
        jobMarketplace.submitProofOfWork(sessionId, 1000, treasuryProofHash, treasuryProofSig, "QmProof", "");

        vm.prank(user1);
        jobMarketplace.completeSessionJob(sessionId, "QmConv");

        // Verify treasury accumulated fees
        uint256 treasuryFees = jobMarketplace.accumulatedTreasuryNative();
        assertTrue(treasuryFees > 0, "Treasury should have accumulated fees");

        // Withdraw treasury fees
        uint256 treasuryBalanceBefore = treasury.balance;

        vm.prank(treasury);
        jobMarketplace.withdrawTreasuryNative();

        assertEq(treasury.balance, treasuryBalanceBefore + treasuryFees, "Treasury received fees");
        assertEq(jobMarketplace.accumulatedTreasuryNative(), 0, "Treasury accumulator reset");
    }

    // ============================================================
    // Full Flow Test: Emergency Pause
    // ============================================================

    function test_EmergencyPauseFlow() public {
        // Register host
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode('{"hardware": "GPU"}', "https://host1.com", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        // Create session before pause
        vm.prank(user1);
        uint256 sessionId = jobMarketplace.createSessionJob{value: 0.5 ether}(host1, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        // Pause the marketplace
        vm.prank(deployer);
        jobMarketplace.pause();

        // New sessions should be blocked
        vm.prank(user2);
        vm.expectRevert();
        jobMarketplace.createSessionJob{value: 0.5 ether}(host1, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        // But existing sessions can still be completed (critical for user safety)
        vm.prank(user1);
        jobMarketplace.completeSessionJob(sessionId, "QmConv");

        // Unpause
        vm.prank(deployer);
        jobMarketplace.unpause();

        // New sessions work again
        vm.prank(user2);
        uint256 newSession = jobMarketplace.createSessionJob{value: 0.5 ether}(host1, MIN_PRICE_NATIVE, 1 days, 1000, 300);
        assertEq(newSession, 2, "New session created after unpause");
    }

    // ============================================================
    // Full Flow Test: Host Unregistration
    // ============================================================

    function test_HostUnregistrationFlow() public {
        // Register host
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        uint256 host1BalanceBefore = fabToken.balanceOf(host1);

        vm.prank(host1);
        nodeRegistry.registerNode('{"hardware": "GPU"}', "https://host1.com", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        assertTrue(nodeRegistry.isActiveNode(host1), "Host registered");
        assertEq(fabToken.balanceOf(host1), host1BalanceBefore - MIN_STAKE, "Stake taken");

        // Unregister
        vm.prank(host1);
        nodeRegistry.unregisterNode();

        assertFalse(nodeRegistry.isActiveNode(host1), "Host unregistered");
        assertEq(fabToken.balanceOf(host1), host1BalanceBefore, "Stake returned");
    }

    // ============================================================
    // Helper: Generate Valid Host Signature
    // ============================================================

    /**
     * @dev Generate valid ECDSA signature for proof submission
     * @param hostPrivateKey The private key of the host
     * @param hostAddr The host address (must match private key)
     * @param proofHash The proof hash being signed
     * @param tokensClaimed Number of tokens claimed
     */
    function _generateSignature(
        uint256 hostPrivateKey,
        address hostAddr,
        bytes32 proofHash,
        uint256 tokensClaimed
    ) internal pure returns (bytes memory) {
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, hostAddr, tokensClaimed));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }
}
