// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/// @notice F202614998+F202614976: Proof submission without signature parameter
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
    address public nonHost = address(0x4);

    bytes32 public modelId;

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

        // Configure ProofSystem
        marketplace.setProofSystem(address(proofSystem));
        proofSystem.setAuthorizedCaller(address(marketplace), true);

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

    function _createSession() internal returns (uint256) {
        vm.prank(user);
        return marketplace.createSessionJob{value: 0.01 ether}(host, MIN_PRICE_NATIVE, 1 hours, 100, 300);
    }

    /// @notice F202614998+F202614976: Proof submission succeeds with new 5-param signature (no signature bytes)
    function test_SubmitProof_NoSignature_Succeeds() public {
        uint256 sessionId = _createSession();

        // Advance time so rate limit passes
        vm.warp(block.timestamp + 1);

        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            100,                      // tokensClaimed
            keccak256("proof1"),      // proofHash
            "QmCID",                  // proofCID
            "QmDelta"                 // deltaCID
        );

        // Verify proof was recorded
        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, 100);
    }

    /// @notice Only host can submit proof (msg.sender check preserved)
    function test_SubmitProof_OnlyHost_CanSubmit() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1);

        vm.prank(nonHost);
        vm.expectRevert("Not host");
        marketplace.submitProofOfWork(
            sessionId,
            100,
            keccak256("proof1"),
            "QmCID",
            "QmDelta"
        );
    }

    /// @notice Proof replay protection still works via ProofSystem.markProofUsed
    function test_SubmitProof_ReplayProtection() public {
        uint256 startTime = 1000;
        vm.warp(startTime);
        uint256 sessionId = _createSession();
        vm.warp(startTime + 1);

        bytes32 proofHash = keccak256("proof1");

        // First submission succeeds
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 100, proofHash, "QmCID1", "QmDelta1");

        // Advance time for rate limit
        vm.warp(startTime + 2);

        // Same proofHash should fail (replay)
        vm.prank(host);
        vm.expectRevert("Proof already used");
        marketplace.submitProofOfWork(sessionId, 100, proofHash, "QmCID2", "QmDelta2");
    }

    /// @notice Multiple unique proofs succeed sequentially
    function test_SubmitProof_MultipleUniqueProofs() public {
        uint256 startTime = 1000;
        vm.warp(startTime);
        uint256 sessionId = _createSession();

        // First proof
        vm.warp(startTime + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 100, keccak256("proof1"), "QmCID1", "QmDelta1");

        // Second proof
        vm.warp(startTime + 2);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 100, keccak256("proof2"), "QmCID2", "QmDelta2");

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, 200);
    }

    /// @notice ProofSubmitted event emits correctly with new parameters
    function test_SubmitProof_EmitsEvent() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1);

        bytes32 proofHash = keccak256("proof1");

        vm.prank(host);
        vm.expectEmit(true, true, false, true);
        emit JobMarketplaceWithModelsUpgradeable.ProofSubmitted(
            sessionId, host, 100, proofHash, "QmCID", "QmDelta"
        );
        marketplace.submitProofOfWork(sessionId, 100, proofHash, "QmCID", "QmDelta");
    }
}
