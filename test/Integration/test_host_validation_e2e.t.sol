// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title Host Validation End-to-End Integration Tests
 * @dev Tests for Sub-phase 2.3: Integration tests for host validation
 *
 * Tests complete flows including:
 * - Full session lifecycle with registered host
 * - Host deactivation effects on new vs existing sessions
 * - Random address rejection
 */
contract HostValidationE2ETest is Test {
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
    address public randomAddress = address(0x999);

    bytes32 public modelId;

    uint256 constant feeBasisPoints = 1000; // 10%
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    // Dummy 65-byte signature for Sub-phase 6.1 (length validation only)
    bytes constant DUMMY_SIG = hex"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000101";

    function setUp() public {
        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        vm.startPrank(owner);

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add approved model
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // Deploy HostEarnings
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(new ERC1967Proxy(
            address(hostEarningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(new ERC1967Proxy(
            address(proofSystemImpl),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        ));
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                feeBasisPoints,
                disputeWindow
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Authorize marketplace in ProofSystem
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Setup user with ETH
        vm.deal(user, 100 ether);
        vm.deal(host, 10 ether);

        // Setup user with USDC
        usdcToken.mint(user, 1000 * 10**6);
    }

    // ============================================================
    // Helper: Register host in NodeRegistry
    // ============================================================

    function _registerHost(address hostAddr) internal {
        fabToken.mint(hostAddr, 10000 * 10**18);
        vm.prank(hostAddr);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.prank(hostAddr);
        nodeRegistry.registerNode(
            '{"hardware": "GPU", "memory": "16GB"}',
            "https://api.host.example.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
    }

    // ============================================================
    // Test: Full Flow - Register Host, Create Session, Submit Proof, Complete
    // ============================================================

    function test_FullFlowWithRegisteredHost() public {
        // Step 1: Register host
        _registerHost(host);
        assertTrue(nodeRegistry.isActiveNode(host), "Host should be active");

        // Step 2: User creates session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000 // proof interval
        );
        assertEq(sessionId, 1, "Session ID should be 1");

        // Step 3: Verify session is created (check via nextJobId)
        assertEq(marketplace.nextJobId(), 2, "Next job ID should be 2");

        // Step 4: Host submits proof of work
        // Need to wait a bit for rate limiting
        vm.warp(block.timestamp + 1);

        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            1000, // tokens claimed
            bytes32(uint256(0x1234)), // proof hash
            DUMMY_SIG,
            "QmProofCID123",
            ""
        );

        // Step 5: Complete session (wait for dispute window)
        vm.warp(block.timestamp + disputeWindow + 1);

        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversationCID456");

        // Verify host has earnings (session completed successfully)
        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertTrue(hostBalance > 0, "Host should have earnings after session completion");
    }

    // ============================================================
    // Test: Unregistered Host Cannot Receive Sessions
    // ============================================================

    function test_RandomAddressAsHostFails() public {
        // randomAddress is never registered
        assertFalse(nodeRegistry.isActiveNode(randomAddress), "Random address should not be active");

        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJob{value: 1 ether}(
            randomAddress,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    function test_MultipleRandomAddressesFail() public {
        address[] memory fakeHosts = new address[](5);
        fakeHosts[0] = address(0x100);
        fakeHosts[1] = address(0x200);
        fakeHosts[2] = address(0x300);
        fakeHosts[3] = address(0x400);
        fakeHosts[4] = address(0x500);

        for (uint i = 0; i < fakeHosts.length; i++) {
            vm.prank(user);
            vm.expectRevert("Host not registered");
            marketplace.createSessionJob{value: 0.1 ether}(
                fakeHosts[i],
                MIN_PRICE_NATIVE,
                1 days,
                1000
            );
        }
    }

    // ============================================================
    // Test: Deactivated Host Cannot Receive New Sessions
    // ============================================================

    function test_DeactivatedHostCannotReceiveNewSessions() public {
        // Register host first
        _registerHost(host);
        assertTrue(nodeRegistry.isActiveNode(host), "Host should be active initially");

        // Create first session (should succeed)
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJob{value: 0.5 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
        assertEq(sessionId1, 1);

        // Host unregisters (this is the only way to "deactivate" currently)
        vm.prank(host);
        nodeRegistry.unregisterNode();
        assertFalse(nodeRegistry.isActiveNode(host), "Host should be inactive after unregister");

        // Attempt to create new session (should fail)
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJob{value: 0.5 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    function test_DeactivatedHostSimulatedWithMock() public {
        // Register host first
        _registerHost(host);

        // Create first session (should succeed)
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJob{value: 0.5 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
        assertEq(sessionId1, 1);

        // Mock getNodeFullInfo to return inactive host (simulates future deactivation feature)
        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(NodeRegistryWithModelsUpgradeable.getNodeFullInfo.selector, host),
            abi.encode(
                host,           // operator (non-zero = registered)
                MIN_STAKE,      // stakedAmount
                false,          // active = FALSE
                '{}',
                "",
                new bytes32[](0),
                MIN_PRICE_NATIVE,
                MIN_PRICE_STABLE
            )
        );

        // Attempt to create new session (should fail with "Host not active")
        vm.prank(user);
        vm.expectRevert("Host not active");
        marketplace.createSessionJob{value: 0.5 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    // ============================================================
    // Test: Existing Sessions Complete Normally After Host Unregisters
    // ============================================================

    function test_ExistingSessionsCompleteAfterHostUnregisters() public {
        // Register host
        _registerHost(host);

        // Set initial timestamp
        uint256 startTime = 1000;
        vm.warp(startTime);

        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Host submits some proof (wait 1 second, can claim up to 2000 tokens)
        vm.warp(startTime + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            500,
            bytes32(uint256(0xABCD)),
            DUMMY_SIG,
            "QmProof1",
            ""
        );

        // Host unregisters (deactivates)
        vm.prank(host);
        nodeRegistry.unregisterNode();
        assertFalse(nodeRegistry.isActiveNode(host), "Host should be inactive");

        // Host can still submit more proofs for existing session
        // Wait 1 second from last proof (allows up to 2000 tokens)
        vm.warp(startTime + 2);
        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            200, // Reduced to ensure within rate limit
            bytes32(uint256(0xEF01)),
            DUMMY_SIG,
            "QmProof2",
            ""
        );

        // Session can still be completed
        vm.warp(block.timestamp + disputeWindow + 1);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmFinalConversation");

        // Verify completed by checking host has earnings
        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertTrue(hostBalance > 0, "Host should have earnings after session completion");
    }

    function test_ExistingSessionEarningsAccumulateAfterHostUnregisters() public {
        // Register host
        _registerHost(host);

        // Create session with significant deposit
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Host submits proof
        vm.warp(block.timestamp + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            1000,
            bytes32(uint256(0x1111)),
            DUMMY_SIG,
            "QmProof",
            ""
        );

        // Host unregisters
        vm.prank(host);
        nodeRegistry.unregisterNode();

        // Complete session - payments should still work
        vm.warp(block.timestamp + disputeWindow + 1);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConvo");

        // Verify host has earnings in HostEarnings contract
        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertTrue(hostBalance > 0, "Host should have earnings");
    }

    // ============================================================
    // Test: Re-registration After Unregistration
    // ============================================================

    function test_HostCanReregisterAndReceiveNewSessions() public {
        // Register host
        _registerHost(host);

        // Create session
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
        assertEq(sessionId1, 1);

        // Unregister
        vm.prank(host);
        nodeRegistry.unregisterNode();

        // Cannot create new session
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJob{value: 0.1 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Re-register
        _registerHost(host);
        assertTrue(nodeRegistry.isActiveNode(host), "Host should be active again");

        // Can now create new session
        vm.prank(user);
        uint256 sessionId2 = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
        assertEq(sessionId2, 2);
    }

    // ============================================================
    // Test: Multiple Hosts Scenario
    // ============================================================

    function test_MultipleHostsValidation() public {
        address host2 = address(0x22);
        address host3 = address(0x33);

        // Register only host and host2, not host3
        _registerHost(host);
        _registerHost(host2);

        // Sessions with registered hosts succeed
        vm.prank(user);
        uint256 s1 = marketplace.createSessionJob{value: 0.1 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000);
        vm.prank(user);
        uint256 s2 = marketplace.createSessionJob{value: 0.1 ether}(host2, MIN_PRICE_NATIVE, 1 days, 1000);

        assertEq(s1, 1);
        assertEq(s2, 2);

        // Session with unregistered host3 fails
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJob{value: 0.1 ether}(host3, MIN_PRICE_NATIVE, 1 days, 1000);
    }
}
