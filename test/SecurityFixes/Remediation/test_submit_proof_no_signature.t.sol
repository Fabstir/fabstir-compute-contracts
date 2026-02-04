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
 * @title submitProofOfWork No Signature Tests
 * @notice Tests for Sub-phase 2.1: Update submitProofOfWork Function
 *
 * AUDIT REMEDIATION: Remove signature parameter from submitProofOfWork
 * - submitProofOfWork now takes 5 parameters (was 6)
 * - Signature verification removed (redundant with msg.sender check)
 * - ProofSystem.markProofUsed() called for replay protection
 */
contract SubmitProofNoSignatureTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public user = address(0x3);
    address public attacker = address(0x4);

    bytes32 public modelId;
    uint256 public sessionId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PROVEN_TOKENS = 100;

    function setUp() public {
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

        // Configure ProofSystem in marketplace
        marketplace.setProofSystem(address(proofSystem));

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Authorize marketplace in ProofSystem
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host
        _registerHost(host);

        // Fund user
        vm.deal(user, 100 ether);
        vm.deal(host, 100 ether);

        // Create a session
        vm.prank(user);
        sessionId = marketplace.createSessionJob{value: 1 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        // Advance time for rate limit
        vm.warp(block.timestamp + 10);
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
    // Test: submitProofOfWork works without signature parameter (5 params)
    // ============================================================

    /**
     * @notice Verify submitProofOfWork works with 5 parameters (no signature)
     */
    function test_SubmitProof_WorksWithoutSignature() public {
        bytes32 proofHash = keccak256("test proof");
        uint256 tokensClaimed = 500;

        // Submit proof without signature (5 params instead of 6)
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmProofCID", "QmDeltaCID");

        // Verify proof was recorded
        (,,,,,, uint256 tokensUsed,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensClaimed, "Tokens should be recorded");
    }

    /**
     * @notice Verify multiple proof submissions work
     */
    function test_SubmitProof_MultipleProofs() public {
        // Use explicit timestamps to avoid block.timestamp caching issues
        uint256 baseTime = block.timestamp;

        for (uint256 i = 0; i < 3; i++) {
            // Advance time before each proof to satisfy rate limit
            // Need at least 1 second between proofs for 100 tokens at 2000 tokens/sec rate
            baseTime += 1;
            vm.warp(baseTime);

            bytes32 proofHash = keccak256(abi.encodePacked("proof", i));

            vm.prank(host);
            marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, "QmCID", "");
        }

        // Verify total tokens
        (,,,,,, uint256 tokensUsed,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, MIN_PROVEN_TOKENS * 3, "Total tokens should match");
    }

    // ============================================================
    // Test: Replay protection still works via ProofSystem
    // ============================================================

    /**
     * @notice Verify replay protection via ProofSystem.markProofUsed()
     */
    function test_ReplayProtection_Works() public {
        bytes32 proofHash = keccak256("replay test");

        // First submission succeeds
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, "QmCID", "");

        vm.warp(block.timestamp + 5);

        // Second submission with same hash should fail
        vm.prank(host);
        vm.expectRevert("Proof already used");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, "QmCID2", "");
    }

    /**
     * @notice Verify ProofSystem marks proofs as used
     */
    function test_ProofSystem_MarksProofsUsed() public {
        bytes32 proofHash = keccak256("marking test");

        // Initially not marked
        assertFalse(proofSystem.verifiedProofs(proofHash), "Should not be marked initially");

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, "QmCID", "");

        // Now marked
        assertTrue(proofSystem.verifiedProofs(proofHash), "Should be marked after submission");
    }

    // ============================================================
    // Test: msg.sender == host check still enforced
    // ============================================================

    /**
     * @notice Verify only host can submit proofs
     */
    function test_OnlyHost_CanSubmitProof() public {
        bytes32 proofHash = keccak256("host auth test");

        // Non-host cannot submit
        vm.prank(attacker);
        vm.expectRevert("Not host");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, "QmCID", "");

        // User cannot submit
        vm.prank(user);
        vm.expectRevert("Not host");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, "QmCID", "");

        // Host can submit
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, "QmCID", "");
    }

    // ============================================================
    // Test: ProofSystem not configured still works gracefully
    // ============================================================

    /**
     * @notice Verify proof submission fails when ProofSystem not configured
     */
    function test_ProofSystemNotSet_Reverts() public {
        // Deploy marketplace without ProofSystem
        vm.startPrank(owner);
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
        JobMarketplaceWithModelsUpgradeable noProofMarketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));
        hostEarnings.setAuthorizedCaller(address(noProofMarketplace), true);
        vm.stopPrank();

        // Create session
        vm.prank(user);
        uint256 newSessionId = noProofMarketplace.createSessionJob{value: 0.1 ether}(host, MIN_PRICE_NATIVE, 1 hours, 100, 300);

        vm.warp(block.timestamp + 5);

        // Proof submission should fail
        vm.prank(host);
        vm.expectRevert("ProofSystem not set");
        noProofMarketplace.submitProofOfWork(newSessionId, MIN_PROVEN_TOKENS, keccak256("test"), "QmCID", "");
    }

    // ============================================================
    // Test: ProofSubmission struct populated correctly
    // ============================================================

    /**
     * @notice Verify ProofSubmission includes correct data
     */
    function test_ProofSubmission_PopulatedCorrectly() public {
        bytes32 proofHash = keccak256("submission test");
        uint256 tokensClaimed = 500;
        string memory deltaCID = "QmDeltaCID123";

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmProofCID", deltaCID);

        // Get proof submission
        (
            bytes32 storedHash,
            uint256 storedTokens,
            uint256 timestamp,
            bool verified,
            string memory storedDeltaCID
        ) = marketplace.getProofSubmission(sessionId, 0);

        assertEq(storedHash, proofHash, "Hash should match");
        assertEq(storedTokens, tokensClaimed, "Tokens should match");
        assertGt(timestamp, 0, "Timestamp should be set");
        assertTrue(verified, "Should be verified");
        assertEq(storedDeltaCID, deltaCID, "DeltaCID should match");
    }

    // ============================================================
    // Test: Session state updated correctly
    // ============================================================

    /**
     * @notice Verify session state after proof submission
     */
    function test_SessionState_UpdatedCorrectly() public {
        bytes32 proofHash = keccak256("state test");
        uint256 tokensClaimed = 500;

        uint256 timeBefore = block.timestamp;

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmCID", "");

        // Check session state
        // SessionJob fields: id(1), depositor(2), host(3), paymentToken(4), deposit(5), pricePerToken(6),
        // tokensUsed(7), maxDuration(8), startTime(9), lastProofTime(10), proofInterval(11), proofTimeoutWindow(12),
        // status(13), withdrawnByHost(14), refundedToUser(15), conversationCID(16), lastProofHash(17), lastProofCID(18)
        (
            ,,,,,, // skip 1-6
            uint256 tokensUsed, // position 7
            ,, // skip 8-9
            uint256 lastProofTime, // position 10
            ,,,,,, // skip 11-16
            bytes32 lastProofHash, // position 17
             // skip 18
        ) = marketplace.sessionJobs(sessionId);

        assertEq(tokensUsed, tokensClaimed, "tokensUsed should match");
        assertEq(lastProofHash, proofHash, "lastProofHash should match");
        assertGe(lastProofTime, timeBefore, "lastProofTime should be updated");
    }
}
