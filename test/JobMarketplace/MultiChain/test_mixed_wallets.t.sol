// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract SmartWallet {
    receive() external payable {}

    function callContract(address target, uint256 value, bytes calldata data) external returns (bool) {
        (bool success,) = target.call{value: value}(data);
        return success;
    }
}

contract TestMixedWallets is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    HostEarnings public hostEarnings;
    SmartWallet public smartWallet;

    address public eoaUser = address(0x4444);
    address public eoaHost = address(0x5555);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%

    function setUp() public {
        // Deploy contracts
        ERC20Mock fabToken = new ERC20Mock("FAB", "FAB");
        ERC20Mock govToken = new ERC20Mock("GOV", "GOV");
        ModelRegistry modelReg = new ModelRegistry(address(govToken));
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelReg));
        ProofSystem proofSys = new ProofSystem();
        hostEarnings = new HostEarnings();

        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            FEE_BASIS_POINTS,
            30);

        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSys));
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Deploy Smart Wallet
        smartWallet = new SmartWallet();

        // Fund accounts
        vm.deal(eoaUser, 5 ether);
        vm.deal(eoaHost, 5 ether);
        vm.deal(address(smartWallet), 5 ether);
    }

    function test_EOA_Creates_SmartWallet_Completes() public {
        // EOA creates session
        vm.prank(eoaUser);
        uint256 sessionId = marketplace.createSessionJob{value: 0.5 ether}(
            eoaHost, 0.001 ether, 1 days, 10
        );

        // Wait for dispute window
        vm.warp(block.timestamp + 1 hours + 1);

        // Smart Wallet completes session
        vm.prank(address(smartWallet));
        marketplace.completeSessionJob(sessionId, "ipfs://test");

        // Verify completed
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModels.SessionStatus.Completed), "Session should be completed");
    }

    function test_SmartWallet_Deposits_EOA_Uses() public {
        // Smart Wallet deposits
        bytes memory depositCall = abi.encodeWithSignature("depositNative()");
        smartWallet.callContract(address(marketplace), 2 ether, depositCall);

        assertEq(marketplace.userDepositsNative(address(smartWallet)), 2 ether);

        // Smart Wallet creates session
        vm.prank(address(smartWallet));
        uint256 sessionId = marketplace.createSessionFromDeposit(
            eoaHost, address(0), 1 ether, 0.001 ether, 1 days, 10
        );

        // Wait for dispute window
        vm.warp(block.timestamp + 1 hours + 1);

        // EOA host completes
        vm.prank(eoaHost);
        marketplace.completeSessionJob(sessionId, "ipfs://test");

        // Verify session completed successfully
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModels.SessionStatus.Completed), "Session should be completed");
    }

    function test_BackwardCompatibility_OldFunctions() public {
        // Test old createSessionJob still works
        vm.prank(eoaUser);
        uint256 sessionId = marketplace.createSessionJob{value: 0.3 ether}(
            eoaHost, 0.001 ether, 1 days, 10
        );

        // Wait for dispute window
        vm.warp(block.timestamp + 1 hours + 1);

        // Old pattern: specific user completes
        vm.prank(eoaUser);
        marketplace.completeSessionJob(sessionId, "ipfs://test");

        // Verify it worked
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModels.SessionStatus.Completed), "Session should be completed");
    }
}