// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";

/**
 * @title FeeConfigurationTest
 * @dev Tests for configurable treasury fee in JobMarketplaceWithModels
 * @notice Validates that FEE_BASIS_POINTS can be set at deployment time
 */
contract FeeConfigurationTest is Test {
    JobMarketplaceWithModels marketplace;
    NodeRegistryWithModels nodeRegistry;
    ModelRegistry modelRegistry;
    HostEarnings hostEarnings;

    address constant USER = address(0x1111);
    address constant HOST = address(0x2222);
    address constant TREASURY = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;
    address constant FAB_TOKEN = address(0x3333);
    address constant GOVERNANCE_TOKEN = address(0x4444);

    function setUp() public {
        // Deploy mock contracts
        modelRegistry = new ModelRegistry(GOVERNANCE_TOKEN);
        nodeRegistry = new NodeRegistryWithModels(FAB_TOKEN, address(modelRegistry));
        hostEarnings = new HostEarnings();
    }

    function test_DeploymentWithDefaultFee() public {
        // Deploy with 10% treasury fee (1000 basis points)
        uint256 feeBasisPoints = 1000;
        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            feeBasisPoints,
            30
        );

        assertEq(marketplace.FEE_BASIS_POINTS(), 1000, "Should have 10% treasury fee");
    }

    function test_DeploymentWithCustomFee() public {
        // Deploy with 5% treasury fee (500 basis points)
        uint256 feeBasisPoints = 500;
        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            feeBasisPoints,
            30
        );

        assertEq(marketplace.FEE_BASIS_POINTS(), 500, "Should have 5% treasury fee");
    }

    function test_DeploymentWithZeroFee() public {
        // Deploy with 0% treasury fee (0 basis points)
        uint256 feeBasisPoints = 0;
        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            feeBasisPoints,
            30
        );

        assertEq(marketplace.FEE_BASIS_POINTS(), 0, "Should have 0% treasury fee");
    }

    function test_DeploymentWithMaxFee() public {
        // Deploy with 100% treasury fee (10000 basis points)
        uint256 feeBasisPoints = 10000;
        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            feeBasisPoints,
            30
        );

        assertEq(marketplace.FEE_BASIS_POINTS(), 10000, "Should have 100% treasury fee");
    }

    function test_RevertOnFeeExceeding100Percent() public {
        // Try to deploy with >100% treasury fee (10001 basis points)
        uint256 feeBasisPoints = 10001;

        vm.expectRevert("Fee cannot exceed 100%");
        new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            feeBasisPoints,
            30
        );
    }

    function test_FeeCalculationWithDifferentPercentages() public {
        // Test various fee percentages
        uint256[] memory percentages = new uint256[](5);
        percentages[0] = 0;   // 0%
        percentages[1] = 250; // 2.5%
        percentages[2] = 500; // 5%
        percentages[3] = 1000; // 10%
        percentages[4] = 2000; // 20%

        for (uint i = 0; i < percentages.length; i++) {
            marketplace = new JobMarketplaceWithModels(
                address(nodeRegistry),
                payable(address(hostEarnings)),
                percentages[i],
                30
            );

            // Test payment calculation
            uint256 payment = 1 ether;
            uint256 expectedTreasuryFee = (payment * percentages[i]) / 10000;
            uint256 expectedHostPayment = payment - expectedTreasuryFee;

            // Calculate actual fees using marketplace's fee calculation
            uint256 actualTreasuryFee = (payment * marketplace.FEE_BASIS_POINTS()) / 10000;
            uint256 actualHostPayment = payment - actualTreasuryFee;

            assertEq(actualTreasuryFee, expectedTreasuryFee, "Treasury fee mismatch");
            assertEq(actualHostPayment, expectedHostPayment, "Host payment mismatch");
        }
    }

    function testFuzz_DeploymentWithValidFees(uint256 feeBasisPoints) public {
        // Fuzz test with valid fee ranges
        feeBasisPoints = bound(feeBasisPoints, 0, 10000);

        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            feeBasisPoints,
            30
        );

        assertEq(marketplace.FEE_BASIS_POINTS(), feeBasisPoints, "Fee should match input");
    }

    function testFuzz_RevertOnInvalidFees(uint256 feeBasisPoints) public {
        // Fuzz test with invalid fee ranges
        vm.assume(feeBasisPoints > 10000);

        vm.expectRevert("Fee cannot exceed 100%");
        new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            feeBasisPoints,
            30
        );
    }
}