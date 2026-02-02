// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title Delegation Security Tests
 * @notice Security-focused tests for V2 Direct Payment Delegation
 * @dev Tests for Phase 4: Security Hardening
 *
 * Key Security Properties:
 * 1. Unauthorized addresses cannot pull from any payer
 * 2. Revoked delegates fail after revocation
 * 3. Delegate cannot exceed payer's ERC-20 approval
 * 4. Session refunds go to payer (not delegate)
 * 5. Reentrancy protection is active
 * 6. Pause mechanism blocks delegated functions
 * 7. Payer can still use non-delegated functions
 */
contract DelegationSecurityTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public payer = address(0x3);
    address public delegate = address(0x4);
    address public attacker = address(0x5);
    address public treasury = address(0x6);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant SESSION_AMOUNT = 10_000_000;  // 10 USDC

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(
            new ERC1967Proxy(
                address(modelRegistryImpl),
                abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
            )
        );
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(
            new ERC1967Proxy(
                address(nodeRegistryImpl),
                abi.encodeCall(
                    NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry))
                )
            )
        );
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // Deploy HostEarnings
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(
            new ERC1967Proxy(address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ()))
        );
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(
            new ERC1967Proxy(address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ()))
        );
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(
            new ERC1967Proxy(
                address(marketplaceImpl),
                abi.encodeCall(
                    JobMarketplaceWithModelsUpgradeable.initialize,
                    (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW)
                )
            )
        );
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Configure marketplace
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        // Authorize marketplace in HostEarnings and ProofSystem
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host
        _registerHost(host);

        // Setup payer with USDC and LIMITED approval (not max)
        usdcToken.mint(payer, 100_000_000_000);  // 100k USDC
        vm.prank(payer);
        usdcToken.approve(address(marketplace), 1_000_000_000);  // 1000 USDC approval only

        // Payer authorizes delegate
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate, true);
    }

    function _registerHost(address _host) internal {
        fabToken.mint(_host, MIN_STAKE);

        vm.startPrank(_host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    // ============================================================
    // Security Test 1: Unauthorized Cannot Pull From Payer
    // ============================================================

    function test_UnauthorizedCannotPullFromPayer() public {
        vm.prank(attacker);
        vm.expectRevert(JobMarketplaceWithModelsUpgradeable.NotDelegate.selector);
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_UnauthorizedCannotPullFromAnyPayerNonModel() public {
        vm.prank(attacker);
        vm.expectRevert(JobMarketplaceWithModelsUpgradeable.NotDelegate.selector);
        marketplace.createSessionAsDelegate(
            payer, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    // ============================================================
    // Security Test 2: Revoked Delegate Cannot Create Session
    // ============================================================

    function test_RevokedDelegateCannotCreateSession() public {
        // First verify delegate CAN create session
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        assertTrue(sessionId > 0, "Delegate should be able to create session initially");

        // Payer revokes delegate
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate, false);

        // Now delegate should fail
        vm.prank(delegate);
        vm.expectRevert(JobMarketplaceWithModelsUpgradeable.NotDelegate.selector);
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    // ============================================================
    // Security Test 3: Delegate Cannot Exceed Payer's Approval
    // ============================================================

    function test_DelegateCannotExceedApproval() public {
        // Payer only approved 1000 USDC, try to use more
        uint256 excessiveAmount = 2_000_000_000;  // 2000 USDC (exceeds 1000 approval)

        vm.prank(delegate);
        vm.expectRevert();  // ERC-20 will revert
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            excessiveAmount, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_AllowanceDecreasesWithEachSession() public {
        uint256 allowanceBefore = usdcToken.allowance(payer, address(marketplace));

        vm.prank(delegate);
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        uint256 allowanceAfter = usdcToken.allowance(payer, address(marketplace));
        assertEq(allowanceAfter, allowanceBefore - SESSION_AMOUNT, "Allowance should decrease");
    }

    // ============================================================
    // Security Test 4: Session Refunds Go To Payer (Not Delegate)
    // ============================================================

    function test_SessionRefundsGoToPayer() public {
        uint256 payerBalanceBefore = usdcToken.balanceOf(payer);
        uint256 delegateBalanceBefore = usdcToken.balanceOf(delegate);

        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // Complete session (no tokens used = refund)
        vm.prank(payer);
        marketplace.completeSessionJob(sessionId, "final_cid");

        // Payer should receive refund (minus fees)
        uint256 payerBalanceAfter = usdcToken.balanceOf(payer);
        assertTrue(payerBalanceAfter > payerBalanceBefore - SESSION_AMOUNT, "Payer should receive partial refund");

        // Delegate balance should be unchanged
        assertEq(usdcToken.balanceOf(delegate), delegateBalanceBefore, "Delegate should not receive any funds");
    }

    function test_DelegateCannotCompleteSession() public {
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // Verify session is owned by payer
        (,address depositor,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, payer, "Session must be owned by payer");

        // Delegate CANNOT complete session - only depositor or host can
        vm.prank(delegate);
        vm.expectRevert("Only depositor or host can complete");
        marketplace.completeSessionJob(sessionId, "final_cid");
    }

    // ============================================================
    // Security Test 5: Pause Mechanism Blocks Delegated Functions
    // ============================================================

    function test_PauseMechanismBlocksDelegatedFunctions() public {
        // Owner pauses contract
        vm.prank(owner);
        marketplace.pause();

        // Delegate cannot create session
        vm.prank(delegate);
        vm.expectRevert();  // Pausable: paused
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_PauseMechanismBlocksNonModelDelegation() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(delegate);
        vm.expectRevert();
        marketplace.createSessionAsDelegate(
            payer, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_UnpauseRestoresDelegatedFunctions() public {
        // Pause then unpause
        vm.startPrank(owner);
        marketplace.pause();
        marketplace.unpause();
        vm.stopPrank();

        // Delegate should be able to create session again
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        assertTrue(sessionId > 0, "Delegation should work after unpause");
    }

    // ============================================================
    // Security Test 6: Payer Can Still Use Non-Delegated Functions
    // ============================================================

    function test_PayerCanUseNonDelegatedFunctions() public {
        // Payer can create session directly (without delegation)
        vm.prank(payer);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        assertTrue(sessionId > 0, "Payer should be able to use direct functions");
    }

    function test_PayerCanCreateViaDelegate_AsSelf() public {
        // Payer can use delegate function with themselves as payer
        vm.prank(payer);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer,  // payer == msg.sender
            modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        assertTrue(sessionId > 0, "Payer should be able to call delegate function for self");
    }

    // ============================================================
    // Security Test 7: Cross-User Authorization Isolation
    // ============================================================

    function test_DelegateCannotAccessOtherPayersFunds() public {
        // Create another payer
        address payer2 = makeAddr("payer2");
        usdcToken.mint(payer2, 100_000_000_000);

        vm.prank(payer2);
        usdcToken.approve(address(marketplace), type(uint256).max);

        // payer2 has NOT authorized delegate
        vm.prank(delegate);
        vm.expectRevert(JobMarketplaceWithModelsUpgradeable.NotDelegate.selector);
        marketplace.createSessionForModelAsDelegate(
            payer2, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_AuthorizationIsPerPayer() public {
        address payer2 = makeAddr("payer2");
        address delegate2 = makeAddr("delegate2");

        usdcToken.mint(payer2, 100_000_000_000);
        vm.prank(payer2);
        usdcToken.approve(address(marketplace), type(uint256).max);

        // payer2 authorizes delegate2 (not delegate)
        vm.prank(payer2);
        marketplace.authorizeDelegate(delegate2, true);

        // delegate cannot access payer2
        vm.prank(delegate);
        vm.expectRevert(JobMarketplaceWithModelsUpgradeable.NotDelegate.selector);
        marketplace.createSessionForModelAsDelegate(
            payer2, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // delegate2 cannot access payer (original)
        vm.prank(delegate2);
        vm.expectRevert(JobMarketplaceWithModelsUpgradeable.NotDelegate.selector);
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // delegate2 CAN access payer2
        vm.prank(delegate2);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer2, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        assertTrue(sessionId > 0, "Correct delegate should work");
    }

    // ============================================================
    // Security Test 8: Authorization Check Ordering
    // ============================================================

    function test_AuthorizationCheckIsFirst() public {
        // This test verifies authorization is checked BEFORE any state changes
        // If authorization weren't first, different errors would appear

        // Attacker with invalid host should get NotDelegate not other errors
        vm.prank(attacker);
        vm.expectRevert(JobMarketplaceWithModelsUpgradeable.NotDelegate.selector);
        marketplace.createSessionForModelAsDelegate(
            payer, modelId,
            address(0xdead),  // Invalid host
            address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }
}
