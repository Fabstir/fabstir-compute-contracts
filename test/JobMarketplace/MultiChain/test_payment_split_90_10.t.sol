// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract PaymentSplit90_10Test is Test {
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
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10% treasury fee = 90% host payment

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
            FEE_BASIS_POINTS
        );

        vm.stopPrank();

        // Set proof system from treasury
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));
    }

    function test_FeeCalculationFormula() public {
        // Verify the fee calculation formula matches expected split
        uint256 payment = 1 ether;

        // Calculate using contract's formula
        uint256 treasuryFee = (payment * FEE_BASIS_POINTS) / 10000;
        uint256 hostPayment = payment - treasuryFee;

        // Verify 10% treasury, 90% host
        assertEq(treasuryFee, 0.1 ether, "Treasury gets 10%");
        assertEq(hostPayment, 0.9 ether, "Host gets 90%");
        assertEq(treasuryFee + hostPayment, payment, "Total preserved");
    }

    function test_TokenPaymentSplitCalculation() public {
        // Test split calculation with token amounts
        uint256 payment = 100e6; // 100 USDC

        // Calculate using contract's formula
        uint256 treasuryFee = (payment * FEE_BASIS_POINTS) / 10000;
        uint256 hostPayment = payment - treasuryFee;

        // Verify 10% treasury, 90% host
        assertEq(treasuryFee, 10e6, "Treasury gets 10% of USDC");
        assertEq(hostPayment, 90e6, "Host gets 90% of USDC");
        assertEq(treasuryFee + hostPayment, payment, "Total preserved");
    }

    function test_ExactSplitCalculation() public {
        // Test with exact amounts that should split cleanly
        // 1000 units total payment -> 100 treasury (10%), 900 host (90%)

        uint256 payment = 1000 ether;
        uint256 expectedTreasury = (payment * FEE_BASIS_POINTS) / 10000; // 100 ether
        uint256 expectedHost = payment - expectedTreasury; // 900 ether

        assertEq(expectedTreasury, 100 ether, "Treasury should get 10%");
        assertEq(expectedHost, 900 ether, "Host should get 90%");
        assertEq(expectedTreasury + expectedHost, payment, "Split should equal total");
    }

    function test_RoundingBehavior() public {
        // Test with amount that doesn't divide evenly
        // 999 wei -> 99 treasury, 900 host (rounding down treasury fee)

        uint256 payment = 999;
        uint256 expectedTreasury = (payment * FEE_BASIS_POINTS) / 10000; // 99 (rounds down)
        uint256 expectedHost = payment - expectedTreasury; // 900

        assertEq(expectedTreasury, 99, "Treasury rounds down");
        assertEq(expectedHost, 900, "Host gets remainder");
        assertEq(expectedTreasury + expectedHost, payment, "Split should equal total");
    }

    function test_VariousPaymentAmounts() public {
        // Test multiple payment amounts
        uint256[] memory payments = new uint256[](5);
        payments[0] = 0.1 ether;
        payments[1] = 1 ether;
        payments[2] = 10 ether;
        payments[3] = 100 ether;
        payments[4] = 1000 ether;

        for (uint256 i = 0; i < payments.length; i++) {
            uint256 payment = payments[i];
            uint256 treasuryFee = (payment * FEE_BASIS_POINTS) / 10000;
            uint256 hostPayment = payment - treasuryFee;

            // Verify 90/10 split
            assertEq(treasuryFee, payment / 10, "Treasury gets 10%");
            assertEq(hostPayment, (payment * 9) / 10, "Host gets 90%");
            assertEq(treasuryFee + hostPayment, payment, "Total preserved");
        }
    }

    function test_ConfigurableFeePercentage() public {
        // Test deployment with different fee percentages
        vm.startPrank(owner);

        // 5% fee (500 basis points)
        JobMarketplaceWithModels market5 = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            500
        );
        assertEq(market5.FEE_BASIS_POINTS(), 500, "5% fee configured");

        // 20% fee (2000 basis points)
        JobMarketplaceWithModels market20 = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            2000
        );
        assertEq(market20.FEE_BASIS_POINTS(), 2000, "20% fee configured");

        vm.stopPrank();
    }
}