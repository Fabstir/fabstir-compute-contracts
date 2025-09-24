// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

// Simple Smart Account mock
contract SmartAccountMock {
    receive() external payable {}

    function execute(address target, uint256 value, bytes calldata data) external payable returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "Smart Account execution failed");
        return result;
    }
}

contract TestSmartAccountIntegration is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ProofSystem public proofSystem;
    HostEarnings public hostEarnings;
    SmartAccountMock public smartAccount;

    address public host = address(0x3333);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%

    function setUp() public {
        // Deploy contracts
        ERC20Mock fabToken = new ERC20Mock("FAB", "FAB");
        ERC20Mock govToken = new ERC20Mock("GOV", "GOV");
        modelRegistry = new ModelRegistry(address(govToken));
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));
        proofSystem = new ProofSystem();
        hostEarnings = new HostEarnings();

        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            FEE_BASIS_POINTS
        );

        // Configure
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Deploy Smart Account
        smartAccount = new SmartAccountMock();
        vm.deal(address(smartAccount), 10 ether);
        vm.deal(host, 1 ether);
    }

    function test_SmartAccount_GaslessEnding() public {
        // 1. Smart Account deposits through execute
        bytes memory depositCall = abi.encodeWithSignature("depositNative()");
        smartAccount.execute(address(marketplace), 2 ether, depositCall);
        assertEq(marketplace.userDepositsNative(address(smartAccount)), 2 ether);

        // 2. Smart Account creates session
        bytes memory createCall = abi.encodeWithSignature(
            "createSessionFromDeposit(address,address,uint256,uint256,uint256,uint256)",
            host, address(0), 1 ether, 0.001 ether, 1 days, 100
        );
        smartAccount.execute(address(marketplace), 0, createCall);

        // 3. Verify session created successfully
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,) = marketplace.sessionJobs(1);
        assertEq(uint256(status), uint256(JobMarketplaceWithModels.SessionStatus.Active), "Session should be active");

        // 4. Verify Smart Account balance updated correctly
        assertEq(marketplace.userDepositsNative(address(smartAccount)), 1 ether);
    }

    function test_SmartAccount_AnyoneCanComplete() public {
        // Create session directly with Smart Account
        vm.prank(address(smartAccount));
        uint256 sessionId = marketplace.createSessionJob{value: 0.5 ether}(
            host, 0.001 ether, 1 days, 10
        );

        // Random address completes (not user, not host)
        address randomCompleter = address(0x9999);

        // Wait for dispute window
        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(randomCompleter);
        marketplace.completeSessionJob(sessionId, "ipfs://test");

        // Verify session completed
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModels.SessionStatus.Completed), "Session should be completed");
    }
}