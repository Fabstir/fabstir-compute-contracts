// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface INodeRegistry {
    function isActiveNode(address operator) external view returns (bool);
}