// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPaymentEscrow {
    function grantRole(bytes32 role, address account) external;
    function PROOF_SYSTEM_ROLE() external view returns (bytes32);
}