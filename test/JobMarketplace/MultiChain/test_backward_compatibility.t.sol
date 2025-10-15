// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BackwardCompatibilityTest is Test {
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
    address public actualUsdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

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

        // Setup mock USDC at the actual address
        vm.etch(actualUsdcAddress, address(usdcToken).code);
    }

    function test_CreateSessionJobStillWorks() public {
        // Test that the original createSessionJob still works
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );

        // Verify session created
        assertEq(sessionId, 1, "Session should be created");

        // Verify session details
        (uint256 id, address depositor, address requester, address sessionHost,,,,,,,,,,,,,,) =
            marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID should match");
        assertEq(depositor, user, "Depositor should be user");
        assertEq(requester, user, "Requester should be user");
        assertEq(sessionHost, host, "Host should match");

        vm.stopPrank();
    }

    function test_CreateSessionJobWithTokenStillWorks() public {
        // Test that the original createSessionJobWithToken still works
        ERC20Mock actualUsdc = ERC20Mock(actualUsdcAddress);

        vm.startPrank(user);
        actualUsdc.mint(user, 100e6);
        actualUsdc.approve(address(marketplace), 100e6);

        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            actualUsdcAddress,
            1e6, // 1 USDC
            1e3, // 0.001 USDC per token
            3600,
            100
        );

        // Verify session created
        assertEq(sessionId, 1, "Session should be created");

        // Verify session details
        (uint256 id, address depositor, address requester,, address paymentToken, uint256 deposit,,,,,,,,,,,,) =
            marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID should match");
        assertEq(depositor, user, "Depositor should be user");
        assertEq(requester, user, "Requester should be user");
        assertEq(paymentToken, actualUsdcAddress, "Payment token should be USDC");
        assertEq(deposit, 1e6, "Deposit should be 1 USDC");

        vm.stopPrank();
    }

    function test_BothMethodsEmitCorrectEvents() public {
        // Test native session emits events
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(1, user, host, 0.1 ether);

        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDepositor(1, user, host, 0.1 ether);

        marketplace.createSessionJob{value: 0.1 ether}(host, 0.0001 ether, 3600, 100);

        vm.stopPrank();
    }

    event SessionJobCreated(uint256 indexed jobId, address indexed requester, address indexed host, uint256 deposit);
    event SessionCreatedByDepositor(uint256 indexed sessionId, address indexed depositor, address indexed host, uint256 deposit);
}