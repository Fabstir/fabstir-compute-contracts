// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAccount {
    function execute(address dest, uint256 value, bytes calldata func) external;
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external;
}
