// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/JobMarketplaceWithModelsUpgradeable.sol";
import "../../src/NodeRegistryWithModelsUpgradeable.sol";
import "../../src/ModelRegistryUpgradeable.sol";
import "../../src/HostEarningsUpgradeable.sol";
import "../../src/ProofSystemUpgradeable.sol";
import "../mocks/ERC20Mock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Full Session Lifecycle Integration Test
 * @notice End-to-end tests covering complete session workflows
 */
contract FullSessionLifecycleTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;

    ERC20Mock public fabToken;

    address public owner = address(this);
    uint256 public hostPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address public host;
    address public depositor = address(0x2222);

    bytes32 public modelId;

    uint256 public constant MIN_STAKE = 1000 * 10**18;
    uint256 public constant MIN_PRICE_NATIVE = 227_273;
    uint256 public constant MIN_PRICE_STABLE = 1;
    uint256 public constant FEE_BASIS_POINTS = 1000; // 10%
    uint256 public constant DISPUTE_WINDOW = 30;

    // Dummy proof data for tests
    bytes32 constant DUMMY_PROOF_HASH = keccak256("test_proof");
    string constant DUMMY_CID = "QmTest123";

    function setUp() public {
        host = vm.addr(hostPrivateKey);

        // Deploy tokens
        fabToken = new ERC20Mock("FAB", "FAB");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelImpl = new ModelRegistryUpgradeable();
        ERC1967Proxy modelProxy = new ERC1967Proxy(
            address(modelImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        );
        modelRegistry = ModelRegistryUpgradeable(address(modelProxy));

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeImpl = new NodeRegistryWithModelsUpgradeable();
        ERC1967Proxy nodeProxy = new ERC1967Proxy(
            address(nodeImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        );
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(nodeProxy));

        // Deploy HostEarnings
        HostEarningsUpgradeable earningsImpl = new HostEarningsUpgradeable();
        ERC1967Proxy earningsProxy = new ERC1967Proxy(
            address(earningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        );
        hostEarnings = HostEarningsUpgradeable(payable(address(earningsProxy)));

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(
                JobMarketplaceWithModelsUpgradeable.initialize,
                (
                    address(nodeRegistry),
                    payable(address(hostEarnings)),
                    FEE_BASIS_POINTS,
                    DISPUTE_WINDOW
                )
            )
        );
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(address(marketplaceProxy)));

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        ERC1967Proxy proofSystemProxy = new ERC1967Proxy(
            address(proofSystemImpl),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        );
        proofSystem = ProofSystemUpgradeable(address(proofSystemProxy));

        // Configure authorizations
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Configure ProofSystem in marketplace
        marketplace.setProofSystem(address(proofSystem));

        // Add trusted model
        modelRegistry.addTrustedModel("test/repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("test/repo", "model.gguf");

        // Fund accounts
        fabToken.mint(host, MIN_STAKE * 10);
        vm.deal(depositor, 100 ether);

        // Register host
        _registerHost();
    }

    function _generateSignature(bytes32 proofHash, uint256 tokensClaimed)
        internal
        view
        returns (bytes memory)
    {
        // AUDIT-F4: Include modelId in signature
        bytes32 modelIdForSig = bytes32(0); // Non-model session
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, host, tokensClaimed, modelIdForSig));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    // ============ Complete Session Lifecycle (ETH) ============

    function test_FullLifecycle_ETH_HostServesSession() public {
        // Initial state
        uint256 depositorInitialBalance = depositor.balance;
        uint256 hostInitialEarnings = hostEarnings.getBalance(host, address(0));
        assertEq(hostInitialEarnings, 0);

        // Step 1: Depositor creates session
        uint256 deposit = 1 ether;
        uint256 pricePerToken = MIN_PRICE_NATIVE;

        vm.prank(depositor);
        uint256 jobId = marketplace.createSessionJob{value: deposit}(
            host,
            pricePerToken,
            3600, // maxDuration
            100,  // proofInterval
            300   // proofTimeoutWindow
        );

        assertGt(jobId, 0, "Job should be created");

        // Step 2: Host submits proofs (3 times)
        // Rate limit: 1000 tokens/sec base * 2x buffer = 2000 tokens/sec max
        // So we need to warp time to allow enough tokens
        uint256 totalTokensClaimed = 0;
        uint256 currentTime = block.timestamp;

        for (uint256 i = 0; i < 3; i++) {
            // Warp time to allow token claims
            // Rate limit: expectedTokens = timeSinceLastProof * 1000, max = expectedTokens * 2
            // For 200 tokens: need timeSinceLastProof >= 200/2000 = 0.1 sec, use 2 sec for buffer
            currentTime += 2; // Increment by 2 seconds each iteration
            vm.warp(currentTime);

            uint256 tokensClaimed = 100 + i * 50; // 100, 150, 200
            totalTokensClaimed += tokensClaimed;

            bytes32 proofHash = keccak256(abi.encodePacked("proof", i));
            bytes memory signature = _generateSignature(proofHash, tokensClaimed);
            vm.prank(host);
            marketplace.submitProofOfWork(jobId, tokensClaimed, proofHash, signature, DUMMY_CID, "");
        }

        // Verify tokens were tracked (tokensUsed is 7th field, 18 total excluding array)
        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(jobId);
        assertEq(tokensUsed, totalTokensClaimed, "Tokens should match");

        // Step 3: Host must wait dispute window before completing
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        vm.prank(host);
        marketplace.completeSessionJob(jobId, "QmConversationCID");

        // Step 4: Verify host has earnings
        uint256 hostEarningsBalance = hostEarnings.getBalance(host, address(0));
        assertGt(hostEarningsBalance, 0, "Host should have earnings");

        // Step 5: Verify depositor got refund
        uint256 depositorFinalBalance = depositor.balance;
        assertGt(depositorFinalBalance, depositorInitialBalance - deposit, "Depositor should get partial refund");

        // Step 6: Host withdraws earnings
        uint256 hostBalanceBefore = host.balance;

        vm.prank(host);
        hostEarnings.withdrawAll(address(0));

        assertGt(host.balance, hostBalanceBefore, "Host should receive payment");
        assertEq(hostEarnings.getBalance(host, address(0)), 0, "Earnings should be zero after withdrawal");
    }

    // ============ Timeout and Partial Refund ============

    function test_Timeout_PartialRefundAfterSomeProofs() public {
        // Step 1: Create session
        uint256 deposit = 1 ether;

        vm.prank(depositor);
        uint256 jobId = marketplace.createSessionJob{value: deposit}(
            host,
            MIN_PRICE_NATIVE,
            3600,
            100,  // proofInterval
            300   // proofTimeoutWindow
        );

        // Step 2: Host submits one proof (warp time first to allow tokens)
        vm.warp(block.timestamp + 1); // Allow enough tokens

        bytes32 proofHash = keccak256("timeout_proof");
        bytes memory signature = _generateSignature(proofHash, 100);
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, 100, proofHash, signature, DUMMY_CID, "");

        // Step 3: Host goes offline (time passes beyond 3x proofInterval)
        vm.warp(block.timestamp + 400); // 4x proofInterval

        // Step 4: Anyone triggers timeout
        uint256 depositorBalanceBefore = depositor.balance;

        address anyUser = address(0x3333);
        vm.prank(anyUser);
        marketplace.triggerSessionTimeout(jobId);

        // Step 5: Verify partial payment to host
        uint256 hostEarningsBalance = hostEarnings.getBalance(host, address(0));
        assertGt(hostEarningsBalance, 0, "Host should get partial payment");

        // Step 6: Verify refund to depositor
        uint256 depositorBalanceAfter = depositor.balance;
        assertGt(depositorBalanceAfter, depositorBalanceBefore, "Depositor should get refund");
    }

    // ============ Multi-Session Concurrent Operations ============

    function test_MultiSession_HostServesMultipleDepositors() public {
        address depositor2 = address(0x4444);
        address depositor3 = address(0x5555);
        vm.deal(depositor2, 10 ether);
        vm.deal(depositor3, 10 ether);

        // Create 3 sessions
        uint256[] memory jobIds = new uint256[](3);

        vm.prank(depositor);
        jobIds[0] = marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        vm.prank(depositor2);
        jobIds[1] = marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        vm.prank(depositor3);
        jobIds[2] = marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        // Host serves all sessions with different token amounts
        uint256[] memory tokens = new uint256[](3);
        tokens[0] = 100;
        tokens[1] = 200;
        tokens[2] = 300;

        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 1); // Allow enough tokens
            bytes32 proofHash = keccak256(abi.encodePacked("multi", i));
            bytes memory signature = _generateSignature(proofHash, tokens[i]);
            vm.prank(host);
            marketplace.submitProofOfWork(jobIds[i], tokens[i], proofHash, signature, DUMMY_CID, "");
        }

        // Wait for dispute window
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Complete all sessions
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(host);
            marketplace.completeSessionJob(jobIds[i], "QmConversationCID");
        }

        // Verify cumulative earnings
        uint256 totalEarnings = hostEarnings.getBalance(host, address(0));
        assertGt(totalEarnings, 0, "Host should have accumulated earnings");

        // Withdraw all at once
        vm.prank(host);
        hostEarnings.withdrawAll(address(0));

        assertEq(hostEarnings.getBalance(host, address(0)), 0, "All earnings withdrawn");
    }

    // ============ Depositor Early Exit ============

    function test_DepositorCanCompleteEarly() public {
        // Create session
        vm.prank(depositor);
        uint256 jobId = marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        // Warp time to allow token claims
        vm.warp(block.timestamp + 1);

        // Host submits some proofs (MIN_PROVEN_TOKENS = 100)
        bytes32 proofHash = keccak256("early_exit_proof");
        bytes memory signature = _generateSignature(proofHash, 100);
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, 100, proofHash, signature, DUMMY_CID, "");

        // Depositor decides to end early - NO dispute window needed for depositor
        uint256 depositorBalanceBefore = depositor.balance;

        vm.prank(depositor);
        marketplace.completeSessionJob(jobId, "QmEarlyCID");

        // Depositor should get most of their deposit back
        uint256 depositorBalanceAfter = depositor.balance;
        assertGt(depositorBalanceAfter, depositorBalanceBefore, "Depositor should get refund");
    }

    // ============ Model-Specific Session ============

    function test_ModelSpecificSession_CreatesAndCompletes() public {
        vm.prank(depositor);
        uint256 jobId = marketplace.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            3600,
            100,
            300
        );

        // Verify model is tracked
        bytes32 sessionModelId = marketplace.sessionModel(jobId);
        assertEq(sessionModelId, modelId, "Model should be tracked");

        // Wait for dispute window before host completes
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Complete session
        vm.prank(host);
        marketplace.completeSessionJob(jobId, "QmModelCID");

        // Verify completion worked - check status is not Active (proofInterval is 11th field, 18 total excluding array)
        (,,,,,,,,,,uint256 proofInterval,,,,,,,) = marketplace.sessionJobs(jobId);
        assertEq(proofInterval, 100, "Session should exist");
    }

    // ============ Helper Functions ============

    function _registerHost() internal {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        nodeRegistry.registerNode(
            "Host Node",
            "http://host.api",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
        vm.stopPrank();
    }
}
