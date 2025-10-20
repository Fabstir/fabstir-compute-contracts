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

contract CreateFromDepositTest is Test {
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

    function test_CreateSessionFromNativeDeposit() public {
        // First deposit native tokens
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        marketplace.depositNative{value: 0.5 ether}();

        // Create session from deposited funds
        uint256 sessionId = marketplace.createSessionFromDeposit(
            host,
            address(0), // Native token
            0.1 ether,
            0.0001 ether,
            3600,
            100
        );

        // Verify session created
        assertEq(sessionId, 1, "Session ID should be 1");

        // Check deposit was deducted
        uint256 remainingBalance = marketplace.userDepositsNative(user);
        assertEq(remainingBalance, 0.4 ether, "Should have 0.4 ether left");

        vm.stopPrank();
    }

    function test_CreateSessionFromTokenDeposit() public {
        // Use the actual USDC address from the contract
        address actualUsdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

        // First deposit USDC tokens - use a mock at the actual USDC address
        vm.etch(actualUsdcAddress, address(usdcToken).code);
        ERC20Mock actualUsdc = ERC20Mock(actualUsdcAddress);

        vm.startPrank(user);
        actualUsdc.mint(user, 1000e6); // 1000 USDC
        actualUsdc.approve(address(marketplace), 1000e6);
        marketplace.depositToken(actualUsdcAddress, 500e6);

        // Create session from deposited tokens (use minimum 0.8 USDC)
        uint256 sessionId = marketplace.createSessionFromDeposit(
            host,
            actualUsdcAddress,
            1e6, // 1 USDC (above 0.8 USDC minimum)
            1e3, // 0.001 USDC per token
            3600,
            100
        );

        // Verify session created
        assertEq(sessionId, 1, "Session ID should be 1");

        // Check deposit was deducted
        uint256 remainingBalance = marketplace.userDepositsToken(user, actualUsdcAddress);
        assertEq(remainingBalance, 499e6, "Should have 499 USDC left");

        vm.stopPrank();
    }

    function test_CreateSessionSetsDepositorField() public {
        // Deposit and create session
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        marketplace.depositNative{value: 0.5 ether}();

        uint256 sessionId = marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.1 ether,
            0.0001 ether,
            3600,
            100
        );

        // Check depositor field is set
        (, address depositor, address requester, , , , , , , , , , , , ,,,) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, user, "Depositor should be user");
        assertEq(requester, user, "Requester should also be user for compatibility");

        vm.stopPrank();
    }
}