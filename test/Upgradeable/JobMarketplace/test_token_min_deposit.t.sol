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
 * @title Token Minimum Deposit Update Tests
 * @dev Tests for updateTokenMinDeposit function
 */
contract TokenMinDepositTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public user1 = address(0x3);
    address public treasury;

    bytes32 public modelId1;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;

    event TokenMinDepositUpdated(address indexed token, uint256 oldMinDeposit, uint256 newMinDeposit);

    function setUp() public {
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        vm.startPrank(owner);

        // Deploy ModelRegistry as proxy
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);
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

        // Deploy JobMarketplace as proxy (4 params)
        JobMarketplaceWithModelsUpgradeable impl = new JobMarketplaceWithModelsUpgradeable();
        address proxyAddr = address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxyAddr));

        // Treasury is the deployer (owner) by default
        treasury = marketplace.treasuryAddress();

        // Set mock USDC address and configure it
        marketplace.setUsdcAddress(address(usdcToken));

        // Authorize marketplace in hostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();
    }

    // ============================================================
    // updateTokenMinDeposit Tests
    // ============================================================

    function test_UpdateTokenMinDeposit_Success() public {
        uint256 newMinDeposit = 100000; // 0.10 USDC

        vm.prank(owner);
        marketplace.updateTokenMinDeposit(address(usdcToken), newMinDeposit);

        assertEq(marketplace.tokenMinDeposits(address(usdcToken)), newMinDeposit);
    }

    function test_UpdateTokenMinDeposit_EmitsEvent() public {
        uint256 oldMinDeposit = marketplace.tokenMinDeposits(address(usdcToken));
        uint256 newMinDeposit = 100000; // 0.10 USDC

        vm.expectEmit(true, false, false, true);
        emit TokenMinDepositUpdated(address(usdcToken), oldMinDeposit, newMinDeposit);

        vm.prank(owner);
        marketplace.updateTokenMinDeposit(address(usdcToken), newMinDeposit);
    }

    function test_UpdateTokenMinDeposit_TreasuryCanCall() public {
        uint256 newMinDeposit = 50000; // 0.05 USDC

        vm.prank(treasury);
        marketplace.updateTokenMinDeposit(address(usdcToken), newMinDeposit);

        assertEq(marketplace.tokenMinDeposits(address(usdcToken)), newMinDeposit);
    }

    function test_UpdateTokenMinDeposit_RevertIfNotOwnerOrTreasury() public {
        uint256 newMinDeposit = 100000;

        vm.prank(user1);
        vm.expectRevert("Only treasury or owner");
        marketplace.updateTokenMinDeposit(address(usdcToken), newMinDeposit);
    }

    function test_UpdateTokenMinDeposit_RevertIfTokenNotAccepted() public {
        address randomToken = address(0x999);
        uint256 newMinDeposit = 100000;

        vm.prank(owner);
        vm.expectRevert("Token not accepted");
        marketplace.updateTokenMinDeposit(randomToken, newMinDeposit);
    }

    function test_UpdateTokenMinDeposit_RevertIfZeroDeposit() public {
        vm.prank(owner);
        vm.expectRevert("Invalid minimum deposit");
        marketplace.updateTokenMinDeposit(address(usdcToken), 0);
    }

    function test_UpdateTokenMinDeposit_CanReduceMinDeposit() public {
        uint256 originalMin = marketplace.tokenMinDeposits(address(usdcToken));
        uint256 reducedMin = originalMin / 5; // Reduce by 5x (from 0.50 to 0.10)

        vm.prank(owner);
        marketplace.updateTokenMinDeposit(address(usdcToken), reducedMin);

        assertEq(marketplace.tokenMinDeposits(address(usdcToken)), reducedMin);
        assertLt(reducedMin, originalMin);
    }

    function test_UpdateTokenMinDeposit_CanIncreaseMinDeposit() public {
        uint256 originalMin = marketplace.tokenMinDeposits(address(usdcToken));
        uint256 increasedMin = originalMin * 2;

        vm.prank(owner);
        marketplace.updateTokenMinDeposit(address(usdcToken), increasedMin);

        assertEq(marketplace.tokenMinDeposits(address(usdcToken)), increasedMin);
        assertGt(increasedMin, originalMin);
    }

    function test_InitialMinDeposit_IsFiftyCents() public {
        // Verify the initial USDC_MIN_DEPOSIT is $0.50 (500000 with 6 decimals)
        assertEq(marketplace.USDC_MIN_DEPOSIT(), 500000);
    }
}
