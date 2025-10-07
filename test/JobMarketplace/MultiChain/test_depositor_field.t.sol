// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract DepositorFieldTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ProofSystem public proofSystem;
    HostEarnings public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public eoaDepositor = address(2);
    address public smartAccountDepositor = address(300);
    address public host = address(4);
    address public model = address(5);

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
    }

    function test_DepositorFieldWorksForEOA() public {
        // Test with EOA wallet
        vm.deal(eoaDepositor, 1 ether);
        vm.startPrank(eoaDepositor);

        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,  // Lower price per token
            3600,
            100
        );

        // Test actual depositor field
        (, address depositor, , , , , , , , , , , , , ,) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, eoaDepositor, "EOA depositor should be tracked");

        vm.stopPrank();
    }

    function test_DepositorFieldWorksForSmartAccount() public {
        // Test with simulated smart account
        vm.deal(smartAccountDepositor, 1 ether);
        vm.etch(smartAccountDepositor, hex"60"); // Make it a contract
        vm.startPrank(smartAccountDepositor);

        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,  // Lower price per token
            3600,
            100
        );

        (, address depositor, , , , , , , , , , , , , ,) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, smartAccountDepositor, "Smart Account depositor should be tracked");

        vm.stopPrank();
    }

    function test_BackwardCompatibilityWithRequesterField() public {
        // Verify both depositor and requester fields are set for backward compatibility
        vm.deal(eoaDepositor, 1 ether);
        vm.startPrank(eoaDepositor);

        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,  // Lower price per token
            3600,
            100
        );

        (
            ,
            address depositor,
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
               // conversationCID
        ) = marketplace.sessionJobs(sessionId);

        assertEq(depositor, eoaDepositor, "Depositor should be set");
        assertEq(requester, eoaDepositor, "Requester should also be set for compatibility");
        assertEq(depositor, requester, "Both should have same value initially");

        vm.stopPrank();
    }

    function test_DepositorFieldInSessionEvents() public {
        // Verify depositor is included in events
        vm.deal(eoaDepositor, 1 ether);
        vm.startPrank(eoaDepositor);

        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDepositor(1, eoaDepositor, host, 0.1 ether);

        marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,  // Lower price per token
            3600,
            100
        );

        vm.stopPrank();
    }

    event SessionCreatedByDepositor(
        uint256 indexed sessionId,
        address indexed depositor,
        address indexed host,
        uint256 deposit
    );
}