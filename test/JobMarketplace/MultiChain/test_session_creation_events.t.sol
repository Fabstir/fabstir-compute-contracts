// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract SessionCreationEventsTest is Test {
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

    // Event definitions
    event SessionJobCreated(uint256 indexed jobId, address indexed requester, address indexed host, uint256 deposit);
    event SessionCreatedByDepositor(
        uint256 indexed sessionId,
        address indexed depositor,
        address indexed host,
        uint256 deposit
    );

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
            FEE_BASIS_POINTS
        );

        vm.stopPrank();

        // Set proof system from treasury
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));

        // USDC is automatically accepted with hardcoded address
    }

    function test_EmitsSessionJobCreatedEvent() public {
        // Setup deposit
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        marketplace.depositNative{value: 0.5 ether}();

        // Expect SessionJobCreated event
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(1, user, host, 0.1 ether);

        // Create session
        marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.1 ether,
            0.0001 ether,
            3600,
            100
        );

        vm.stopPrank();
    }

    function test_EmitsSessionCreatedByDepositorEvent() public {
        // Setup deposit
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        marketplace.depositNative{value: 0.5 ether}();

        // Expect SessionCreatedByDepositor event
        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDepositor(1, user, host, 0.1 ether);

        // Create session
        marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.1 ether,
            0.0001 ether,
            3600,
            100
        );

        vm.stopPrank();
    }

    function test_EmitsBothEventsForBackwardCompatibility() public {
        // Setup deposit
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        marketplace.depositNative{value: 0.5 ether}();

        // Expect both events
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(1, user, host, 0.1 ether);

        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDepositor(1, user, host, 0.1 ether);

        // Create session
        marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.1 ether,
            0.0001 ether,
            3600,
            100
        );

        vm.stopPrank();
    }

    function test_EventsWithTokenDeposit() public {
        // Use the actual USDC address from the contract
        address actualUsdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

        // Setup mock at USDC address
        vm.etch(actualUsdcAddress, address(usdcToken).code);
        ERC20Mock actualUsdc = ERC20Mock(actualUsdcAddress);

        // Setup token deposit
        vm.startPrank(user);
        actualUsdc.mint(user, 1000e6);
        actualUsdc.approve(address(marketplace), 1000e6);
        marketplace.depositToken(actualUsdcAddress, 500e6);

        // Expect both events with token amounts (use 1 USDC which is above 0.8 USDC minimum)
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(1, user, host, 1e6);

        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDepositor(1, user, host, 1e6);

        // Create session with tokens
        marketplace.createSessionFromDeposit(
            host,
            actualUsdcAddress,
            1e6,  // 1 USDC (above minimum)
            1e3,  // 0.001 USDC per token
            3600,
            100
        );

        vm.stopPrank();
    }
}