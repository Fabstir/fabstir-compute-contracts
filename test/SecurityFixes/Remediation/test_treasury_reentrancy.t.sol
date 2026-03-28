// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/**
 * @title Treasury Reentrancy Guard Tests
 * @notice Defense-in-depth: Verify treasury withdrawal functions work correctly
 *         with nonReentrant modifier. While CEI pattern already prevents reentrancy,
 *         the modifier provides an additional safety layer.
 */
contract TreasuryReentrancyTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdc;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public depositor = address(0x3);
    address public treasury;

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant TOKEN_PRICE = 1000;
    uint256 constant MIN_PROVEN_TOKENS = 100;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant PROOF_TIMEOUT = 300;

    function setUp() public {
        // Use a regular address for treasury (receives ETH)
        treasury = address(0x4);
        vm.deal(treasury, 0);

        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdc = new ERC20Mock("USD Coin", "USDC");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        )));

        // Deploy HostEarnings
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        hostEarnings = HostEarningsUpgradeable(payable(address(new ERC1967Proxy(
            address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ))));

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        proofSystem = ProofSystemUpgradeable(address(new ERC1967Proxy(
            address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        )));

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize,
                (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW))
        ))));

        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdc), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        _registerHost();
    }

    function _registerHost() internal {
        fabToken.mint(host, MIN_STAKE);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(usdc), MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);
        vm.stopPrank();
    }

    /// @notice Treasury can withdraw token fees after session completion (with nonReentrant)
    function test_TreasuryWithdraw_TokenFees_WithNonReentrant() public {
        // Create session and submit proof
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        usdc.mint(depositor, deposit);
        vm.prank(depositor);
        usdc.approve(address(marketplace), type(uint256).max);
        vm.prank(depositor);
        uint256 sid = marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdc), deposit, TOKEN_PRICE, 1 days, MIN_PROVEN_TOKENS, PROOF_TIMEOUT
        );

        // Host submits proof
        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sid, MIN_PROVEN_TOKENS, keccak256("tr"), "cid", "d");

        // Complete session
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.prank(depositor);
        marketplace.completeSessionJob(sid, "QmConversation");

        // Treasury withdraws token fees
        uint256 treasuryTokenBal = marketplace.accumulatedTreasuryTokens(address(usdc));
        assertGt(treasuryTokenBal, 0, "Treasury should have accumulated token fees");

        vm.prank(treasury);
        marketplace.withdrawTreasuryTokens(address(usdc));

        // Verify treasury received fees
        uint256 treasuryBal = usdc.balanceOf(treasury);
        assertEq(treasuryBal, treasuryTokenBal, "Treasury should receive token fees");

        // Verify accumulated is now zero
        assertEq(marketplace.accumulatedTreasuryTokens(address(usdc)), 0, "Accumulated should be zero");
    }

    /// @notice Treasury can withdraw ETH fees after ETH session completion (with nonReentrant)
    function test_TreasuryWithdraw_NativeFees_WithNonReentrant() public {
        uint256 deposit = 1 ether;

        vm.deal(depositor, deposit);
        vm.prank(depositor);
        uint256 sid = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, PROOF_TIMEOUT
        );

        // Host submits proof
        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sid, MIN_PROVEN_TOKENS, keccak256("eth"), "cid", "d");

        // Complete session
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.prank(depositor);
        marketplace.completeSessionJob(sid, "QmConversation");

        // Treasury withdraws native fees
        uint256 treasuryNative = marketplace.accumulatedTreasuryNative();
        assertGt(treasuryNative, 0, "Treasury should have accumulated ETH fees");

        uint256 treasuryBalBefore = treasury.balance;
        vm.prank(treasury);
        marketplace.withdrawTreasuryNative();

        assertEq(treasury.balance - treasuryBalBefore, treasuryNative, "Treasury should receive ETH fees");
        assertEq(marketplace.accumulatedTreasuryNative(), 0, "Accumulated ETH should be zero");
    }

    /// @notice withdrawAllTreasuryFees works correctly with nonReentrant
    function test_TreasuryWithdraw_AllFees_WithNonReentrant() public {
        // Create and complete a token session to accumulate fees
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        usdc.mint(depositor, deposit);
        vm.prank(depositor);
        usdc.approve(address(marketplace), type(uint256).max);
        vm.prank(depositor);
        uint256 sid = marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdc), deposit, TOKEN_PRICE, 1 days, MIN_PROVEN_TOKENS, PROOF_TIMEOUT
        );

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sid, MIN_PROVEN_TOKENS, keccak256("all"), "cid", "d");

        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.prank(depositor);
        marketplace.completeSessionJob(sid, "QmConversation");

        uint256 expectedTokenFees = marketplace.accumulatedTreasuryTokens(address(usdc));
        assertGt(expectedTokenFees, 0, "Should have token fees");

        // Withdraw all fees at once
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(treasury);
        marketplace.withdrawAllTreasuryFees(tokens);

        assertEq(usdc.balanceOf(treasury), expectedTokenFees, "Treasury received all token fees");
        assertEq(marketplace.accumulatedTreasuryTokens(address(usdc)), 0, "Token fees zeroed");
    }
}
