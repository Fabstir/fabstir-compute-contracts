// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract TestEOAIntegration is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ProofSystem public proofSystem;
    HostEarnings public hostEarnings;

    address public eoa_user = address(0x1111);
    address public eoa_host = address(0x2222);
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
            FEE_BASIS_POINTS,
            30);

        // Configure
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Fund EOA users
        vm.deal(eoa_user, 10 ether);
        vm.deal(eoa_host, 10 ether);
    }

    function test_EOA_FullFlow_DepositToWithdrawal() public {
        // 1. EOA deposits ETH
        vm.startPrank(eoa_user);
        marketplace.depositNative{value: 1 ether}();
        assertEq(marketplace.userDepositsNative(eoa_user), 1 ether);

        // 2. Create session from deposit
        uint256 sessionId = marketplace.createSessionFromDeposit(
            eoa_host,
            address(0), // native token
            0.5 ether,  // deposit amount
            0.0001 ether, // price per token
            1 days,
            10  // proof interval (10 * 10 = 100 tokens per proof)
        );
        assertEq(marketplace.userDepositsNative(eoa_user), 0.5 ether);

        // 3. Session is created and can be completed
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModels.SessionStatus.Active), "Session should be active");

        // 4. EOA withdraws remaining balance
        uint256 remainingBalance = marketplace.userDepositsNative(eoa_user);
        marketplace.withdrawNative(remainingBalance);
        assertEq(marketplace.userDepositsNative(eoa_user), 0);
        vm.stopPrank();
    }
}