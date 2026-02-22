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
 * @title Delegation Authorization Tests (F202614916)
 * @notice Tests for delegate authorization infrastructure
 * @dev V2 Delegation for Coinbase Smart Wallet sub-accounts
 */
contract DelegationAuthorizationTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public depositor = address(0x3);
    address public delegate = address(0x4);
    address public treasury = address(0x5);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;

    event DelegateAuthorized(address indexed depositor, address indexed delegate, bool authorized);

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

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

        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(
            new ERC1967Proxy(address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ()))
        );
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(
            new ERC1967Proxy(address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ()))
        );
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

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

        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        vm.deal(depositor, 100 ether);
        usdcToken.mint(depositor, 10_000_000_000);
    }

    function test_AuthorizeDelegate_Success() public {
        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, true);
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));
    }

    function test_RevokeDelegate_Success() public {
        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, true);
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));

        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, false);
        assertFalse(marketplace.isDelegateAuthorized(depositor, delegate));
    }

    function test_AuthorizeDelegate_ZeroAddress_Reverts() public {
        vm.prank(depositor);
        vm.expectRevert("Invalid delegate address");
        marketplace.authorizeDelegate(address(0), true);
    }

    function test_AuthorizeDelegate_Self_Reverts() public {
        vm.prank(depositor);
        vm.expectRevert("Cannot delegate to self");
        marketplace.authorizeDelegate(depositor, true);
    }

    function test_AuthorizeDelegate_EmitsEvent() public {
        vm.prank(depositor);
        vm.expectEmit(true, true, false, true);
        emit DelegateAuthorized(depositor, delegate, true);
        marketplace.authorizeDelegate(delegate, true);
    }

    function test_RevokeDelegate_EmitsEvent() public {
        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, true);

        vm.prank(depositor);
        vm.expectEmit(true, true, false, true);
        emit DelegateAuthorized(depositor, delegate, false);
        marketplace.authorizeDelegate(delegate, false);
    }

    function test_MultipleDelegatorsIndependentDelegates() public {
        address depositor2 = makeAddr("depositor2");
        address delegate2 = makeAddr("delegate2");

        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, true);

        vm.prank(depositor2);
        marketplace.authorizeDelegate(delegate2, true);

        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));
        assertTrue(marketplace.isDelegateAuthorized(depositor2, delegate2));
        assertFalse(marketplace.isDelegateAuthorized(depositor, delegate2));
        assertFalse(marketplace.isDelegateAuthorized(depositor2, delegate));
    }

    function test_SameDepositorMultipleDelegates() public {
        address delegate2 = makeAddr("delegate2");
        address delegate3 = makeAddr("delegate3");

        vm.startPrank(depositor);
        marketplace.authorizeDelegate(delegate, true);
        marketplace.authorizeDelegate(delegate2, true);
        marketplace.authorizeDelegate(delegate3, true);
        vm.stopPrank();

        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate2));
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate3));
    }

    function test_SameDelegateMultipleDepositors() public {
        address depositor2 = makeAddr("depositor2");
        address depositor3 = makeAddr("depositor3");

        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, true);
        vm.prank(depositor2);
        marketplace.authorizeDelegate(delegate, true);
        vm.prank(depositor3);
        marketplace.authorizeDelegate(delegate, true);

        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));
        assertTrue(marketplace.isDelegateAuthorized(depositor2, delegate));
        assertTrue(marketplace.isDelegateAuthorized(depositor3, delegate));
    }

    function test_UnauthorizedDelegateReturnsFalse() public view {
        assertFalse(marketplace.isDelegateAuthorized(depositor, delegate));
    }

    function test_AuthorizeRevokeAuthorize() public {
        vm.startPrank(depositor);
        marketplace.authorizeDelegate(delegate, true);
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));

        marketplace.authorizeDelegate(delegate, false);
        assertFalse(marketplace.isDelegateAuthorized(depositor, delegate));

        marketplace.authorizeDelegate(delegate, true);
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));
        vm.stopPrank();
    }
}
