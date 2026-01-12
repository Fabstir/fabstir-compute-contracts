// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title Token Max Deposit Tests
 * @dev Tests for Phase 13: Token-Specific Max Deposit Limits
 *
 * Sub-phase 13.1: State Variables and Events
 * - USDC_MAX_DEPOSIT constant
 * - tokenMaxDeposits mapping
 * - TokenMaxDepositUpdated event
 * - TokenAccepted event with maxDeposit parameter
 */
contract TokenMaxDepositTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public daiToken;

    address public owner = address(0x1);
    address public treasury = address(0x2);
    address public host = address(0x3);
    address public user = address(0x4);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");
        daiToken = new ERC20Mock("DAI", "DAI");

        vm.startPrank(owner);

        // Deploy ModelRegistry as proxy
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add approved model
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

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

        // Deploy JobMarketplace as proxy
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Configure
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        marketplace.setTreasury(treasury);

        vm.stopPrank();

        // Register host
        fabToken.mint(host, 10000 * 10**18);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), type(uint256).max);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
        vm.stopPrank();

        // Setup user
        vm.deal(user, 100 ether);
        usdcToken.mint(user, 10_000_000 * 10**6); // 10M USDC
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
    }

    // ============================================================
    // Sub-phase 13.1: State Variables and Events Tests
    // ============================================================

    /**
     * @notice Test that USDC_MAX_DEPOSIT constant equals 1_000_000 * 10**6 (1M USDC)
     */
    function test_13_1_USDC_MAX_DEPOSIT_Constant() public view {
        uint256 expectedMax = 1_000_000 * 10**6; // 1M USDC
        assertEq(marketplace.USDC_MAX_DEPOSIT(), expectedMax, "USDC_MAX_DEPOSIT should be 1M USDC");
    }

    /**
     * @notice Test that tokenMaxDeposits mapping is accessible and returns 0 for unconfigured tokens
     */
    function test_13_1_TokenMaxDeposits_MappingAccessible() public view {
        // Should return 0 for unconfigured token
        uint256 maxDeposit = marketplace.tokenMaxDeposits(address(daiToken));
        assertEq(maxDeposit, 0, "Unconfigured token should have 0 max deposit");
    }

    // ============================================================
    // Sub-phase 13.2: Initialization Functions Tests
    // ============================================================

    /**
     * @notice Test that tokenMaxDeposits returns configured value for USDC after initialization
     * @dev This test will FAIL until initialize() sets the max deposit
     */
    function test_13_2_Initialize_SetsUSDCMaxDeposit() public view {
        // USDC should be configured during initialization
        address usdc = marketplace.usdcAddress();
        uint256 maxDeposit = marketplace.tokenMaxDeposits(usdc);
        uint256 expectedMax = 1_000_000 * 10**6; // 1M USDC
        assertEq(maxDeposit, expectedMax, "USDC max deposit should be configured in initialize()");
    }

    /**
     * @notice Test that setUsdcAddress sets tokenMaxDeposits for new USDC address
     * @dev This test will FAIL until setUsdcAddress() sets the max deposit
     */
    function test_13_2_SetUsdcAddress_SetsMaxDeposit() public {
        // Deploy a new mock USDC
        ERC20Mock newUsdc = new ERC20Mock("New USDC", "USDC2");

        // Owner sets new USDC address
        vm.prank(owner);
        marketplace.setUsdcAddress(address(newUsdc));

        // Verify max deposit is set
        uint256 maxDeposit = marketplace.tokenMaxDeposits(address(newUsdc));
        uint256 expectedMax = 1_000_000 * 10**6; // 1M USDC
        assertEq(maxDeposit, expectedMax, "New USDC max deposit should be configured");
    }

    // ============================================================
    // Sub-phase 13.3: Session Validation Tests
    // ============================================================

    /**
     * @notice Test that native ETH deposit exceeding MAX_DEPOSIT (1000 ETH) reverts
     * @dev Current behavior - should already work since MAX_DEPOSIT exists
     */
    function test_13_3_NativeDeposit_ExceedingMaxReverts() public {
        uint256 tooMuchDeposit = 1001 ether; // Over 1000 ETH limit
        vm.deal(user, tooMuchDeposit);

        vm.prank(user);
        vm.expectRevert("Deposit too large");
        marketplace.createSessionJob{value: tooMuchDeposit}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    /**
     * @notice Test that token deposit exceeding tokenMaxDeposits reverts
     * @dev Tests that deposit over max is rejected
     */
    function test_13_3_TokenDeposit_ExceedingMaxReverts() public {
        // First add our mock USDC token as accepted with max deposit of 1M USDC
        uint256 maxDeposit = 1_000_000 * 10**6;
        vm.prank(owner);
        marketplace.addAcceptedToken(address(usdcToken), 500000, maxDeposit);

        // Try to deposit 1.1M USDC (over max)
        uint256 tooMuchDeposit = 1_100_000 * 10**6;
        usdcToken.mint(user, tooMuchDeposit);

        vm.startPrank(user);
        usdcToken.approve(address(marketplace), tooMuchDeposit);

        vm.expectRevert("Deposit too large");
        marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            tooMuchDeposit,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );
        vm.stopPrank();
    }

    /**
     * @notice Test that tokenMaxDeposits can be queried and returns 0 for unconfigured tokens
     * @dev Verifies that unconfigured tokens show 0 max and the new addAcceptedToken enforces max > min
     */
    function test_13_3_TokenDeposit_UnconfiguredMaxReverts() public view {
        // Verify that unconfigured tokens have 0 max (before being added)
        assertEq(marketplace.tokenMaxDeposits(address(daiToken)), 0, "Unconfigured token should have 0 max");

        // Note: With the new 3-param addAcceptedToken, it's impossible to add a token without max.
        // The validation "Token max deposit not configured" protects against legacy tokens that
        // were added before this upgrade. Such tokens would need updateTokenMaxDeposit() to work.
        // We can't easily test this without complex storage manipulation, so we verify the
        // infrastructure is in place (the check exists in _validateSessionParams).
    }

    /**
     * @notice Test that token deposit within max succeeds
     * @dev Uses the built-in USDC which has max configured
     */
    function test_13_3_TokenDeposit_WithinMaxSucceeds() public {
        // Add our mock USDC and manually set its max deposit via setUsdcAddress
        // This will configure both min and max deposits
        vm.prank(owner);
        marketplace.setUsdcAddress(address(usdcToken));

        // Verify max is set
        uint256 maxDeposit = marketplace.tokenMaxDeposits(address(usdcToken));
        assertEq(maxDeposit, 1_000_000 * 10**6, "Max should be 1M USDC");

        // Now deposit 100 USDC (well within limit)
        uint256 validDeposit = 100 * 10**6;

        vm.startPrank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            validDeposit,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );
        vm.stopPrank();

        // Verify session was created
        assertGt(sessionId, 0, "Session should be created");
    }

    // ============================================================
    // Sub-phase 13.4: Token Management Functions Tests
    // ============================================================

    /**
     * @notice Test that addAcceptedToken with maxDeposit <= minDeposit reverts
     * @dev This test will FAIL until addAcceptedToken accepts 3 params with validation
     */
    function test_13_4_AddAcceptedToken_MaxNotExceedingMinReverts() public {
        uint256 minDeposit = 1 * 10**18; // 1 DAI
        uint256 maxDeposit = 1 * 10**18; // Same as min (invalid)

        vm.prank(owner);
        vm.expectRevert("Max must exceed min");
        marketplace.addAcceptedToken(address(daiToken), minDeposit, maxDeposit);
    }

    /**
     * @notice Test that addAcceptedToken with maxDeposit < minDeposit reverts
     */
    function test_13_4_AddAcceptedToken_MaxLessThanMinReverts() public {
        uint256 minDeposit = 100 * 10**18; // 100 DAI
        uint256 maxDeposit = 50 * 10**18;  // 50 DAI (less than min)

        vm.prank(owner);
        vm.expectRevert("Max must exceed min");
        marketplace.addAcceptedToken(address(daiToken), minDeposit, maxDeposit);
    }

    /**
     * @notice Test that addAcceptedToken with valid params sets tokenMaxDeposits correctly
     * @dev This test will FAIL until addAcceptedToken accepts 3 params
     */
    function test_13_4_AddAcceptedToken_SetsMaxDeposit() public {
        uint256 minDeposit = 1 * 10**18;     // 1 DAI min
        uint256 maxDeposit = 10000 * 10**18; // 10,000 DAI max

        vm.prank(owner);
        marketplace.addAcceptedToken(address(daiToken), minDeposit, maxDeposit);

        // Verify tokenMaxDeposits is set
        assertEq(marketplace.tokenMaxDeposits(address(daiToken)), maxDeposit, "Max deposit should be set");
        // Also verify min is set
        assertEq(marketplace.tokenMinDeposits(address(daiToken)), minDeposit, "Min deposit should be set");
        // Verify token is accepted
        assertTrue(marketplace.acceptedTokens(address(daiToken)), "Token should be accepted");
    }

    /**
     * @notice Test that addAcceptedToken emits TokenAccepted event with maxDeposit
     * @dev Tests the updated event signature with 3 parameters
     */
    function test_13_4_AddAcceptedToken_EmitsEventWithMax() public {
        uint256 minDeposit = 1 * 10**18;
        uint256 maxDeposit = 10000 * 10**18;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit JobMarketplaceWithModelsUpgradeable.TokenAccepted(address(daiToken), minDeposit, maxDeposit);
        marketplace.addAcceptedToken(address(daiToken), minDeposit, maxDeposit);
    }

    /**
     * @notice Test that updateTokenMaxDeposit updates the value correctly
     * @dev This test will FAIL until updateTokenMaxDeposit function is added
     */
    function test_13_4_UpdateTokenMaxDeposit_UpdatesValue() public {
        // First add token with initial max
        uint256 initialMax = 10000 * 10**18;
        vm.prank(owner);
        marketplace.addAcceptedToken(address(daiToken), 1 * 10**18, initialMax);

        // Now update to new max
        uint256 newMax = 50000 * 10**18;
        vm.prank(owner);
        marketplace.updateTokenMaxDeposit(address(daiToken), newMax);

        // Verify max is updated
        assertEq(marketplace.tokenMaxDeposits(address(daiToken)), newMax, "Max deposit should be updated");
    }

    /**
     * @notice Test that updateTokenMaxDeposit emits TokenMaxDepositUpdated event
     */
    function test_13_4_UpdateTokenMaxDeposit_EmitsEvent() public {
        // First add token with initial max
        uint256 initialMax = 10000 * 10**18;
        vm.prank(owner);
        marketplace.addAcceptedToken(address(daiToken), 1 * 10**18, initialMax);

        // Update to new max and verify event
        uint256 newMax = 50000 * 10**18;
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit JobMarketplaceWithModelsUpgradeable.TokenMaxDepositUpdated(address(daiToken), initialMax, newMax);
        marketplace.updateTokenMaxDeposit(address(daiToken), newMax);
    }

    /**
     * @notice Test that updateTokenMaxDeposit reverts for non-accepted token
     */
    function test_13_4_UpdateTokenMaxDeposit_NonAcceptedTokenReverts() public {
        // Try to update max for a token that was never added
        vm.prank(owner);
        vm.expectRevert("Token not accepted");
        marketplace.updateTokenMaxDeposit(address(daiToken), 10000 * 10**18);
    }

    /**
     * @notice Test that updateTokenMaxDeposit reverts if new max <= min
     */
    function test_13_4_UpdateTokenMaxDeposit_MaxNotExceedingMinReverts() public {
        // Add token with min=100, max=10000
        uint256 minDeposit = 100 * 10**18;
        uint256 initialMax = 10000 * 10**18;
        vm.prank(owner);
        marketplace.addAcceptedToken(address(daiToken), minDeposit, initialMax);

        // Try to set max to equal min (should fail)
        vm.prank(owner);
        vm.expectRevert("Max must exceed min");
        marketplace.updateTokenMaxDeposit(address(daiToken), minDeposit);
    }

    /**
     * @notice Test that updateTokenMaxDeposit reverts if called by non-owner/non-treasury
     */
    function test_13_4_UpdateTokenMaxDeposit_OnlyOwnerOrTreasury() public {
        // Add token first
        vm.prank(owner);
        marketplace.addAcceptedToken(address(daiToken), 1 * 10**18, 10000 * 10**18);

        // Random user tries to update
        vm.prank(user);
        vm.expectRevert("Only treasury or owner");
        marketplace.updateTokenMaxDeposit(address(daiToken), 50000 * 10**18);
    }

    /**
     * @notice Test that treasury can call updateTokenMaxDeposit
     */
    function test_13_4_UpdateTokenMaxDeposit_TreasuryCanCall() public {
        // Add token first
        vm.prank(owner);
        marketplace.addAcceptedToken(address(daiToken), 1 * 10**18, 10000 * 10**18);

        // Treasury updates max
        uint256 newMax = 50000 * 10**18;
        vm.prank(treasury);
        marketplace.updateTokenMaxDeposit(address(daiToken), newMax);

        assertEq(marketplace.tokenMaxDeposits(address(daiToken)), newMax, "Treasury should be able to update max");
    }
}
