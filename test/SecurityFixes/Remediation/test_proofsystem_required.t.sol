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
 * @title ProofSystem Required Tests (AUDIT-F2)
 * @notice Tests for Phase 2: Require ProofSystem configuration for proof submission
 *
 * Finding: AUDIT-F2
 * Slack Ref: slack-C0A61FZC8SH-p1769545156133729
 *
 * Issue: When proofSystem is address(0), hosts can submit arbitrary proofs
 * without verification. This allows hosts to claim tokens for work they
 * haven't done, draining user deposits.
 *
 * Fix: Add require(address(proofSystem) != address(0), "ProofSystem not configured")
 * at the start of proof verification in submitProofOfWork().
 */
contract ProofSystemRequiredTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    uint256 public hostPrivateKey = 0x2;
    address public host; // Set in setUp using vm.addr
    address public user = address(0x3);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PROVEN_TOKENS = 100;

    function setUp() public {
        // Derive host address from private key for signature verification
        host = vm.addr(hostPrivateKey);

        vm.startPrank(owner);

        // Deploy mock tokens
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

        // Deploy JobMarketplace WITHOUT ProofSystem configured
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

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

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
        vm.stopPrank();
    }

    // ============================================================
    // Test: submitProofOfWork reverts when ProofSystem not configured
    // ============================================================

    /**
     * @notice Verify proof submission fails when ProofSystem is address(0)
     * @dev This test should FAIL before the fix (current code allows this)
     *      After fix: Should revert with "ProofSystem not configured"
     */
    function test_SubmitProof_RevertsWhenProofSystemNotConfigured() public {
        // Verify ProofSystem is not configured
        assertEq(address(marketplace.proofSystem()), address(0), "ProofSystem should be address(0)");

        // Create a session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(host, MIN_PRICE_NATIVE, 1 hours, 100, 300);

        // Wait for some time so token rate limit passes
        vm.warp(block.timestamp + 1);

        // Prepare arbitrary proof data (signature doesn't matter since no verification)
        bytes32 proofHash = keccak256("arbitrary proof");
        bytes memory signature = new bytes(65); // Empty signature

        // Host tries to submit proof - should revert when ProofSystem not configured
        vm.prank(host);
        vm.expectRevert("ProofSystem not configured");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, signature, "QmProofCID", "QmDeltaCID");
    }

    // ============================================================
    // Test: submitProofOfWork succeeds when ProofSystem is configured
    // ============================================================

    /**
     * @notice Verify proof submission works with valid ProofSystem and signature
     * @dev This is a baseline test to ensure the fix doesn't break normal operation
     */
    function test_SubmitProof_SucceedsWhenProofSystemConfigured() public {
        // Deploy and configure ProofSystem
        vm.startPrank(owner);
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(
            new ERC1967Proxy(address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ()))
        );
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // Configure ProofSystem in marketplace
        marketplace.setProofSystem(address(proofSystem));
        vm.stopPrank();

        // Verify ProofSystem is configured
        assertEq(address(marketplace.proofSystem()), address(proofSystem), "ProofSystem should be set");

        // Create a session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(host, MIN_PRICE_NATIVE, 1 hours, 100, 300);

        // Wait for some time so token rate limit passes
        vm.warp(block.timestamp + 1);

        // Generate valid signature
        bytes32 proofHash = keccak256("valid proof");

        // The host signs: keccak256(proofHash, prover, claimedTokens)
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, host, MIN_PROVEN_TOKENS));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Host submits valid proof - should succeed
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, signature, "QmProofCID", "QmDeltaCID");

        // Verify proof was recorded
        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, MIN_PROVEN_TOKENS, "Tokens should be recorded");
    }

    // ============================================================
    // Test: Session creation works without ProofSystem
    // ============================================================

    /**
     * @notice Verify session creation still works when ProofSystem is not configured
     * @dev ProofSystem is only needed for proof submission, not session creation
     */
    function test_SessionCreation_WorksWithoutProofSystem() public {
        // Verify ProofSystem is not configured
        assertEq(address(marketplace.proofSystem()), address(0), "ProofSystem should be address(0)");

        // Create session - should succeed even without ProofSystem
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(host, MIN_PRICE_NATIVE, 1 hours, 100, 300);

        // Verify session was created
        assertGt(sessionId, 0, "Session should be created");

        // Verify session details
        (uint256 id, address depositor, address sessionHost,,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(id, sessionId, "Session ID should match");
        assertEq(depositor, user, "Depositor should be user");
        assertEq(sessionHost, host, "Host should match");
    }
}
