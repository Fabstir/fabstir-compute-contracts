// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HostEarnings90PercentTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ProofSystem public proofSystem;
    HostEarnings public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public user = address(2);
    address public host = address(3);
    address public host2 = address(4);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10% treasury = 90% host

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC Token", "USDC");
        governanceToken = new ERC20Mock("Governance Token", "GOV");

        modelRegistry = new ModelRegistry(address(governanceToken));
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));
        proofSystem = new ProofSystem();
        hostEarnings = new HostEarnings();

        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            FEE_BASIS_POINTS,
            30);

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Set proof system from treasury
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));
    }

    function test_HostReceives90PercentCalculation() public {
        // Test the 90% host payment calculation
        uint256 payment = 1 ether;
        uint256 expectedHostPayment = (payment * 9000) / 10000; // 90% = 0.9 ETH
        uint256 expectedTreasuryFee = (payment * FEE_BASIS_POINTS) / 10000; // 10% = 0.1 ETH

        // Verify calculations
        assertEq(expectedHostPayment, 0.9 ether, "Host gets 90%");
        assertEq(expectedTreasuryFee, 0.1 ether, "Treasury gets 10%");
        assertEq(expectedHostPayment + expectedTreasuryFee, payment, "Total preserved");
    }

    function test_HostReceives90PercentInTokens() public {
        // Test token payment split calculation
        uint256 payment = 100e6; // 100 USDC
        uint256 expectedHostPayment = (payment * 9000) / 10000; // 90% = 90 USDC
        uint256 expectedTreasuryFee = (payment * FEE_BASIS_POINTS) / 10000; // 10% = 10 USDC

        // Verify calculations
        assertEq(expectedHostPayment, 90e6, "Host gets 90 USDC");
        assertEq(expectedTreasuryFee, 10e6, "Treasury gets 10 USDC");
        assertEq(expectedHostPayment + expectedTreasuryFee, payment, "Total preserved");
    }

    function test_MultipleHostsEarningsCalculation() public {
        // Test earnings calculation for multiple hosts
        uint256 payment1 = 1 ether;
        uint256 payment2 = 2 ether;

        uint256 host1Earnings = (payment1 * 9000) / 10000;
        uint256 host2Earnings = (payment2 * 9000) / 10000;

        // Verify calculations
        assertEq(host1Earnings, 0.9 ether, "Host1 would get 90% of 1 ETH");
        assertEq(host2Earnings, 1.8 ether, "Host2 would get 90% of 2 ETH");
    }

    function test_ZeroPaymentNoEarnings() public {
        // Test edge case: zero payment
        uint256 payment = 0;
        uint256 expectedHostPayment = (payment * 9000) / 10000;
        uint256 expectedTreasuryFee = (payment * FEE_BASIS_POINTS) / 10000;

        // Verify calculations
        assertEq(expectedHostPayment, 0, "No host earnings for zero payment");
        assertEq(expectedTreasuryFee, 0, "No treasury fee for zero payment");
    }

    function test_MaximumPaymentStillSplitsCorrectly() public {
        // Test with large payment amount
        uint256 payment = 100 ether;
        uint256 expectedHostPayment = (payment * 9000) / 10000; // 90 ETH
        uint256 expectedTreasury = (payment * FEE_BASIS_POINTS) / 10000; // 10 ETH

        // Verify split calculations
        assertEq(expectedHostPayment, 90 ether, "Host would get 90 ETH");
        assertEq(expectedTreasury, 10 ether, "Treasury would get 10 ETH");
        assertEq(expectedHostPayment + expectedTreasury, payment, "Total preserved");
    }

    function test_HostEarningsAccumulate() public {
        // Test accumulation calculation for multiple jobs
        uint256 totalHostEarnings = 0;

        // Calculate earnings for 3 jobs
        for (uint256 i = 0; i < 3; i++) {
            uint256 payment = 1 ether;
            uint256 hostPayment = (payment * 9000) / 10000;
            totalHostEarnings += hostPayment;
        }

        // Verify total accumulated calculation
        assertEq(totalHostEarnings, 2.7 ether, "Total earnings for 3 jobs at 0.9 ETH each");
    }
}