// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract SessionStructUpdateTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ProofSystem public proofSystem;
    HostEarnings public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public depositor = address(2);
    address public host = address(3);
    address public model = address(4);

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC Token", "USDC");
        governanceToken = new ERC20Mock("Governance Token", "GOV");

        modelRegistry = new ModelRegistry(address(governanceToken));
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));
        proofSystem = new ProofSystem();
        hostEarnings = new HostEarnings();

        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            FEE_BASIS_POINTS,
            30);

        vm.stopPrank();

        // Set proof system from treasury address
        address treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));
    }

    function test_SessionStructHasDepositorField() public {
        // Create a session using createSessionJob and verify depositor field is set
        vm.deal(depositor, 1 ether);
        vm.startPrank(depositor);

        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,  // Lower price per token
            3600,
            100
        );

        // Now test actual depositor field
        (
            uint256 id,
            address sessionDepositor,
            address requester,
            ,  // host
            ,  // paymentToken
            ,  // deposit
            ,  // pricePerToken
            ,  // tokensUsed
            ,  // maxDuration
            ,  // startTime
            ,  // lastProofTime
            ,  // proofInterval
            ,  // status
            ,  // withdrawnByHost
            ,  // refundedToUser
            ,  // conversationCID
            ,  // lastProofHash
               // lastProofCID
        ) = marketplace.sessionJobs(sessionId);

        assertEq(sessionDepositor, depositor, "Depositor field should be set");
        assertEq(requester, depositor, "Requester field should still be set for compatibility");
        assertEq(id, sessionId, "Session ID should match");

        vm.stopPrank();
    }

    function test_DepositorFieldPersistsAfterUpdate() public {
        // Test that depositor field remains unchanged during session lifecycle
        vm.deal(depositor, 1 ether);
        vm.startPrank(depositor);

        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,  // Lower price per token
            3600,
            100
        );

        // Get initial depositor
        (, address initialDepositor, , , , , , , , , , , , , ,,,) = marketplace.sessionJobs(sessionId);

        // Update deposit via native deposit function (doesn't change session depositor)
        marketplace.depositNative{value: 0.05 ether}();

        vm.stopPrank();

        // Check depositor unchanged after other operations
        (, address afterDepositDepositor, , , , , , , , , , , , , ,,,) = marketplace.sessionJobs(sessionId);
        assertEq(afterDepositDepositor, initialDepositor, "Depositor should not change");

        // Create another session from different address
        address otherUser = address(999);
        vm.deal(otherUser, 1 ether);
        vm.prank(otherUser);
        marketplace.createSessionJob{value: 0.1 ether}(host, 0.0001 ether, 3600, 100);

        // Check original session depositor still unchanged
        (, address finalDepositor, , , , , , , , , , , , , ,,,) = marketplace.sessionJobs(sessionId);
        assertEq(finalDepositor, initialDepositor, "Depositor should persist");
    }
}