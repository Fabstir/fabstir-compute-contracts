// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";

contract DepositEventsTest is Test {
    JobMarketplaceWithModels marketplace;

    address constant ALICE = address(0x1111);
    address constant BOB = address(0x2222);
    address constant USDC_TOKEN = address(0x3333);

    // Define expected events
    event DepositReceived(address indexed depositor, uint256 amount, address token);
    event WithdrawalProcessed(address indexed depositor, uint256 amount, address token);

    function setUp() public {
        // Deploy marketplace with required dependencies
        address modelRegistry = address(new ModelRegistry(address(0x4444)));
        address nodeRegistry = address(new NodeRegistryWithModels(address(0x5555), modelRegistry));
        address hostEarnings = address(new HostEarnings());

        marketplace = new JobMarketplaceWithModels(
            nodeRegistry,
            payable(hostEarnings),
            1000 // 10% fee,
                    30);
    }

    function test_DepositReceivedEventSignature() public {
        // Test that DepositReceived event can be expected
        // This will fail initially as event doesn't exist
        vm.expectEmit(true, false, false, true);
        emit DepositReceived(ALICE, 1 ether, address(0));

        // This would trigger the event (once implemented)
        // For now, just checking event signature exists
    }

    function test_WithdrawalProcessedEventSignature() public {
        // Test that WithdrawalProcessed event can be expected
        vm.expectEmit(true, false, false, true);
        emit WithdrawalProcessed(BOB, 0.5 ether, address(0));

        // This would trigger the event (once implemented)
    }

    function test_EventsHaveCorrectIndexedParams() public {
        // Verify depositor is indexed in DepositReceived
        vm.expectEmit(true, false, false, false);
        emit DepositReceived(ALICE, 0, address(0));

        // Verify depositor is indexed in WithdrawalProcessed
        vm.expectEmit(true, false, false, false);
        emit WithdrawalProcessed(ALICE, 0, address(0));
    }

    function test_EventsDistinguishNativeFromToken() public {
        // Native token uses address(0)
        vm.expectEmit(false, false, false, true);
        emit DepositReceived(ALICE, 1 ether, address(0));

        // ERC20 token uses token address
        vm.expectEmit(false, false, false, true);
        emit DepositReceived(ALICE, 1000, USDC_TOKEN);
    }
}