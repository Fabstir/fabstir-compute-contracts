// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPaymentEscrow {
    function grantRole(bytes32 role, address account) external;
    function PROOF_SYSTEM_ROLE() external view returns (bytes32);
    
    function createEscrow(
        bytes32 _jobId,
        address _host,
        uint256 _amount,
        address _token
    ) external payable;
    
    function releaseEscrow(bytes32 _jobId) external;
}