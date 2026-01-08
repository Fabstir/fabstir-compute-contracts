// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title Receive Function Restriction Tests
 * @dev Tests for Phase 2: Unrestricted receive() function fixes
 *      - HostEarnings: restrict to authorized callers
 *      - JobMarketplace: remove receive/fallback entirely
 */
contract ReceiveFunctionRestrictionTest is Test {
    // HostEarnings contracts
    HostEarningsUpgradeable public hostEarningsImpl;
    HostEarningsUpgradeable public hostEarnings;

    // JobMarketplace contracts
    JobMarketplaceWithModelsUpgradeable public marketplaceImpl;
    JobMarketplaceWithModelsUpgradeable public marketplace;

    // Supporting contracts
    NodeRegistryWithModelsUpgradeable public nodeRegistryImpl;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistryImpl;
    ModelRegistryUpgradeable public modelRegistry;
    ProofSystemUpgradeable public proofSystemImpl;
    ProofSystemUpgradeable public proofSystem;

    // Tokens
    ERC20Mock public usdc;
    ERC20Mock public fab;

    // Addresses
    address public owner = address(0x1);
    address public authorizedCaller = address(0x4);
    address public unauthorizedUser = address(0x5);
    address public host = address(0x6);
    address public depositor = address(0x7);

    // Model ID for testing
    bytes32 public modelId;

    function setUp() public {
        // Deploy mock tokens
        usdc = new ERC20Mock("USD Coin", "USDC");
        fab = new ERC20Mock("FAB Token", "FAB");

        // =============================================
        // Deploy HostEarnings
        // =============================================
        hostEarningsImpl = new HostEarningsUpgradeable();
        vm.prank(owner);
        address hostEarningsProxy = address(new ERC1967Proxy(
            address(hostEarningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // Authorize a caller for HostEarnings
        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(authorizedCaller, true);

        // Fund HostEarnings with ETH for withdrawals
        vm.deal(address(hostEarnings), 100 ether);

        // =============================================
        // Deploy ModelRegistry
        // =============================================
        modelRegistryImpl = new ModelRegistryUpgradeable();
        vm.prank(owner);
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fab)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add a trusted model using correct signature
        vm.prank(owner);
        modelRegistry.addTrustedModel("test-org/test-model", "model.bin", keccak256("test-hash"));
        modelId = modelRegistry.getModelId("test-org/test-model", "model.bin");

        // =============================================
        // Deploy NodeRegistry
        // =============================================
        nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        vm.prank(owner);
        address nodeRegistryProxy = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fab), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // =============================================
        // Deploy ProofSystem
        // =============================================
        proofSystemImpl = new ProofSystemUpgradeable();
        vm.prank(owner);
        address proofSystemProxy = address(new ERC1967Proxy(
            address(proofSystemImpl),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        ));
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // =============================================
        // Deploy JobMarketplace
        // =============================================
        marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        vm.prank(owner);
        address marketplaceProxy = address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                1000,  // feeBasisPoints (10%)
                30     // disputeWindow
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Configure marketplace proof system
        vm.prank(owner);
        marketplace.setProofSystem(address(proofSystem));

        // Authorize JobMarketplace in HostEarnings
        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Authorize JobMarketplace in ProofSystem
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        // =============================================
        // Setup host with stake
        // =============================================
        fab.mint(host, 2000 * 10**18);
        vm.startPrank(host);
        fab.approve(address(nodeRegistry), 1000 * 10**18);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode(
            "test-host-metadata",
            "https://api.test.com",
            models,
            1e9,           // minPricePerTokenNative (1 gwei)
            100            // minPricePerTokenStable
        );
        vm.stopPrank();

        // Fund accounts
        vm.deal(unauthorizedUser, 10 ether);
        vm.deal(authorizedCaller, 10 ether);
        vm.deal(depositor, 100 ether);
        vm.deal(address(marketplace), 10 ether);
    }

    // ============================================================
    // HostEarnings: receive() restriction tests
    // ============================================================

    function test_HostEarnings_ReceiveFromUnauthorized_Reverts() public {
        // Unauthorized user tries to send ETH directly
        vm.prank(unauthorizedUser);
        (bool success, ) = address(hostEarnings).call{value: 1 ether}("");

        // Should revert with "Unauthorized ETH sender"
        assertFalse(success, "Should reject ETH from unauthorized sender");
    }

    function test_HostEarnings_ReceiveFromAuthorized_Succeeds() public {
        uint256 balanceBefore = address(hostEarnings).balance;

        // Authorized caller sends ETH
        vm.prank(authorizedCaller);
        (bool success, ) = address(hostEarnings).call{value: 1 ether}("");

        assertTrue(success, "Should accept ETH from authorized caller");
        assertEq(address(hostEarnings).balance, balanceBefore + 1 ether, "Balance should increase");
    }

    function test_HostEarnings_ReceiveFromJobMarketplace_Succeeds() public {
        uint256 balanceBefore = address(hostEarnings).balance;

        // JobMarketplace (authorized) sends ETH
        vm.prank(address(marketplace));
        (bool success, ) = address(hostEarnings).call{value: 2 ether}("");

        assertTrue(success, "Should accept ETH from JobMarketplace");
        assertEq(address(hostEarnings).balance, balanceBefore + 2 ether, "Balance should increase");
    }

    function test_HostEarnings_ExistingFundFlow_StillWorks() public {
        // Credit earnings via authorized caller
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host, 1 ether, address(0));

        // Verify balance credited
        assertEq(hostEarnings.getBalance(host, address(0)), 1 ether, "Should have 1 ETH credited");

        // Host withdraws (this tests the full flow still works)
        uint256 hostBalanceBefore = host.balance;
        vm.prank(host);
        hostEarnings.withdraw(1 ether, address(0));

        assertEq(host.balance, hostBalanceBefore + 1 ether, "Host should receive ETH");
    }

    // ============================================================
    // JobMarketplace: receive()/fallback() removal tests
    // ============================================================

    function test_JobMarketplace_DirectETHSend_Reverts() public {
        // Try to send ETH directly (not through payable function)
        vm.prank(unauthorizedUser);
        (bool success, ) = address(marketplace).call{value: 1 ether}("");

        // Should fail because receive() is removed
        assertFalse(success, "Direct ETH send should revert");
    }

    function test_JobMarketplace_FallbackCall_Reverts() public {
        // Try to call non-existent function with ETH (triggers fallback)
        vm.prank(unauthorizedUser);
        (bool success, ) = address(marketplace).call{value: 1 ether}(
            abi.encodeWithSignature("nonExistentFunction()")
        );

        // Should fail because fallback() is removed
        assertFalse(success, "Fallback call should revert");
    }

    function test_JobMarketplace_SessionCreationWithETH_StillWorks() public {
        // Create session via payable function (should still work)
        vm.prank(depositor);
        uint256 jobId = marketplace.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            1e9,           // pricePerToken (1 gwei)
            1 days,        // maxDuration
            100            // proofInterval
        );

        // Verify session created by checking the job ID is valid
        assertGt(jobId, 0, "Job ID should be greater than 0");
    }

    function test_JobMarketplace_DepositNative_StillWorks() public {
        uint256 depositAmount = 5 ether;

        // Deposit via depositNative (payable function)
        vm.prank(depositor);
        marketplace.depositNative{value: depositAmount}();

        // Verify deposit recorded
        assertEq(marketplace.userDepositsNative(depositor), depositAmount, "Deposit should be recorded");
    }

    function test_JobMarketplace_CreateSessionJob_StillWorks() public {
        // Create basic session (no model) with ETH
        vm.prank(depositor);
        uint256 jobId = marketplace.createSessionJob{value: 0.5 ether}(
            host,
            1e9,           // pricePerToken
            1 days,        // maxDuration
            100            // proofInterval
        );

        // Verify session created
        assertGt(jobId, 0, "Job should be created");
    }

    // ============================================================
    // Edge cases
    // ============================================================

    function test_HostEarnings_ZeroValueTransfer_FromUnauthorized_Reverts() public {
        // Even zero-value transfers should be rejected from unauthorized
        vm.prank(unauthorizedUser);
        (bool success, ) = address(hostEarnings).call{value: 0}("");

        assertFalse(success, "Zero-value transfer from unauthorized should revert");
    }

    function test_JobMarketplace_ZeroValueDirectSend_Reverts() public {
        // Zero-value direct send should also fail (no receive)
        vm.prank(unauthorizedUser);
        (bool success, ) = address(marketplace).call{value: 0}("");

        assertFalse(success, "Zero-value direct send should revert");
    }
}
