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
 * @title Direct Payment Delegation Tests (F202614916)
 * @notice Tests for createSessionForModelAsDelegate
 * @dev V2 Pattern: Delegate pulls USDC from payer via transferFrom
 */
contract DirectPaymentDelegationTest is Test {
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
    address public treasury = address(0x5);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant SESSION_AMOUNT = 10_000_000; // 10 USDC

    event SessionJobCreated(uint256 indexed jobId, address indexed depositor, address indexed host, uint256 deposit);
    event SessionJobCreatedForModel(
        uint256 indexed jobId, address indexed depositor, address indexed host, bytes32 modelId, uint256 deposit
    );
    event SessionCreatedByDelegate(
        uint256 indexed sessionId,
        address indexed payer,
        address indexed delegate,
        address host,
        bytes32 modelId,
        uint256 amount
    );

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

        _registerHost(host);

        // Setup payer with USDC and approvals
        usdcToken.mint(payer, 100_000_000_000); // 100k USDC
        vm.prank(payer);
        usdcToken.approve(address(marketplace), type(uint256).max);

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
    // createSessionForModelAsDelegate Tests
    // ============================================================

    function test_CreateSessionForModelAsDelegate_Success() public {
        uint256 payerBalanceBefore = usdcToken.balanceOf(payer);

        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        assertTrue(sessionId > 0);
        assertEq(usdcToken.balanceOf(payer), payerBalanceBefore - SESSION_AMOUNT);

        (, address depositor,,,,,,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, payer, "Session should be owned by payer");
        assertEq(marketplace.sessionModel(sessionId), modelId);
    }

    function test_CreateSessionForModelAsDelegate_EmitsEvents() public {
        vm.prank(delegate);
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(1, payer, host, SESSION_AMOUNT);
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_UnauthorizedDelegate_Reverts() public {
        address unauthorizedDelegate = makeAddr("unauthorized");
        vm.prank(unauthorizedDelegate);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_RevokedDelegate_Reverts() public {
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate, false);

        vm.prank(delegate);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_ETH_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Direct delegation requires ERC-20 token");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(0), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_InsufficientAllowance_Reverts() public {
        vm.prank(payer);
        usdcToken.approve(address(marketplace), SESSION_AMOUNT - 1);

        vm.prank(delegate);
        vm.expectRevert();
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_InsufficientBalance_Reverts() public {
        address poorPayer = makeAddr("poorPayer");
        usdcToken.mint(poorPayer, SESSION_AMOUNT - 1);
        vm.prank(poorPayer);
        usdcToken.approve(address(marketplace), type(uint256).max);
        vm.prank(poorPayer);
        marketplace.authorizeDelegate(delegate, true);

        vm.prank(delegate);
        vm.expectRevert();
        marketplace.createSessionForModelAsDelegate(
            poorPayer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_ZeroPayer_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Invalid payer");
        marketplace.createSessionForModelAsDelegate(
            address(0), modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_InvalidModel_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Invalid model ID");
        marketplace.createSessionForModelAsDelegate(
            payer, bytes32(0), host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_PayerCanAlsoCreateDirectly() public {
        vm.prank(payer);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        (, address depositor,,,,,,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, payer);
    }

    // ============================================================
    // Multiple Delegated Sessions
    // ============================================================

    function test_MultipleSessionsFromSamePayer() public {
        uint256 payerBalanceBefore = usdcToken.balanceOf(payer);

        vm.startPrank(delegate);
        uint256 s1 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        uint256 s2 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT * 2, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        vm.stopPrank();

        (, address depositor1,,,,,,,,,,,,,,,, ) = marketplace.sessionJobs(s1);
        (, address depositor2,,,,,,,,,,,,,,,, ) = marketplace.sessionJobs(s2);
        assertEq(depositor1, payer);
        assertEq(depositor2, payer);
        assertEq(usdcToken.balanceOf(payer), payerBalanceBefore - SESSION_AMOUNT - SESSION_AMOUNT * 2);
    }

    function test_MultipleDelegatesForSamePayer() public {
        address delegate2 = makeAddr("delegate2");
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate2, true);

        vm.prank(delegate);
        uint256 s1 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        vm.prank(delegate2);
        uint256 s2 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        (, address depositor1,,,,,,,,,,,,,,,, ) = marketplace.sessionJobs(s1);
        (, address depositor2,,,,,,,,,,,,,,,, ) = marketplace.sessionJobs(s2);
        assertEq(depositor1, payer);
        assertEq(depositor2, payer);
    }
}
