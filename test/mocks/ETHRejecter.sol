// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title ETHRejecter - Simulates a contract that rejects ETH refunds
/// @notice Used in settlement pull pattern tests (GAP 1 / Finding #4)
contract ETHRejecter {
    // Reject all incoming ETH
    receive() external payable {
        revert("ETH rejected");
    }
}
