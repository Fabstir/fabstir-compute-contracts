// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title Safe Transfer Methods Tests
 * @dev Tests for Phase 3: Verifies transfer functionality after SafeERC20 migration
 *      and .call{value:} pattern for native ETH
 */
contract SafeTransferMethodsTest is Test {
    // Contracts
    JobMarketplaceWithModelsUpgradeable public marketplace;
    HostEarningsUpgradeable public hostEarnings;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    ProofSystemUpgradeable public proofSystem;

    // Tokens
    ERC20Mock public usdc;
    ERC20Mock public fab;

    // Addresses
    address public owner = address(0x1);
    address public host = address(0x2);
    address public depositor = address(0x3);
    address public treasury = address(0x4);

    // Model ID
    bytes32 public modelId;

    function setUp() public {
        // Deploy mock tokens
        usdc = new ERC20Mock("USD Coin", "USDC");
        fab = new ERC20Mock("FAB Token", "FAB");

        // =============================================
        // Deploy HostEarnings
        // =============================================
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        vm.prank(owner);
        address hostEarningsProxy = address(new ERC1967Proxy(
            address(hostEarningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // =============================================
        // Deploy ModelRegistry
        // =============================================
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        vm.prank(owner);
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fab)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add a trusted model
        vm.prank(owner);
        modelRegistry.addTrustedModel("test-org/model", "model.bin", keccak256("hash"));
        modelId = modelRegistry.getModelId("test-org/model", "model.bin");

        // =============================================
        // Deploy NodeRegistry
        // =============================================
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        vm.prank(owner);
        address nodeRegistryProxy = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fab), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // =============================================
        // Deploy ProofSystem
        // =============================================
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        vm.prank(owner);
        address proofSystemProxy = address(new ERC1967Proxy(
            address(proofSystemImpl),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        ));
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // =============================================
        // Deploy JobMarketplace
        // =============================================
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
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

        // Configure marketplace
        vm.startPrank(owner);
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdc), 1e6, 1_000_000 * 10**6); // 1 USDC min, 1M max
        vm.stopPrank();

        // Authorize JobMarketplace
        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        // Fund accounts
        vm.deal(depositor, 100 ether);
        vm.deal(host, 10 ether);
        usdc.mint(depositor, 10000 * 1e6);
        fab.mint(host, 5000 * 1e18);
        fab.mint(depositor, 1000 * 1e18);

        // Register host
        vm.startPrank(host);
        fab.approve(address(nodeRegistry), 1000 * 1e18);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("host-metadata", "https://api.host.com", models, 1e9, 100);
        vm.stopPrank();
    }

    // ============================================================
    // Native ETH: withdrawNative() with .call{value:} pattern
    // ============================================================

    function test_WithdrawNative_Success() public {
        // Deposit native ETH
        vm.prank(depositor);
        marketplace.depositNative{value: 5 ether}();

        uint256 balanceBefore = depositor.balance;

        // Withdraw
        vm.prank(depositor);
        marketplace.withdrawNative(3 ether);

        assertEq(depositor.balance, balanceBefore + 3 ether, "Should receive 3 ETH");
        assertEq(marketplace.userDepositsNative(depositor), 2 ether, "Should have 2 ETH remaining");
    }

    function test_WithdrawNative_FullAmount() public {
        vm.prank(depositor);
        marketplace.depositNative{value: 2 ether}();

        uint256 balanceBefore = depositor.balance;

        vm.prank(depositor);
        marketplace.withdrawNative(2 ether);

        assertEq(depositor.balance, balanceBefore + 2 ether, "Should receive all ETH");
        assertEq(marketplace.userDepositsNative(depositor), 0, "Should have 0 remaining");
    }

    function test_WithdrawNative_ToContractWithReceive() public {
        // Deploy a contract that can receive ETH
        ETHReceiver receiver = new ETHReceiver();

        // Fund the receiver so it can deposit
        vm.deal(address(receiver), 10 ether);

        // Deposit from the receiver contract
        vm.prank(address(receiver));
        marketplace.depositNative{value: 1 ether}();

        uint256 balanceBefore = address(receiver).balance;

        // Withdraw to the receiver contract - tests .call{value:} pattern works with contracts
        vm.prank(address(receiver));
        marketplace.withdrawNative(1 ether);

        assertEq(address(receiver).balance, balanceBefore + 1 ether, "Contract should receive ETH");
    }

    // ============================================================
    // ERC20: JobMarketplace token operations
    // ============================================================

    function test_DepositToken_StillWorks() public {
        vm.startPrank(depositor);
        usdc.approve(address(marketplace), 1000 * 1e6);
        marketplace.depositToken(address(usdc), 500 * 1e6);
        vm.stopPrank();

        assertEq(marketplace.userDepositsToken(depositor, address(usdc)), 500 * 1e6, "Deposit should be recorded");
    }

    function test_WithdrawToken_StillWorks() public {
        // Deposit first
        vm.startPrank(depositor);
        usdc.approve(address(marketplace), 1000 * 1e6);
        marketplace.depositToken(address(usdc), 500 * 1e6);

        uint256 balanceBefore = usdc.balanceOf(depositor);

        // Withdraw
        marketplace.withdrawToken(address(usdc), 200 * 1e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(depositor), balanceBefore + 200 * 1e6, "Should receive USDC");
        assertEq(marketplace.userDepositsToken(depositor, address(usdc)), 300 * 1e6, "Should have 300 USDC remaining");
    }

    function test_CreateSessionWithToken_StillWorks() public {
        vm.startPrank(depositor);
        usdc.approve(address(marketplace), 1000 * 1e6);

        uint256 jobId = marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdc),
            500 * 1e6,     // deposit
            100,           // pricePerToken
            1 days,        // maxDuration
            100            // proofInterval
        );
        vm.stopPrank();

        assertGt(jobId, 0, "Session should be created");
    }

    // ============================================================
    // ERC20: HostEarnings token operations
    // ============================================================

    function test_HostEarnings_WithdrawToken_StillWorks() public {
        // Credit some earnings
        vm.prank(address(marketplace));
        hostEarnings.creditEarnings(host, 100 * 1e6, address(usdc));

        // Fund HostEarnings with USDC
        usdc.mint(address(hostEarnings), 100 * 1e6);

        uint256 balanceBefore = usdc.balanceOf(host);

        // Host withdraws
        vm.prank(host);
        hostEarnings.withdraw(50 * 1e6, address(usdc));

        assertEq(usdc.balanceOf(host), balanceBefore + 50 * 1e6, "Host should receive USDC");
    }

    function test_HostEarnings_RescueTokens_StillWorks() public {
        // Send excess tokens directly to contract (simulating accidental send)
        usdc.mint(address(hostEarnings), 1000 * 1e6);

        uint256 ownerBalanceBefore = usdc.balanceOf(owner);

        // Owner rescues excess tokens
        vm.prank(owner);
        hostEarnings.rescueTokens(address(usdc), 500 * 1e6);

        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + 500 * 1e6, "Owner should receive rescued USDC");
    }

    // ============================================================
    // ERC20: NodeRegistry stake operations
    // ============================================================

    function test_NodeRegistry_Stake_StillWorks() public {
        uint256 additionalStake = 500 * 1e18;

        vm.startPrank(host);
        fab.approve(address(nodeRegistry), additionalStake);
        nodeRegistry.stake(additionalStake);
        vm.stopPrank();

        (,uint256 stakedAmount,,,,,,) = nodeRegistry.getNodeFullInfo(host);
        assertEq(stakedAmount, 1000 * 1e18 + additionalStake, "Stake should increase");
    }

    function test_NodeRegistry_Unregister_ReturnsStake() public {
        uint256 balanceBefore = fab.balanceOf(host);
        (,uint256 stakedAmount,,,,,,) = nodeRegistry.getNodeFullInfo(host);

        vm.prank(host);
        nodeRegistry.unregisterNode();

        assertEq(fab.balanceOf(host), balanceBefore + stakedAmount, "Should receive stake back");
    }

    // ============================================================
    // ERC20: ModelRegistry governance operations
    // ============================================================

    function test_ModelRegistry_ProposeModel_StillWorks() public {
        vm.startPrank(depositor);
        fab.approve(address(modelRegistry), 100 * 1e18);
        modelRegistry.proposeModel("new-org/new-model", "new-model.bin", keccak256("new-hash"));
        vm.stopPrank();

        bytes32 newModelId = modelRegistry.getModelId("new-org/new-model", "new-model.bin");
        (,,,, uint256 proposalTime,,) = modelRegistry.proposals(newModelId);
        assertGt(proposalTime, 0, "Proposal should be created");
    }

    function test_ModelRegistry_VoteOnProposal_StillWorks() public {
        // Create a proposal first
        vm.startPrank(depositor);
        fab.approve(address(modelRegistry), 200 * 1e18);
        modelRegistry.proposeModel("vote-org/vote-model", "vote-model.bin", keccak256("vote-hash"));

        bytes32 voteModelId = modelRegistry.getModelId("vote-org/vote-model", "vote-model.bin");

        // Vote for the model (support = true)
        modelRegistry.voteOnProposal(voteModelId, 50 * 1e18, true);
        vm.stopPrank();

        assertEq(modelRegistry.votes(voteModelId, depositor), 50 * 1e18, "Vote should be recorded");
    }

    function test_ModelRegistry_WithdrawVotes_StillWorks() public {
        // Create and vote
        vm.startPrank(depositor);
        fab.approve(address(modelRegistry), 200 * 1e18);
        modelRegistry.proposeModel("withdraw-org/withdraw-model", "withdraw-model.bin", keccak256("withdraw-hash"));
        bytes32 withdrawModelId = modelRegistry.getModelId("withdraw-org/withdraw-model", "withdraw-model.bin");
        modelRegistry.voteOnProposal(withdrawModelId, 50 * 1e18, true);
        vm.stopPrank();

        // Fast forward past voting period
        vm.warp(block.timestamp + 4 days);

        // Execute proposal (will fail threshold but that's ok, just need voting to end)
        modelRegistry.executeProposal(withdrawModelId);

        // Withdraw votes
        uint256 balanceBefore = fab.balanceOf(depositor);
        vm.prank(depositor);
        modelRegistry.withdrawVotes(withdrawModelId);

        assertEq(fab.balanceOf(depositor), balanceBefore + 50 * 1e18, "Should receive votes back");
    }
}


/**
 * @dev Helper contract that can receive ETH
 */
contract ETHReceiver {
    receive() external payable {}
}
