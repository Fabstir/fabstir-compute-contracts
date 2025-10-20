// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface IAccount {
    function execute(address dest, uint256 value, bytes calldata func) external;
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external;
}
