// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceMock} from "./mocks/JobMarketplaceMock.sol";
import {PaymentEscrowMock} from "./mocks/PaymentEscrowMock.sol";
import {NodeRegistryMock} from "./mocks/NodeRegistryMock.sol";
import {ReputationSystemMock} from "./mocks/ReputationSystemMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract TestSetup is Test {
    JobMarketplaceMock public jobMarketplace;
    PaymentEscrowMock public paymentEscrow;
    NodeRegistryMock public nodeRegistry;
    ReputationSystemMock public reputationSystem;
    ERC20Mock public token;
    
    address public client = address(0x1111);
    address public host1 = address(0x2222);
    address public host2 = address(0x3333);
    
    uint256 public jobId;
    
    function setUp() public virtual {
        // Deploy contracts
        nodeRegistry = new NodeRegistryMock();
        jobMarketplace = new JobMarketplaceMock();
        reputationSystem = new ReputationSystemMock();
        paymentEscrow = new PaymentEscrowMock();
        
        // Deploy mock token
        token = new ERC20Mock("Test Token", "TEST");
        
        // Fund test accounts
        vm.deal(client, 1000 ether);
        vm.deal(host1, 1000 ether);
        vm.deal(host2, 1000 ether);
        
        // Mint tokens
        token.mint(client, 10000e18);
        token.mint(host1, 10000e18);
        token.mint(host2, 10000e18);
    }
}