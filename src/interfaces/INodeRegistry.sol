// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface INodeRegistry {
    function isActiveNode(address operator) external view returns (bool);
    function getNodeController(address node) external view returns (address);
}