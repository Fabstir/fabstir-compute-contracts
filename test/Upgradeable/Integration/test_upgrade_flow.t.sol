// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Upgradeable contracts
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";

// Non-upgradeable dependencies
import {ModelRegistry} from "../../../src/ModelRegistry.sol";

import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryV2 - Mock upgrade for testing
 */
contract NodeRegistryWithModelsUpgradeableV2 is NodeRegistryWithModelsUpgradeable {
    string public registryVersion;

    function initializeV2(string memory _version) external reinitializer(2) {
        registryVersion = _version;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }
}

/**
 * @title JobMarketplaceV2 - Mock upgrade for testing
 */
contract JobMarketplaceWithModelsUpgradeableV2 is JobMarketplaceWithModelsUpgradeable {
    string public marketplaceVersion;

    function initializeV2(string memory _version) external reinitializer(2) {
        marketplaceVersion = _version;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }
}

/**
 * @title Upgrade Flow Integration Tests
 * @dev Tests upgrading contracts while sessions are active to verify state preservation
 */
contract UpgradeFlowIntegrationTest is Test {
    // Implementations
    HostEarningsUpgradeable public hostEarningsImpl;
    NodeRegistryWithModelsUpgradeable public nodeRegistryImpl;
    JobMarketplaceWithModelsUpgradeable public jobMarketplaceImpl;

    // Proxies
    HostEarningsUpgradeable public hostEarnings;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    JobMarketplaceWithModelsUpgradeable public jobMarketplace;

    ModelRegistry public modelRegistryNonUpgradeable;
    ERC20Mock public fabToken;

    address public deployer = address(0x1);
    address public host1 = address(0x100);
    address public user1 = address(0x200);

    bytes32 public modelId1;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy mock token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry
        modelRegistryNonUpgradeable = new ModelRegistry(address(fabToken));
        modelRegistryNonUpgradeable.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId1 = modelRegistryNonUpgradeable.getModelId("Model1/Repo", "model1.gguf");

        // Deploy HostEarnings
        hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(new ERC1967Proxy(
            address(hostEarningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // Deploy NodeRegistry
        nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (
                address(fabToken),
                address(modelRegistryNonUpgradeable)
            ))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // Deploy JobMarketplace
        jobMarketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address jobMarketplaceProxy = address(new ERC1967Proxy(
            address(jobMarketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
            ))
        ));
        jobMarketplace = JobMarketplaceWithModelsUpgradeable(payable(jobMarketplaceProxy));

        // Configure
        hostEarnings.setAuthorizedCaller(address(jobMarketplace), true);

        vm.stopPrank();

        // Setup accounts
        fabToken.mint(host1, 10000 * 10**18);
        vm.prank(host1);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        vm.deal(user1, 100 ether);
    }

    // ============================================================
    // Test: Upgrade NodeRegistry While Session Active
    // ============================================================

    function test_UpgradeNodeRegistryDuringActiveSession() public {
        // Step 1: Register host
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode('{"hardware": "GPU"}', "https://host1.com", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        // Step 2: Create active session
        vm.prank(user1);
        uint256 sessionId = jobMarketplace.createSessionJob{value: 1 ether}(host1, MIN_PRICE_NATIVE, 1 days, 1000);

        // Step 3: Submit a proof (use explicit large timestamp to avoid rate limit issues)
        vm.warp(100);
        vm.prank(host1);
        jobMarketplace.submitProofOfWork(sessionId, 500, bytes32(uint256(1)), "QmProof1");

        // Step 4: UPGRADE NodeRegistry
        NodeRegistryWithModelsUpgradeableV2 newNodeRegistryImpl = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(deployer);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(
            address(newNodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeableV2.initializeV2, ("NodeRegistry V2"))
        );

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        // Step 5: Verify upgrade
        assertEq(nodeRegistryV2.version(), "v2", "NodeRegistry upgraded to V2");
        assertEq(nodeRegistryV2.registryVersion(), "NodeRegistry V2", "V2 initialized");

        // Step 6: Verify host state preserved
        assertTrue(nodeRegistryV2.isActiveNode(host1), "Host still registered after upgrade");
        assertTrue(nodeRegistryV2.nodeSupportsModel(host1, modelId1), "Host still supports model");

        // Step 7: Session operations still work (advance time for rate limit)
        vm.warp(200);
        vm.prank(host1);
        jobMarketplace.submitProofOfWork(sessionId, 500, bytes32(uint256(2)), "QmProof2");

        // Step 8: Complete session after upgrade
        vm.prank(user1);
        jobMarketplace.completeSessionJob(sessionId, "QmConversation");

        // Verify earnings
        assertTrue(hostEarnings.getBalance(host1, address(0)) > 0, "Host has earnings after upgrade");
    }

    // ============================================================
    // Test: Upgrade JobMarketplace While Session Active
    // ============================================================

    function test_UpgradeJobMarketplaceDuringActiveSession() public {
        // Step 1: Register host
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode('{"hardware": "GPU"}', "https://host1.com", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        // Step 2: Create active session
        vm.prank(user1);
        uint256 sessionId = jobMarketplace.createSessionJob{value: 1 ether}(host1, MIN_PRICE_NATIVE, 1 days, 1000);

        // Step 3: Submit a proof (use explicit large timestamp)
        vm.warp(100);
        vm.prank(host1);
        jobMarketplace.submitProofOfWork(sessionId, 500, bytes32(uint256(1)), "QmProof1");

        // Capture state before upgrade
        uint256 nextJobIdBefore = jobMarketplace.nextJobId();

        // Step 4: UPGRADE JobMarketplace
        JobMarketplaceWithModelsUpgradeableV2 newJobMarketplaceImpl = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(deployer);
        UUPSUpgradeable(address(jobMarketplace)).upgradeToAndCall(
            address(newJobMarketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeableV2.initializeV2, ("JobMarketplace V2"))
        );

        JobMarketplaceWithModelsUpgradeableV2 jobMarketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(jobMarketplace)));

        // Step 5: Verify upgrade
        assertEq(jobMarketplaceV2.version(), "v2", "JobMarketplace upgraded to V2");
        assertEq(jobMarketplaceV2.marketplaceVersion(), "JobMarketplace V2", "V2 initialized");

        // Step 6: Verify state preserved
        assertEq(jobMarketplaceV2.nextJobId(), nextJobIdBefore, "nextJobId preserved");
        assertEq(address(jobMarketplaceV2.nodeRegistry()), address(nodeRegistry), "NodeRegistry reference preserved");
        assertEq(address(jobMarketplaceV2.hostEarnings()), address(hostEarnings), "HostEarnings reference preserved");
        assertEq(jobMarketplaceV2.FEE_BASIS_POINTS(), FEE_BASIS_POINTS, "Fee preserved");
        assertEq(jobMarketplaceV2.DISPUTE_WINDOW(), DISPUTE_WINDOW, "Dispute window preserved");

        // Step 7: Verify session data preserved
        (
            uint256 id,
            address depositor,
            ,
            address sessionHost,
            ,
            uint256 deposit,
            uint256 pricePerToken,
            uint256 tokensUsed,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = jobMarketplaceV2.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID preserved");
        assertEq(depositor, user1, "Depositor preserved");
        assertEq(sessionHost, host1, "Host preserved");
        assertEq(deposit, 1 ether, "Deposit preserved");
        assertEq(pricePerToken, MIN_PRICE_NATIVE, "Price preserved");
        assertEq(tokensUsed, 500, "Tokens used preserved");

        // Step 8: Continue session after upgrade (advance time for rate limit)
        vm.warp(200);
        vm.prank(host1);
        jobMarketplaceV2.submitProofOfWork(sessionId, 500, bytes32(uint256(2)), "QmProof2");

        // Step 9: Complete session
        vm.prank(user1);
        jobMarketplaceV2.completeSessionJob(sessionId, "QmConversation");

        // Verify host got paid
        assertTrue(hostEarnings.getBalance(host1, address(0)) > 0, "Host received earnings");
    }

    // ============================================================
    // Test: Upgrade Both Contracts During Active Session
    // ============================================================

    function test_UpgradeBothContractsDuringActiveSession() public {
        // Setup host and session
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode('{"hardware": "GPU"}', "https://host1.com", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        vm.prank(user1);
        uint256 sessionId = jobMarketplace.createSessionJob{value: 1 ether}(host1, MIN_PRICE_NATIVE, 1 days, 1000);

        // Submit first proof with explicit large timestamp
        vm.warp(100);
        vm.prank(host1);
        jobMarketplace.submitProofOfWork(sessionId, 300, bytes32(uint256(1)), "QmProof1");

        // Upgrade NodeRegistry
        NodeRegistryWithModelsUpgradeableV2 newNodeRegistryImpl = new NodeRegistryWithModelsUpgradeableV2();
        vm.prank(deployer);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(
            address(newNodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeableV2.initializeV2, ("NodeRegistry V2"))
        );

        // Upgrade JobMarketplace
        JobMarketplaceWithModelsUpgradeableV2 newJobMarketplaceImpl = new JobMarketplaceWithModelsUpgradeableV2();
        vm.prank(deployer);
        UUPSUpgradeable(address(jobMarketplace)).upgradeToAndCall(
            address(newJobMarketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeableV2.initializeV2, ("JobMarketplace V2"))
        );

        // Cast to V2
        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));
        JobMarketplaceWithModelsUpgradeableV2 jobMarketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(jobMarketplace)));

        // Verify both upgraded
        assertEq(nodeRegistryV2.version(), "v2", "NodeRegistry V2");
        assertEq(jobMarketplaceV2.version(), "v2", "JobMarketplace V2");

        // Continue session - submit more proofs (advance time for rate limit)
        vm.warp(200);
        vm.prank(host1);
        jobMarketplaceV2.submitProofOfWork(sessionId, 300, bytes32(uint256(2)), "QmProof2");

        // Complete session
        vm.prank(user1);
        jobMarketplaceV2.completeSessionJob(sessionId, "QmConversation");

        // Verify everything worked
        assertTrue(hostEarnings.getBalance(host1, address(0)) > 0, "Host has earnings");

        // Verify host can still withdraw from NodeRegistry
        uint256 hostFabBefore = fabToken.balanceOf(host1);
        vm.prank(host1);
        nodeRegistryV2.unregisterNode();
        assertEq(fabToken.balanceOf(host1), hostFabBefore + 1000 * 10**18, "Stake returned after both upgrades");
    }

    // ============================================================
    // Test: Create New Session After Upgrade
    // ============================================================

    function test_CreateNewSessionAfterUpgrade() public {
        // Setup and upgrade
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode('{"hardware": "GPU"}', "https://host1.com", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        // Upgrade JobMarketplace
        JobMarketplaceWithModelsUpgradeableV2 newJobMarketplaceImpl = new JobMarketplaceWithModelsUpgradeableV2();
        vm.prank(deployer);
        UUPSUpgradeable(address(jobMarketplace)).upgradeToAndCall(
            address(newJobMarketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeableV2.initializeV2, ("V2"))
        );

        JobMarketplaceWithModelsUpgradeableV2 jobMarketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(jobMarketplace)));

        // Create new session on V2
        vm.prank(user1);
        uint256 sessionId = jobMarketplaceV2.createSessionJob{value: 0.5 ether}(host1, MIN_PRICE_NATIVE, 1 days, 1000);

        assertEq(sessionId, 1, "First session on V2");

        // Complete the session
        vm.warp(block.timestamp + 1);
        vm.prank(host1);
        jobMarketplaceV2.submitProofOfWork(sessionId, 500, bytes32(uint256(1)), "QmProof");

        vm.prank(user1);
        jobMarketplaceV2.completeSessionJob(sessionId, "QmConv");

        assertTrue(hostEarnings.getBalance(host1, address(0)) > 0, "Host earned on V2");
    }

    // ============================================================
    // Test: Verify Implementation Slot Changes
    // ============================================================

    function test_ImplementationSlotsUpdatedOnUpgrade() public {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        // Get initial implementations
        address nodeRegistryImplBefore = address(uint160(uint256(vm.load(address(nodeRegistry), slot))));
        address jobMarketplaceImplBefore = address(uint160(uint256(vm.load(address(jobMarketplace), slot))));

        // Upgrade both
        NodeRegistryWithModelsUpgradeableV2 newNodeRegistryImpl = new NodeRegistryWithModelsUpgradeableV2();
        JobMarketplaceWithModelsUpgradeableV2 newJobMarketplaceImpl = new JobMarketplaceWithModelsUpgradeableV2();

        vm.startPrank(deployer);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(newNodeRegistryImpl), "");
        UUPSUpgradeable(address(jobMarketplace)).upgradeToAndCall(address(newJobMarketplaceImpl), "");
        vm.stopPrank();

        // Verify implementations changed
        address nodeRegistryImplAfter = address(uint160(uint256(vm.load(address(nodeRegistry), slot))));
        address jobMarketplaceImplAfter = address(uint160(uint256(vm.load(address(jobMarketplace), slot))));

        assertTrue(nodeRegistryImplAfter != nodeRegistryImplBefore, "NodeRegistry impl changed");
        assertTrue(jobMarketplaceImplAfter != jobMarketplaceImplBefore, "JobMarketplace impl changed");
        assertEq(nodeRegistryImplAfter, address(newNodeRegistryImpl), "NodeRegistry new impl correct");
        assertEq(jobMarketplaceImplAfter, address(newJobMarketplaceImpl), "JobMarketplace new impl correct");
    }
}
