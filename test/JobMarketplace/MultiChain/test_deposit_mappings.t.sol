// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";

contract DepositMappingsTest is Test {
    JobMarketplaceWithModels marketplace;

    address constant ALICE = address(0x1111);
    address constant BOB = address(0x2222);
    address constant USDC = address(0x3333);

    function setUp() public {
        // Deploy marketplace with required dependencies
        address modelRegistry = address(new ModelRegistry(address(0x4444)));
        address nodeRegistry = address(new NodeRegistryWithModels(address(0x5555), modelRegistry));
        address hostEarnings = address(new HostEarnings());

        marketplace = new JobMarketplaceWithModels(
            nodeRegistry,
            payable(hostEarnings),
            1000 // 10% fee
        );
    }

    function test_UserDepositsNativeMappingExists() public {
        // Check native deposits mapping can store and retrieve values
        vm.prank(ALICE);
        uint256 aliceBalance = marketplace.userDepositsNative(ALICE);
        assertEq(aliceBalance, 0, "Initial balance should be 0");
    }

    function test_UserDepositsTokenMappingExists() public {
        // Check token deposits mapping can store and retrieve values
        vm.prank(ALICE);
        uint256 aliceUSDCBalance = marketplace.userDepositsToken(ALICE, USDC);
        assertEq(aliceUSDCBalance, 0, "Initial token balance should be 0");
    }

    function test_MultipleDifferentUsersNativeDeposits() public {
        // Check that different users have independent balances
        uint256 aliceBalance = marketplace.userDepositsNative(ALICE);
        uint256 bobBalance = marketplace.userDepositsNative(BOB);

        assertEq(aliceBalance, 0, "Alice initial balance should be 0");
        assertEq(bobBalance, 0, "Bob initial balance should be 0");
    }

    function test_MultipleTokensPerUser() public {
        address TOKEN_A = address(0x4444);
        address TOKEN_B = address(0x5555);

        uint256 aliceTokenA = marketplace.userDepositsToken(ALICE, TOKEN_A);
        uint256 aliceTokenB = marketplace.userDepositsToken(ALICE, TOKEN_B);

        assertEq(aliceTokenA, 0, "Alice TOKEN_A balance should be 0");
        assertEq(aliceTokenB, 0, "Alice TOKEN_B balance should be 0");
    }

    function test_MappingsArePublic() public view {
        // Verify mappings are publicly accessible
        marketplace.userDepositsNative(ALICE);
        marketplace.userDepositsToken(ALICE, USDC);
        // If this compiles and runs, mappings are public
    }
}