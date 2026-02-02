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
 * @notice Critical security tests for delegated session creation
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
    address public treasury = address(0x4);
    address public victim;
    address public attacker;
    address public depositor;
    address public delegate;

    bytes32 public modelId;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;

    function setUp() public {
        victim = makeAddr("victim");
        attacker = makeAddr("attacker");
        depositor = makeAddr("depositor");
        delegate = makeAddr("delegate");

        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(
            new ERC1967Proxy(address(modelRegistryImpl), abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken))))
        );
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(
            new ERC1967Proxy(address(nodeRegistryImpl), abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), modelRegistryProxy)))
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
            new ERC1967Proxy(address(marketplaceImpl), abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (nodeRegistryProxy, payable(hostEarningsProxy), 1000, 30)))
        );
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        _registerHost(host);
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
    // Critical Security Tests
    // ============================================================

    function test_UnauthorizedCannotDrainDeposits() public {
        // Victim deposits funds
        vm.deal(victim, 10 ether);
        vm.prank(victim);
        marketplace.depositNative{value: 5 ether}();

        // Attacker tries to use victim's deposits without authorization
        vm.prank(attacker);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionFromDepositAsDelegate(
            victim, host, address(0), 1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        // Verify victim's balance unchanged
        assertEq(marketplace.userDepositsNative(victim), 5 ether);
    }

    function test_RevokedDelegateCannotCreateSession() public {
        vm.deal(depositor, 10 ether);
        vm.prank(depositor);
        marketplace.depositNative{value: 5 ether}();

        // Authorize then revoke
        vm.startPrank(depositor);
        marketplace.authorizeDelegate(delegate, true);
        marketplace.authorizeDelegate(delegate, false);
        vm.stopPrank();

        // Delegate tries to create session after revocation
        vm.prank(delegate);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), 1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );
    }

    function test_DelegateCannotAccessOtherUsersDeposits() public {
        // Depositor A sets up deposits and authorizes delegate
        address depositorA = makeAddr("depositorA");
        address depositorB = makeAddr("depositorB");

        vm.deal(depositorA, 10 ether);
        vm.deal(depositorB, 10 ether);

        vm.prank(depositorA);
        marketplace.depositNative{value: 5 ether}();

        vm.prank(depositorB);
        marketplace.depositNative{value: 5 ether}();

        // Depositor A authorizes delegate
        vm.prank(depositorA);
        marketplace.authorizeDelegate(delegate, true);

        // Delegate should NOT be able to access depositor B's funds
        vm.prank(delegate);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionFromDepositAsDelegate(
            depositorB, host, address(0), 1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        // But should be able to access depositor A's funds
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionFromDepositAsDelegate(
            depositorA, host, address(0), 1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );
        assertGt(sessionId, 0);
    }

    function test_PauseMechanismBlocksDelegatedFunctions() public {
        vm.deal(depositor, 10 ether);
        vm.prank(depositor);
        marketplace.depositNative{value: 5 ether}();

        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, true);

        // Owner pauses the contract
        vm.prank(owner);
        marketplace.pause();

        // Delegate tries to create session while paused
        vm.prank(delegate);
        vm.expectRevert();
        marketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), 1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        // Unpause and verify it works again
        vm.prank(owner);
        marketplace.unpause();

        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), 1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );
        assertGt(sessionId, 0);
    }
}
