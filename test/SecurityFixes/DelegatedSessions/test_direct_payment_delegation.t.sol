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
 * @title Direct Payment Delegation Tests
 * @notice Tests for V2 Direct Payment Delegation (Coinbase Smart Wallet)
 * @dev Tests for Phase 3: createSessionAsDelegate and createSessionForModelAsDelegate
 *
 * V2 Pattern: Delegate pulls USDC directly from payer's wallet via transferFrom
 * - Payer approves USDC to contract
 * - Payer authorizes delegate
 * - Delegate creates session → contract pulls from payer's wallet
 * - Session owned by payer (not delegate)
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
    address public payer = address(0x3);  // Primary account (has USDC)
    address public delegate = address(0x4);  // Sub-account (creates sessions)
    address public treasury = address(0x5);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;  // 0.5 USDC
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;  // 1M USDC
    uint256 constant SESSION_AMOUNT = 10_000_000;  // 10 USDC

    event SessionJobCreated(uint256 indexed jobId, address indexed depositor, address indexed host, uint256 deposit);
    event SessionJobCreatedForModel(uint256 indexed jobId, address indexed depositor, address indexed host, bytes32 modelId, uint256 deposit);
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

        // Register host with model support
        _registerHost(host);

        // Setup payer with USDC and approvals
        usdcToken.mint(payer, 100_000_000_000);  // 100k USDC
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
            payer,           // payer (whose USDC is used)
            modelId,         // model
            host,            // host
            address(usdcToken),  // payment token (USDC)
            SESSION_AMOUNT,  // amount
            MIN_PRICE_STABLE,  // price per token
            1 days,          // max duration
            1000,            // proof interval
            300              // proof timeout window
        );

        // Verify session created
        assertTrue(sessionId > 0, "Session should be created");

        // Verify USDC pulled from payer
        assertEq(usdcToken.balanceOf(payer), payerBalanceBefore - SESSION_AMOUNT, "USDC should be pulled from payer");

        // Verify session owned by payer (not delegate)
        (,address depositor,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, payer, "Session should be owned by payer");

        // Verify model stored
        assertEq(marketplace.sessionModel(sessionId), modelId, "Model should be stored");
    }

    function test_CreateSessionForModelAsDelegate_EmitsEvents() public {
        vm.prank(delegate);
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(1, payer, host, SESSION_AMOUNT);

        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_UnauthorizedDelegate_Reverts() public {
        address unauthorizedDelegate = makeAddr("unauthorized");

        vm.prank(unauthorizedDelegate);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_RevokedDelegate_Reverts() public {
        // Revoke delegate
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate, false);

        vm.prank(delegate);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_ETH_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Direct delegation requires ERC-20 token");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(0),  // ETH
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_InsufficientAllowance_Reverts() public {
        // Set low allowance
        vm.prank(payer);
        usdcToken.approve(address(marketplace), SESSION_AMOUNT - 1);

        vm.prank(delegate);
        vm.expectRevert();  // ERC20 transfer will fail
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_InsufficientBalance_Reverts() public {
        // Create a new payer with limited USDC
        address poorPayer = makeAddr("poorPayer");
        usdcToken.mint(poorPayer, SESSION_AMOUNT - 1);  // Not enough for session

        vm.prank(poorPayer);
        usdcToken.approve(address(marketplace), type(uint256).max);

        vm.prank(poorPayer);
        marketplace.authorizeDelegate(delegate, true);

        vm.prank(delegate);
        vm.expectRevert();  // ERC20 transfer will fail
        marketplace.createSessionForModelAsDelegate(
            poorPayer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_ZeroPayer_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Invalid payer");
        marketplace.createSessionForModelAsDelegate(
            address(0), modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_InvalidModel_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Invalid model ID");
        marketplace.createSessionForModelAsDelegate(
            payer, bytes32(0), host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_PayerCanAlsoCreateDirectly() public {
        // Payer can still create their own sessions directly (not as delegate)
        vm.prank(payer);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer,           // payer is also the caller
            modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        (,address depositor,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, payer, "Session should be owned by payer");
    }

    // ============================================================
    // createSessionAsDelegate Tests (Non-Model)
    // ============================================================

    function test_CreateSessionAsDelegate_Success() public {
        uint256 payerBalanceBefore = usdcToken.balanceOf(payer);

        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionAsDelegate(
            payer,
            host,
            address(usdcToken),
            SESSION_AMOUNT,
            MIN_PRICE_STABLE,
            1 days,
            1000,
            300
        );

        assertTrue(sessionId > 0, "Session should be created");
        assertEq(usdcToken.balanceOf(payer), payerBalanceBefore - SESSION_AMOUNT, "USDC should be pulled from payer");

        (,address depositor,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, payer, "Session should be owned by payer");

        // No model stored for non-model session
        assertEq(marketplace.sessionModel(sessionId), bytes32(0), "No model for non-model session");
    }

    function test_CreateSessionAsDelegate_UnauthorizedDelegate_Reverts() public {
        address unauthorizedDelegate = makeAddr("unauthorized");

        vm.prank(unauthorizedDelegate);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionAsDelegate(
            payer, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    function test_CreateSessionAsDelegate_ETH_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Direct delegation requires ERC-20 token");
        marketplace.createSessionAsDelegate(
            payer, host, address(0),  // ETH
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    // ============================================================
    // Multiple Delegated Sessions
    // ============================================================

    function test_MultipleSessionsFromSamePayer() public {
        uint256 payerBalanceBefore = usdcToken.balanceOf(payer);

        vm.startPrank(delegate);

        uint256 s1 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        uint256 s2 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT * 2, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        vm.stopPrank();

        // Both sessions owned by payer
        (,address depositor1,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(s1);
        (,address depositor2,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(s2);
        assertEq(depositor1, payer);
        assertEq(depositor2, payer);

        // Total USDC pulled
        assertEq(
            usdcToken.balanceOf(payer),
            payerBalanceBefore - SESSION_AMOUNT - SESSION_AMOUNT * 2,
            "Total USDC should be pulled"
        );
    }

    function test_MultipleDelegatesForSamePayer() public {
        address delegate2 = makeAddr("delegate2");

        // Authorize second delegate
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate2, true);

        // Both delegates can create sessions
        vm.prank(delegate);
        uint256 s1 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        vm.prank(delegate2);
        uint256 s2 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, host, address(usdcToken),
            SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // Both sessions owned by payer
        (,address depositor1,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(s1);
        (,address depositor2,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(s2);
        assertEq(depositor1, payer);
        assertEq(depositor2, payer);
    }
}
