// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract DepositDeductionTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ProofSystem public proofSystem;
    HostEarnings public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public user = address(2);
    address public host = address(3);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

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

        // Set proof system from treasury
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));

        // USDC is automatically accepted with hardcoded address
    }

    function test_InsufficientNativeDeposit() public {
        // Deposit less than needed
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        marketplace.depositNative{value: 0.05 ether}();

        // Try to create session with more than deposited
        vm.expectRevert("Insufficient native deposit");
        marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.1 ether, // More than deposited
            0.0001 ether,
            3600,
            100
        );

        vm.stopPrank();
    }

    function test_InsufficientTokenDeposit() public {
        // Use the actual USDC address from the contract
        address actualUsdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

        // Setup mock at USDC address
        vm.etch(actualUsdcAddress, address(usdcToken).code);
        ERC20Mock actualUsdc = ERC20Mock(actualUsdcAddress);

        // Deposit less than needed
        vm.startPrank(user);
        actualUsdc.mint(user, 150e6);
        actualUsdc.approve(address(marketplace), 150e6);
        marketplace.depositToken(actualUsdcAddress, 150e6);

        // Try to create session with more than deposited
        vm.expectRevert("Insufficient token deposit");
        marketplace.createSessionFromDeposit(
            host,
            actualUsdcAddress,
            200e6, // More than deposited
            1e6,
            3600,
            100
        );

        vm.stopPrank();
    }

    function test_MultipleSessionsFromSameDeposit() public {
        // Deposit a larger amount
        vm.deal(user, 2 ether);
        vm.startPrank(user);
        marketplace.depositNative{value: 1 ether}();

        // Create first session
        uint256 sessionId1 = marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.3 ether,
            0.0001 ether,
            3600,
            100
        );

        // Check balance after first session
        uint256 balanceAfterFirst = marketplace.userDepositsNative(user);
        assertEq(balanceAfterFirst, 0.7 ether, "Should have 0.7 ether after first session");

        // Create second session
        uint256 sessionId2 = marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.3 ether,
            0.0001 ether,
            3600,
            100
        );

        // Check balance after second session
        uint256 balanceAfterSecond = marketplace.userDepositsNative(user);
        assertEq(balanceAfterSecond, 0.4 ether, "Should have 0.4 ether after second session");

        assertEq(sessionId1, 1, "First session ID should be 1");
        assertEq(sessionId2, 2, "Second session ID should be 2");

        vm.stopPrank();
    }

    function test_ExactDepositAmount() public {
        // Deposit exact amount needed
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        marketplace.depositNative{value: 0.1 ether}();

        // Create session with exact deposited amount
        marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.1 ether,
            0.0001 ether,
            3600,
            100
        );

        // Check balance is now zero
        uint256 remainingBalance = marketplace.userDepositsNative(user);
        assertEq(remainingBalance, 0, "Balance should be zero after using all deposit");

        vm.stopPrank();
    }
}