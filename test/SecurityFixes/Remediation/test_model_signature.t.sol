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
 * @title Model Signature Tests (AUDIT-F4)
 * @notice Tests for Phase 4: Include modelId in signature verification
 *
 * Finding: AUDIT-F4
 * Slack Ref: slack-C0A61FZC8SH-p1769619714508749
 *
 * Issue: modelId is not included in the signed message, allowing potential
 * model mismatch attacks where a proof signed for one model could be used
 * for a different model session.
 *
 * Fix: Include modelId in the signed message hash. Non-model sessions use bytes32(0).
 */
contract ModelSignatureTest is Test {
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

    bytes32 public modelId1;
    bytes32 public modelId2;

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

        // Add two models for testing model mismatch
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelRegistry.addTrustedModel("Model2/Repo", "model2.gguf", bytes32(uint256(2)));
        modelId1 = modelRegistry.getModelId("Model1/Repo", "model1.gguf");
        modelId2 = modelRegistry.getModelId("Model2/Repo", "model2.gguf");

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

        // Register host with both models
        _registerHost(host);

        // Fund user
        vm.deal(user, 100 ether);
    }

    function _registerHost(address _host) internal {
        fabToken.mint(_host, MIN_STAKE);

        vm.startPrank(_host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId1;
        models[1] = modelId2;

        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    // ============================================================
    // Helper: Generate signature WITH modelId (new format)
    // ============================================================

    /**
     * @notice Generate signature that includes modelId in the signed message
     * @dev The host signs: keccak256(proofHash, prover, claimedTokens, modelId)
     */
    function _generateSignatureWithModel(
        bytes32 proofHash,
        address prover,
        uint256 tokensClaimed,
        bytes32 modelId
    ) internal view returns (bytes memory) {
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, prover, tokensClaimed, modelId));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @notice Generate signature WITHOUT modelId (old format - should fail after fix)
     */
    function _generateSignatureWithoutModel(
        bytes32 proofHash,
        address prover,
        uint256 tokensClaimed
    ) internal view returns (bytes memory) {
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, prover, tokensClaimed));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    // ============================================================
    // Test: ProofSystem verifyAndMarkComplete with modelId
    // ============================================================

    /**
     * @notice Valid signature with correct modelId should pass verification
     * @dev This test verifies the new signature scheme includes modelId
     */
    function test_Verify_ValidSignatureWithModelId() public {
        bytes32 proofHash = bytes32(uint256(1));
        uint256 tokensClaimed = 500;

        // Generate signature that includes modelId
        bytes memory signature = _generateSignatureWithModel(proofHash, host, tokensClaimed, modelId1);
        bytes memory proof = abi.encodePacked(proofHash, signature);

        // This call should pass - signature includes correct modelId
        // NOTE: This test will fail compilation until IProofSystem interface is updated
        bool result = proofSystem.verifyAndMarkComplete(proof, host, tokensClaimed, modelId1);
        assertTrue(result, "Valid signature with modelId should pass");
    }

    /**
     * @notice Valid signature with bytes32(0) for non-model session should pass
     * @dev Non-model sessions use bytes32(0) as modelId
     */
    function test_Verify_ValidSignatureWithZeroModelId() public {
        bytes32 proofHash = bytes32(uint256(2));
        uint256 tokensClaimed = 500;
        bytes32 zeroModelId = bytes32(0);

        // Generate signature with zero modelId (non-model session)
        bytes memory signature = _generateSignatureWithModel(proofHash, host, tokensClaimed, zeroModelId);
        bytes memory proof = abi.encodePacked(proofHash, signature);

        // This should pass for non-model sessions
        bool result = proofSystem.verifyAndMarkComplete(proof, host, tokensClaimed, zeroModelId);
        assertTrue(result, "Valid signature with zero modelId should pass");
    }

    /**
     * @notice Signature with wrong modelId should fail verification
     * @dev This prevents using a proof from one model session for another
     */
    function test_Verify_WrongModelId_Fails() public {
        bytes32 proofHash = bytes32(uint256(3));
        uint256 tokensClaimed = 500;

        // Generate signature with modelId1
        bytes memory signature = _generateSignatureWithModel(proofHash, host, tokensClaimed, modelId1);
        bytes memory proof = abi.encodePacked(proofHash, signature);

        // Try to verify with modelId2 - should fail
        bool result = proofSystem.verifyAndMarkComplete(proof, host, tokensClaimed, modelId2);
        assertFalse(result, "Signature with wrong modelId should fail");
    }

    /**
     * @notice Signature without modelId should fail (prevents downgrade attack)
     * @dev Old-format signatures (without modelId) should not work with new verification
     */
    function test_Verify_SignatureWithoutModelId_Fails() public {
        bytes32 proofHash = bytes32(uint256(4));
        uint256 tokensClaimed = 500;

        // Generate OLD format signature (without modelId)
        bytes memory signature = _generateSignatureWithoutModel(proofHash, host, tokensClaimed);
        bytes memory proof = abi.encodePacked(proofHash, signature);

        // Try to verify with modelId1 - should fail because signature doesn't include it
        bool result = proofSystem.verifyAndMarkComplete(proof, host, tokensClaimed, modelId1);
        assertFalse(result, "Old-format signature should fail with new verification");
    }

    /**
     * @notice Replay attack should fail
     */
    function test_Verify_ReplayAttack_Fails() public {
        bytes32 proofHash = bytes32(uint256(5));
        uint256 tokensClaimed = 500;

        bytes memory signature = _generateSignatureWithModel(proofHash, host, tokensClaimed, modelId1);
        bytes memory proof = abi.encodePacked(proofHash, signature);

        // First verification should succeed
        bool result1 = proofSystem.verifyAndMarkComplete(proof, host, tokensClaimed, modelId1);
        assertTrue(result1, "First verification should pass");

        // Replay should fail
        bool result2 = proofSystem.verifyAndMarkComplete(proof, host, tokensClaimed, modelId1);
        assertFalse(result2, "Replay attack should fail");
    }

    // ============================================================
    // Test: JobMarketplace passes modelId to ProofSystem
    // ============================================================

    /**
     * @notice submitProofOfWork should pass sessionModel to ProofSystem
     * @dev For model sessions, the modelId from sessionModel[jobId] should be passed
     */
    function test_SubmitProof_PassesSessionModelToProofSystem() public {
        // Create a model session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 0.01 ether}(
            host,
            modelId1,
            MIN_PRICE_NATIVE,
            1 hours,
            100, // proofInterval
            300  // proofTimeoutWindow
        );

        // Advance time
        vm.warp(block.timestamp + 1);

        // Generate signature that includes modelId1
        bytes32 proofHash = bytes32(uint256(100));
        uint256 tokensClaimed = 500;
        bytes memory signature = _generateSignatureWithModel(proofHash, host, tokensClaimed, modelId1);

        // Submit proof - this should work because signature includes correct modelId
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmProof", "");

        // Verify the proof was recorded
        (,,,,,, uint256 tokensUsed,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensClaimed, "Tokens should be recorded");
    }

    /**
     * @notice submitProofOfWork for non-model session should pass bytes32(0)
     * @dev Non-model sessions (created via createSessionJob) use bytes32(0) as modelId
     */
    function test_SubmitProof_NonModelSession_PassesZeroModelId() public {
        // Create a NON-model session (no modelId)
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 hours,
            100, // proofInterval
            300  // proofTimeoutWindow
        );

        // Verify sessionModel is bytes32(0) for non-model session
        bytes32 storedModel = marketplace.sessionModel(sessionId);
        assertEq(storedModel, bytes32(0), "Non-model session should have zero modelId");

        // Advance time
        vm.warp(block.timestamp + 1);

        // Generate signature with zero modelId
        bytes32 proofHash = bytes32(uint256(101));
        uint256 tokensClaimed = 500;
        bytes memory signature = _generateSignatureWithModel(proofHash, host, tokensClaimed, bytes32(0));

        // Submit proof - should work with zero modelId
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmProof", "");

        // Verify
        (,,,,,, uint256 tokensUsed,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensClaimed, "Tokens should be recorded");
    }

    /**
     * @notice submitProofOfWork with wrong modelId in signature should fail
     * @dev If host signs with different modelId, verification should fail
     */
    function test_SubmitProof_WrongModelInSignature_Fails() public {
        // Create a session for modelId1
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 0.01 ether}(
            host,
            modelId1,
            MIN_PRICE_NATIVE,
            1 hours,
            100,
            300
        );

        vm.warp(block.timestamp + 1);

        // Generate signature with WRONG modelId (modelId2 instead of modelId1)
        bytes32 proofHash = bytes32(uint256(102));
        uint256 tokensClaimed = 500;
        bytes memory signature = _generateSignatureWithModel(proofHash, host, tokensClaimed, modelId2);

        // Submit proof should fail - signature uses wrong modelId
        vm.prank(host);
        vm.expectRevert("Invalid proof signature");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmProof", "");
    }
}
