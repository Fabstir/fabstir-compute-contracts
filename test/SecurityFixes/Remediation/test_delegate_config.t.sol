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
 * @title Delegate Config Tests (F202615255 + F202615256)
 * @notice Tests for delegate spending limits and scope restrictions
 */
contract DelegateConfigTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public hostA = address(0x2);
    address public payer = address(0x3);
    address public delegate = address(0x4);
    address public treasury = address(0x5);
    address public hostB = address(0x6);

    bytes32 public modelIdA;
    bytes32 public modelIdB;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant SESSION_AMOUNT = 10_000_000; // 10 USDC

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
        modelRegistry.addTrustedModel("ModelA/Repo", "modelA.gguf", bytes32(uint256(1)));
        modelIdA = modelRegistry.getModelId("ModelA/Repo", "modelA.gguf");
        modelRegistry.addTrustedModel("ModelB/Repo", "modelB.gguf", bytes32(uint256(2)));
        modelIdB = modelRegistry.getModelId("ModelB/Repo", "modelB.gguf");

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

        _registerHost(hostA, modelIdA);
        _registerHost(hostB, modelIdB);
        // hostA also supports modelB, hostB also supports modelA
        _addModelToHost(hostA, modelIdB);
        _addModelToHost(hostB, modelIdA);

        // Fund payer
        usdcToken.mint(payer, 1_000_000_000_000);
        vm.prank(payer);
        usdcToken.approve(address(marketplace), type(uint256).max);
    }

    function _registerHost(address _host, bytes32 _modelId) internal {
        fabToken.mint(_host, MIN_STAKE);
        vm.startPrank(_host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = _modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(_modelId, address(usdcToken), MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    function _addModelToHost(address _host, bytes32 _modelId) internal {
        bytes32[] memory existingModels = nodeRegistry.getNodeModels(_host);
        bytes32[] memory newModels = new bytes32[](existingModels.length + 1);
        for (uint256 i = 0; i < existingModels.length; i++) {
            newModels[i] = existingModels[i];
        }
        newModels[existingModels.length] = _modelId;
        vm.startPrank(_host);
        nodeRegistry.updateSupportedModels(newModels);
        nodeRegistry.setModelTokenPricing(_modelId, address(usdcToken), MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    function _createSession(address _delegate, address _host, bytes32 _modelId, uint256 _amount) internal returns (uint256) {
        vm.prank(_delegate);
        return marketplace.createSessionForModelAsDelegate(
            payer, _modelId, _host, address(usdcToken), _amount, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    // ============================================================
    // F202615255: Spending Limits Tests
    // ============================================================

    /// @notice configureDelegate stores config correctly
    function test_ConfigureDelegate_StoresConfig() public {
        vm.prank(payer);
        marketplace.configureDelegate(
            delegate,
            uint128(SESSION_AMOUNT), // maxPerSession
            uint128(SESSION_AMOUNT * 5), // totalCap
            uint64(block.timestamp + 1 days), // validUntil
            hostA, // allowedHost
            modelIdA // allowedModel
        );

        (
            uint128 maxPerSession,
            uint128 totalCap,
            uint128 spent,
            uint64 validUntil,
            bool active,
            address allowedHost,
            bytes32 allowedModel
        ) = marketplace.delegateConfigs(payer, delegate);

        assertEq(maxPerSession, uint128(SESSION_AMOUNT));
        assertEq(totalCap, uint128(SESSION_AMOUNT * 5));
        assertEq(spent, 0);
        assertEq(validUntil, uint64(block.timestamp + 1 days));
        assertTrue(active);
        assertEq(allowedHost, hostA);
        assertEq(allowedModel, modelIdA);
    }

    /// @notice F202615255: Delegate exceeding maxPerSession reverts
    function test_Delegate_ExceedsMaxPerSession_Reverts() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, uint128(SESSION_AMOUNT - 1), 0, 0, address(0), bytes32(0));

        vm.prank(delegate);
        vm.expectRevert("Over limit");
        marketplace.createSessionForModelAsDelegate(
            payer, modelIdA, hostA, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    /// @notice F202615255: Delegate within maxPerSession succeeds
    function test_Delegate_WithinMaxPerSession_Succeeds() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, uint128(SESSION_AMOUNT), 0, 0, address(0), bytes32(0));

        uint256 sid = _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        assertTrue(sid > 0);
    }

    /// @notice F202615255: Delegate exceeding totalCap across sessions reverts
    function test_Delegate_ExceedsTotalCap_Reverts() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, uint128(SESSION_AMOUNT * 2 - 1), 0, address(0), bytes32(0));

        _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);

        vm.prank(delegate);
        vm.expectRevert("Over cap");
        marketplace.createSessionForModelAsDelegate(
            payer, modelIdA, hostA, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    /// @notice F202615255: Delegate within totalCap succeeds
    function test_Delegate_WithinTotalCap_Succeeds() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, uint128(SESSION_AMOUNT * 2), 0, address(0), bytes32(0));

        _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        uint256 sid = _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        assertTrue(sid > 0);
    }

    /// @notice F202615255: Expired delegate reverts
    function test_Delegate_Expired_Reverts() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, uint64(block.timestamp + 100), address(0), bytes32(0));

        vm.warp(block.timestamp + 101);

        vm.prank(delegate);
        vm.expectRevert("Expired");
        marketplace.createSessionForModelAsDelegate(
            payer, modelIdA, hostA, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    /// @notice Delegate with valid expiry succeeds
    function test_Delegate_ValidExpiry_Succeeds() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, uint64(block.timestamp + 1 days), address(0), bytes32(0));

        uint256 sid = _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        assertTrue(sid > 0);
    }

    // ============================================================
    // F202615256: Scope Restriction Tests
    // ============================================================

    /// @notice F202615256: Delegate restricted to hostA tries hostB → reverts
    function test_Delegate_WrongHost_Reverts() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, hostA, bytes32(0));

        vm.prank(delegate);
        vm.expectRevert("Wrong host");
        marketplace.createSessionForModelAsDelegate(
            payer, modelIdA, hostB, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    /// @notice F202615256: Delegate restricted to hostA with hostA → succeeds
    function test_Delegate_CorrectHost_Succeeds() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, hostA, bytes32(0));

        uint256 sid = _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        assertTrue(sid > 0);
    }

    /// @notice F202615256: Delegate restricted to modelA tries modelB → reverts
    function test_Delegate_WrongModel_Reverts() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), modelIdA);

        vm.prank(delegate);
        vm.expectRevert("Wrong model");
        marketplace.createSessionForModelAsDelegate(
            payer, modelIdB, hostA, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    /// @notice F202615256: Delegate restricted to modelA with modelA → succeeds
    function test_Delegate_CorrectModel_Succeeds() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), modelIdA);

        uint256 sid = _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        assertTrue(sid > 0);
    }

    // ============================================================
    // Unrestricted + Revocation Tests
    // ============================================================

    /// @notice Unrestricted delegate (all zeros) works with any host/model/amount
    function test_Delegate_Unrestricted_Succeeds() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), bytes32(0));

        uint256 s1 = _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        uint256 s2 = _createSession(delegate, hostB, modelIdB, SESSION_AMOUNT * 2);
        assertTrue(s1 > 0);
        assertTrue(s2 > 0);
    }

    /// @notice Revoking delegate (active = false) reverts
    function test_Delegate_Revoked_Reverts() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), bytes32(0));

        // Revoke using authorizeDelegate(delegate, false)
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate, false);

        vm.prank(delegate);
        vm.expectRevert("Not delegate");
        marketplace.createSessionForModelAsDelegate(
            payer, modelIdA, hostA, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    /// @notice Old isAuthorizedDelegate mapping no longer grants access
    function test_OldMapping_NoAccess() public {
        // Don't configure via new system - old mapping is no longer checked
        vm.prank(delegate);
        vm.expectRevert("Not delegate");
        marketplace.createSessionForModelAsDelegate(
            payer, modelIdA, hostA, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    /// @notice authorizeDelegate(delegate, true) sets config active for backwards compat
    function test_AuthorizeDelegate_SetsConfigActive() public {
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate, true);

        (,,,,bool active,,) = marketplace.delegateConfigs(payer, delegate);
        assertTrue(active);
    }

    /// @notice Payer can still create sessions for themselves (msg.sender == payer bypass)
    function test_Payer_CreatesOwnSession() public {
        vm.prank(payer);
        uint256 sid = marketplace.createSessionForModelAsDelegate(
            payer, modelIdA, hostA, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        assertTrue(sid > 0);
    }

    /// @notice configureDelegate with zero address reverts
    function test_ConfigureDelegate_ZeroAddress_Reverts() public {
        vm.prank(payer);
        vm.expectRevert("Zero addr");
        marketplace.configureDelegate(address(0), 0, 0, 0, address(0), bytes32(0));
    }

    /// @notice configureDelegate with self reverts
    function test_ConfigureDelegate_Self_Reverts() public {
        vm.prank(payer);
        vm.expectRevert("Self deleg");
        marketplace.configureDelegate(payer, 0, 0, 0, address(0), bytes32(0));
    }

    /// @notice Spent counter tracks cumulative spending
    function test_Delegate_SpentCounter_Tracks() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, uint128(SESSION_AMOUNT * 10), 0, address(0), bytes32(0));

        _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);

        (,,uint128 spent,,,,) = marketplace.delegateConfigs(payer, delegate);
        assertEq(spent, uint128(SESSION_AMOUNT));

        _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT * 2);

        (,,spent,,,,) = marketplace.delegateConfigs(payer, delegate);
        assertEq(spent, uint128(SESSION_AMOUNT * 3));
    }

    // ============================================================
    // Phase 26: Security Review Hardening Tests
    // ============================================================

    /// @notice Security review: configureDelegate resets spent counter
    function test_ConfigureDelegate_ResetsSpent() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, uint128(SESSION_AMOUNT * 10), 0, address(0), bytes32(0));

        // Spend some
        _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        (,,uint128 spent,,,,) = marketplace.delegateConfigs(payer, delegate);
        assertEq(spent, uint128(SESSION_AMOUNT));

        // Reconfigure — spent should reset to 0
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, uint128(SESSION_AMOUNT * 10), 0, address(0), bytes32(0));

        (,,spent,,,,) = marketplace.delegateConfigs(payer, delegate);
        assertEq(spent, 0, "spent should reset on reconfigure");
    }

    /// @notice Security review: authorizeDelegate(true) clears stale validUntil
    function test_AuthorizeDelegate_AfterExpiry_ClearsExpiry() public {
        // Configure with expiry
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, uint64(block.timestamp + 100), address(0), bytes32(0));

        // Warp past expiry
        vm.warp(block.timestamp + 200);

        // Re-authorize using simple authorizeDelegate
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate, true);

        // Should succeed — validUntil should be cleared
        uint256 sid = _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        assertTrue(sid > 0, "delegate should work after re-auth clears expiry");
    }

    /// @notice Security review: exact validUntil boundary
    function test_Delegate_ExactExpiryBoundary() public {
        uint64 expiryTime = uint64(block.timestamp + 1000);
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, expiryTime, address(0), bytes32(0));

        // At exact expiry — should succeed (<=)
        vm.warp(expiryTime);
        uint256 sid = _createSession(delegate, hostA, modelIdA, SESSION_AMOUNT);
        assertTrue(sid > 0, "should succeed at exact expiry");

        // One second past — should fail
        vm.warp(expiryTime + 1);
        vm.prank(delegate);
        vm.expectRevert("Expired");
        marketplace.createSessionForModelAsDelegate(
            payer, modelIdA, hostA, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    /// @notice Security review: authorizeDelegate preserves config fields
    function test_AuthorizeDelegate_PreservesConfig() public {
        // Configure with specific limits
        vm.prank(payer);
        marketplace.configureDelegate(delegate, uint128(SESSION_AMOUNT), uint128(SESSION_AMOUNT * 5), 0, hostA, modelIdA);

        // Revoke via authorizeDelegate
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate, false);

        // Re-auth via authorizeDelegate
        vm.prank(payer);
        marketplace.authorizeDelegate(delegate, true);

        // Verify limits are preserved
        (uint128 maxPerSession, uint128 totalCap,,, bool active, address allowedHost, bytes32 allowedModel) =
            marketplace.delegateConfigs(payer, delegate);
        assertTrue(active);
        assertEq(maxPerSession, uint128(SESSION_AMOUNT), "maxPerSession preserved");
        assertEq(totalCap, uint128(SESSION_AMOUNT * 5), "totalCap preserved");
        assertEq(allowedHost, hostA, "allowedHost preserved");
        assertEq(allowedModel, modelIdA, "allowedModel preserved");
    }

    /// @notice Security review: safe cast for large amounts
    function test_Delegate_LargeAmount_SafeCast() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), bytes32(0));

        // amount > type(uint128).max should revert
        uint256 largeAmount = uint256(type(uint128).max) + 1;

        vm.prank(delegate);
        vm.expectRevert("Overflow");
        marketplace.createSessionForModelAsDelegate(
            payer, modelIdA, hostA, address(usdcToken), largeAmount, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    /// @notice Security review: DelegateConfigured event emitted on configureDelegate
    function test_ConfigureDelegate_EmitsEvent() public {
        vm.prank(payer);
        vm.expectEmit(true, true, false, true);
        emit DelegateConfigured(payer, delegate, uint128(SESSION_AMOUNT), uint128(SESSION_AMOUNT * 5), uint64(block.timestamp + 1 days), hostA, modelIdA);
        marketplace.configureDelegate(
            delegate,
            uint128(SESSION_AMOUNT),
            uint128(SESSION_AMOUNT * 5),
            uint64(block.timestamp + 1 days),
            hostA,
            modelIdA
        );
    }

    event DelegateConfigured(address indexed depositor, address indexed delegate, uint128 maxPerSession, uint128 totalCap, uint64 validUntil, address allowedHost, bytes32 allowedModel);
}
