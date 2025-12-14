// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title JobMarketplaceWithModelsUpgradeable Pause Tests
 * @dev Tests emergency pause functionality
 */
contract JobMarketplacePauseTest is Test {
    JobMarketplaceWithModelsUpgradeable public implementation;
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public host1 = address(0x2);
    address public user1 = address(0x3);
    address public treasury = address(0x4);

    bytes32 public modelId1;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

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
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxyAddr));

        // Set treasury
        vm.prank(owner);
        marketplace.setTreasury(treasury);

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

        // Setup user with ETH
        vm.deal(user1, 100 ether);
    }

    // ============================================================
    // Pause Authorization Tests
    // ============================================================

    function test_OwnerCanPause() public {
        vm.prank(owner);
        marketplace.pause();

        assertTrue(marketplace.paused());
    }

    function test_TreasuryCanPause() public {
        vm.prank(treasury);
        marketplace.pause();

        assertTrue(marketplace.paused());
    }

    function test_RandomUserCannotPause() public {
        vm.prank(user1);
        vm.expectRevert("Only treasury or owner");
        marketplace.pause();
    }

    function test_OwnerCanUnpause() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(owner);
        marketplace.unpause();

        assertFalse(marketplace.paused());
    }

    function test_TreasuryCanUnpause() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(treasury);
        marketplace.unpause();

        assertFalse(marketplace.paused());
    }

    function test_RandomUserCannotUnpause() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(user1);
        vm.expectRevert("Only treasury or owner");
        marketplace.unpause();
    }

    // ============================================================
    // Pause Events Tests
    // ============================================================

    function test_PauseEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit JobMarketplaceWithModelsUpgradeable.ContractPaused(owner);
        marketplace.pause();
    }

    function test_UnpauseEmitsEvent() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit JobMarketplaceWithModelsUpgradeable.ContractUnpaused(owner);
        marketplace.unpause();
    }

    // ============================================================
    // Paused Behavior Tests - Session Creation
    // ============================================================

    function test_CreateSessionJobBlockedWhenPaused() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(user1);
        vm.expectRevert();
        marketplace.createSessionJob{value: 0.01 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    function test_CreateSessionJobWorksWhenUnpaused() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(owner);
        marketplace.unpause();

        vm.prank(user1);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        assertEq(sessionId, 1);
    }

    function test_CreateSessionJobForModelBlockedWhenPaused() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(user1);
        vm.expectRevert();
        marketplace.createSessionJobForModel{value: 0.01 ether}(
            host1,
            modelId1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    // ============================================================
    // Paused Behavior Tests - Proof Submission
    // ============================================================

    function test_SubmitProofBlockedWhenPaused() public {
        // Create session first
        vm.prank(user1);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Pause contract
        vm.prank(owner);
        marketplace.pause();

        // Advance time
        vm.warp(block.timestamp + 1);

        // Try to submit proof
        vm.prank(host1);
        vm.expectRevert();
        marketplace.submitProofOfWork(sessionId, 100, bytes32(uint256(123)), "QmProofCID");
    }

    function test_SubmitProofWorksWhenUnpaused() public {
        // Create session first
        vm.prank(user1);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Pause and unpause
        vm.prank(owner);
        marketplace.pause();

        vm.prank(owner);
        marketplace.unpause();

        // Advance time
        vm.warp(block.timestamp + 1);

        // Submit proof should work
        vm.prank(host1);
        marketplace.submitProofOfWork(sessionId, 100, bytes32(uint256(123)), "QmProofCID");

        // Verify tokens used (skip 7 fields: id, depositor, requester, host, paymentToken, deposit, pricePerToken)
        // Total 18 return values (all except ProofSubmission[] array)
        (,,,,,,, uint256 tokensUsed,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, 100);
    }

    // ============================================================
    // Paused Behavior Tests - Deposits
    // ============================================================

    function test_DepositNativeBlockedWhenPaused() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(user1);
        vm.expectRevert();
        marketplace.depositNative{value: 1 ether}();
    }

    function test_DepositNativeWorksWhenUnpaused() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(owner);
        marketplace.unpause();

        vm.prank(user1);
        marketplace.depositNative{value: 1 ether}();

        assertEq(marketplace.getDepositBalance(user1, address(0)), 1 ether);
    }

    // ============================================================
    // Non-Paused Operations Tests
    // ============================================================

    function test_CompleteSessionNotBlockedWhenPaused() public {
        // Create session
        vm.prank(user1);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Pause contract
        vm.prank(owner);
        marketplace.pause();

        // Complete session should still work (doesn't have whenNotPaused)
        // This is intentional - we want users to be able to exit during emergencies
        vm.prank(user1);
        marketplace.completeSessionJob(sessionId, "QmConversationCID");

        // Verify session is completed by checking it no longer reverts on re-complete attempt
        vm.expectRevert("Session not active");
        vm.prank(user1);
        marketplace.completeSessionJob(sessionId, "QmAnotherCID");
    }

    function test_WithdrawNativeNotBlockedWhenPaused() public {
        // Deposit first
        vm.prank(user1);
        marketplace.depositNative{value: 1 ether}();

        // Pause contract
        vm.prank(owner);
        marketplace.pause();

        // Withdraw should still work (users need to exit during emergencies)
        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        marketplace.withdrawNative(0.5 ether);

        assertEq(user1.balance, balanceBefore + 0.5 ether);
    }

    function test_TreasuryWithdrawalNotBlockedWhenPaused() public {
        // Create and complete a session to accumulate treasury fees
        vm.prank(user1);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Submit proof
        vm.warp(block.timestamp + 1);
        vm.prank(host1);
        marketplace.submitProofOfWork(sessionId, 1000, bytes32(uint256(123)), "QmProofCID");

        // Complete session
        vm.prank(user1);
        marketplace.completeSessionJob(sessionId, "QmConversationCID");

        // Pause contract
        vm.prank(owner);
        marketplace.pause();

        // Treasury withdrawal should work
        uint256 treasuryBalance = marketplace.accumulatedTreasuryNative();
        assertTrue(treasuryBalance > 0);

        vm.prank(treasury);
        marketplace.withdrawTreasuryNative();

        assertEq(marketplace.accumulatedTreasuryNative(), 0);
    }

    // ============================================================
    // Edge Cases
    // ============================================================

    function test_CannotPauseWhenAlreadyPaused() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(owner);
        vm.expectRevert();
        marketplace.pause();
    }

    function test_CannotUnpauseWhenNotPaused() public {
        vm.prank(owner);
        vm.expectRevert();
        marketplace.unpause();
    }
}
