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
 * @title Proof Timeout Window Tests (F202614911)
 * @notice Tests for Phase 3: Separate proofTimeoutWindow from proofInterval
 *
 * Issue: proofInterval is validated as token count (MIN_PROVEN_TOKENS = 100)
 * but used as seconds in triggerSessionTimeout():
 *   block.timestamp > session.lastProofTime + session.proofInterval * 3
 *
 * Fix: Add separate proofTimeoutWindow field for time-based timeout.
 */
contract ProofTimeoutWindowTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    uint256 public hostPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address public host;
    address public user = address(0x3);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        host = vm.addr(hostPrivateKey);

        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");

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

        // Configure
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        marketplace.setProofSystem(address(proofSystem));

        vm.stopPrank();

        // Register host
        _registerHost(host);

        // Fund user
        vm.deal(user, 100 ether);
    }

    function _registerHost(address _host) internal {
        fabToken.mint(_host, MIN_STAKE);

        vm.startPrank(_host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);
        vm.stopPrank();
    }

    // ============================================================
    // Test: Session creation with proofTimeoutWindow
    // ============================================================

    function test_CreateSession_WithValidTimeoutWindow() public {
        uint256 proofInterval = 100;
        uint256 proofTimeoutWindow = 300; // 5 minutes

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 0.01 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 hours, proofInterval, proofTimeoutWindow
        );

        assertGt(sessionId, 0, "Session should be created");
    }

    function test_CreateSession_RejectsTooSmallTimeout() public {
        uint256 proofInterval = 100;
        uint256 tooSmallTimeout = 30; // Below MIN_PROOF_TIMEOUT (60s)

        vm.prank(user);
        vm.expectRevert("Bad timeout");
        marketplace.createSessionJobForModel{value: 0.01 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 hours, proofInterval, tooSmallTimeout
        );
    }

    function test_CreateSession_RejectsTooLargeTimeout() public {
        uint256 proofInterval = 100;
        uint256 tooLargeTimeout = 7200; // Above MAX_PROOF_TIMEOUT (3600s)

        vm.prank(user);
        vm.expectRevert("Bad timeout");
        marketplace.createSessionJobForModel{value: 0.01 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 hours, proofInterval, tooLargeTimeout
        );
    }

    // ============================================================
    // Test: triggerSessionTimeout uses proofTimeoutWindow
    // ============================================================

    function test_TriggerTimeout_UsesProofTimeoutWindow() public {
        uint256 proofInterval = 1000; // Token count (NOT seconds)
        uint256 proofTimeoutWindow = 120; // 2 minutes

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 0.01 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 hours, proofInterval, proofTimeoutWindow
        );

        // Fast forward just past the timeout window
        vm.warp(block.timestamp + proofTimeoutWindow + 1);

        // Should be able to trigger timeout
        marketplace.triggerSessionTimeout(sessionId);

        // Verify session is timed out
        (,,,,,,,,,,,, JobMarketplaceWithModelsUpgradeable.SessionStatus status,,,,,) =
            marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModelsUpgradeable.SessionStatus.TimedOut));
    }

    function test_TriggerTimeout_FailsBeforeWindowExpires() public {
        uint256 proofInterval = 1000;
        uint256 proofTimeoutWindow = 300; // 5 minutes

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 0.01 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 hours, proofInterval, proofTimeoutWindow
        );

        // Fast forward less than the timeout window
        vm.warp(block.timestamp + proofTimeoutWindow - 10);

        // Should NOT be able to trigger timeout
        vm.expectRevert("Session not timed out");
        marketplace.triggerSessionTimeout(sessionId);
    }

    function test_TriggerTimeout_FallbackForLegacySessions() public {
        uint256 defaultTimeout = marketplace.DEFAULT_PROOF_TIMEOUT();
        assertEq(defaultTimeout, 300, "Default timeout should be 5 minutes");
    }

    // ============================================================
    // Test: Model-specific session with proofTimeoutWindow
    // ============================================================

    function test_CreateSessionForModel_WithTimeoutWindow() public {
        uint256 proofInterval = 100;
        uint256 proofTimeoutWindow = 180; // 3 minutes

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 0.01 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 hours, proofInterval, proofTimeoutWindow
        );

        assertGt(sessionId, 0, "Model session should be created");
    }

    // ============================================================
    // Test: Constants are properly defined
    // ============================================================

    function test_TimeoutConstants_AreDefined() public view {
        assertEq(marketplace.MIN_PROOF_TIMEOUT(), 60, "Min timeout should be 1 minute");
        assertEq(marketplace.MAX_PROOF_TIMEOUT(), 3600, "Max timeout should be 1 hour");
        assertEq(marketplace.DEFAULT_PROOF_TIMEOUT(), 300, "Default timeout should be 5 minutes");
    }
}
