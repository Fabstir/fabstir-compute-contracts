// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title JobMarketplaceWithModelsUpgradeable V2 (Mock for testing upgrades)
 */
contract JobMarketplaceWithModelsUpgradeableV2 is JobMarketplaceWithModelsUpgradeable {
    string public marketplaceName;

    function initializeV2(string memory _name) external reinitializer(2) {
        marketplaceName = _name;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }

    function getActiveSessionCount(address host) external view returns (uint256) {
        return hostSessions[host].length;
    }
}

/**
 * @title JobMarketplaceWithModelsUpgradeable Upgrade Tests
 */
contract JobMarketplaceUpgradeTest is Test {
    JobMarketplaceWithModelsUpgradeable public implementation;
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public host1 = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);

    bytes32 public modelId1;

    uint256 constant feeBasisPoints = 1000;
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    // Dummy 65-byte signature for Sub-phase 6.1 (length validation only)
    bytes constant DUMMY_SIG = hex"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000101";

    function setUp() public {
        // Deploy mock token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry as proxy
        vm.startPrank(owner);
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add approved model
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId1 = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry as proxy
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // Deploy HostEarnings as proxy
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(new ERC1967Proxy(
            address(hostEarningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));
        vm.stopPrank();

        // Deploy implementation
        implementation = new JobMarketplaceWithModelsUpgradeable();

        // Deploy proxy with initialization
        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                feeBasisPoints,
                disputeWindow
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxyAddr));

        // Authorize marketplace in HostEarnings
        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Setup host
        fabToken.mint(host1, 10000 * 10**18);
        vm.prank(host1);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

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

        // Setup users with ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Create some sessions before upgrade
        vm.prank(user1);
        marketplace.createSessionJob{value: 0.01 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        vm.prank(user2);
        marketplace.createSessionJob{value: 0.02 ether}(
            host1,
            MIN_PRICE_NATIVE * 2,
            2 days,
            1000
        );
    }

    // ============================================================
    // Pre-Upgrade State Verification
    // ============================================================

    function test_PreUpgradeStateIsCorrect() public view {
        // Verify sessions exist
        assertEq(marketplace.nextJobId(), 3);

        // Verify session 1 data
        (
            uint256 id1,
            address depositor1,
            address host1Session,
            ,
            uint256 deposit1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = marketplace.sessionJobs(1);
        assertEq(id1, 1);
        assertEq(depositor1, user1);
        assertEq(host1Session, host1);
        assertEq(deposit1, 0.01 ether);

        // Verify configuration
        assertEq(marketplace.feeBasisPoints(), feeBasisPoints);
        assertEq(marketplace.disputeWindow(), disputeWindow);
        assertEq(marketplace.owner(), owner);
    }

    // ============================================================
    // Upgrade Authorization Tests
    // ============================================================

    function test_OnlyOwnerCanUpgrade() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(user1);
        vm.expectRevert();
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");
    }

    function test_OwnerCanUpgrade() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        JobMarketplaceWithModelsUpgradeableV2 marketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(marketplace)));
        assertEq(marketplaceV2.version(), "v2");
    }

    // ============================================================
    // State Preservation Tests
    // ============================================================

    function test_UpgradePreservesOwner() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        assertEq(marketplace.owner(), owner);
    }

    function test_UpgradePreservesNodeRegistry() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        assertEq(address(marketplace.nodeRegistry()), address(nodeRegistry));
    }

    function test_UpgradePreservesHostEarnings() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        assertEq(address(marketplace.hostEarnings()), address(hostEarnings));
    }

    function test_UpgradePreservesFeeBasisPoints() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        assertEq(marketplace.feeBasisPoints(), feeBasisPoints);
    }

    function test_UpgradePreservesDisputeWindow() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        assertEq(marketplace.disputeWindow(), disputeWindow);
    }

    function test_UpgradePreservesSessionJobs() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        JobMarketplaceWithModelsUpgradeableV2 marketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(marketplace)));

        // Verify session 1
        (
            uint256 id1,
            address depositor1,
            address host1Session,
            ,
            uint256 deposit1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = marketplaceV2.sessionJobs(1);
        assertEq(id1, 1);
        assertEq(depositor1, user1);
        assertEq(host1Session, host1);
        assertEq(deposit1, 0.01 ether);

        // Verify session 2
        (
            uint256 id2,
            address depositor2,
            ,
            ,
            uint256 deposit2,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = marketplaceV2.sessionJobs(2);
        assertEq(id2, 2);
        assertEq(depositor2, user2);
        assertEq(deposit2, 0.02 ether);
    }

    function test_UpgradePreservesNextJobId() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        assertEq(marketplace.nextJobId(), 3);
    }

    function test_UpgradePreservesUserSessions() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        JobMarketplaceWithModelsUpgradeableV2 marketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(marketplace)));

        // Check host sessions preserved
        assertEq(marketplaceV2.getActiveSessionCount(host1), 2);
    }

    // ============================================================
    // Upgrade With Initialization Tests
    // ============================================================

    function test_UpgradeWithV2Initialization() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeableV2.initializeV2, ("Marketplace V2"))
        );

        JobMarketplaceWithModelsUpgradeableV2 marketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(marketplace)));

        // Verify V2 initialization
        assertEq(marketplaceV2.marketplaceName(), "Marketplace V2");
        assertEq(marketplaceV2.version(), "v2");

        // Verify V1 state preserved
        assertEq(marketplaceV2.owner(), owner);
        assertEq(marketplaceV2.nextJobId(), 3);
    }

    function test_V2InitializationCannotBeCalledTwice() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeableV2.initializeV2, ("Marketplace V2"))
        );

        JobMarketplaceWithModelsUpgradeableV2 marketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(marketplace)));

        vm.expectRevert();
        marketplaceV2.initializeV2("Another Name");
    }

    // ============================================================
    // Post-Upgrade Functionality Tests
    // ============================================================

    function test_CanCreateSessionsAfterUpgrade() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        JobMarketplaceWithModelsUpgradeableV2 marketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(marketplace)));

        // Create new session after upgrade
        address newUser = address(0x100);
        vm.deal(newUser, 10 ether);

        vm.prank(newUser);
        uint256 sessionId = marketplaceV2.createSessionJob{value: 0.01 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        assertEq(sessionId, 3);
        assertEq(marketplaceV2.nextJobId(), 4);
        assertEq(marketplaceV2.getActiveSessionCount(host1), 3);
    }

    function test_CanSubmitProofsAfterUpgrade() public {
        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        JobMarketplaceWithModelsUpgradeableV2 marketplaceV2 = JobMarketplaceWithModelsUpgradeableV2(payable(address(marketplace)));

        // Submit proof for existing session
        vm.warp(block.timestamp + 1);

        vm.prank(host1);
        marketplaceV2.submitProofOfWork(1, 100, bytes32(uint256(123)), DUMMY_SIG, "QmProofCID", "");

        // Verify tokens used updated (skip 6 fields: id, depositor, host, paymentToken, deposit, pricePerToken)
        // Total 17 return values (all except ProofSubmission[] array)
        (,,,,,, uint256 tokensUsed,,,,,,,,,, ) = marketplaceV2.sessionJobs(1);
        assertEq(tokensUsed, 100);
    }

    // ============================================================
    // Implementation Slot Verification
    // ============================================================

    function test_ImplementationSlotUpdatedAfterUpgrade() public {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address implBefore = address(uint160(uint256(vm.load(address(marketplace), slot))));
        assertEq(implBefore, address(implementation));

        JobMarketplaceWithModelsUpgradeableV2 implementationV2 = new JobMarketplaceWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(marketplace)).upgradeToAndCall(address(implementationV2), "");

        address implAfter = address(uint160(uint256(vm.load(address(marketplace), slot))));
        assertEq(implAfter, address(implementationV2));
        assertTrue(implAfter != implBefore);
    }
}
