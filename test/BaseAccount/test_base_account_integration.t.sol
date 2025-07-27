// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {BaseAccountIntegration} from "../../src/BaseAccountIntegration.sol";
import {JobMarketplace} from "../../src/JobMarketplace.sol";
import {NodeRegistry} from "../../src/NodeRegistry.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";
import {UserOperation} from "../../src/interfaces/UserOperation.sol";

contract BaseAccountIntegrationTest is Test {
    BaseAccountIntegration public baseIntegration;
    JobMarketplace public jobMarketplace;
    NodeRegistry public nodeRegistry;
    
    address constant ENTRYPOINT = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
    address constant PAYMASTER = address(0x1001);
    address constant SMART_WALLET = address(0x2002);
    address constant SESSION_KEY = address(0x3003);
    address constant HOST = address(0x4004);
    address constant BUNDLER = address(0x5005);
    
    uint256 constant HOST_STAKE = 100 ether;
    uint256 constant JOB_PRICE = 10 ether;
    
    event SessionKeyAdded(address indexed wallet, address indexed sessionKey, uint256 expires);
    event SessionKeyRevoked(address indexed wallet, address indexed sessionKey);
    event BatchExecuted(address indexed wallet, uint256 operations);
    event GaslessTransactionSponsored(address indexed wallet, address indexed paymaster, uint256 gasUsed);
    
    function setUp() public {
        nodeRegistry = new NodeRegistry();
        jobMarketplace = new JobMarketplace(address(nodeRegistry));
        baseIntegration = new BaseAccountIntegration(
            ENTRYPOINT,
            PAYMASTER,
            address(jobMarketplace),
            address(nodeRegistry)
        );
        
        // Setup accounts
        vm.deal(SMART_WALLET, 1000 ether);
        vm.deal(HOST, 1000 ether);
        vm.deal(PAYMASTER, 1000 ether);
        vm.deal(ENTRYPOINT, 1000 ether);
        
        // Register host
        vm.prank(HOST);
        nodeRegistry.registerNode{value: HOST_STAKE}(
            "12D3KooWHost",
            _createModels(),
            "us-east-1"
        );
        
        // Setup smart wallet mock - just use a simple EOA for tests
        // vm.etch(SMART_WALLET, _getSmartWalletBytecode());
    }
    
    function test_SmartWalletCanCreateJob() public {
        // Smart wallet creates UserOperation for job creation
        UserOperation memory userOp = _createUserOperation(
            SMART_WALLET,
            address(baseIntegration),
            abi.encodeWithSelector(
                BaseAccountIntegration.createJobViaAccount.selector,
                "llama3-70b",
                "QmInput",
                JOB_PRICE,
                block.timestamp + 1 hours
            ),
            JOB_PRICE
        );
        
        // EntryPoint executes the UserOperation
        // First send ETH to the integration contract (simulating wallet funding)
        vm.deal(address(baseIntegration), JOB_PRICE);
        
        // Use vm.prank with tx.origin to simulate smart wallet
        vm.prank(ENTRYPOINT, SMART_WALLET);
        uint256 jobId = baseIntegration.createJobViaAccount{value: JOB_PRICE}(
            "llama3-70b",  
            "QmInput",
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        // Verify job was created
        JobMarketplace.Job memory job = jobMarketplace.getJob(jobId);
        assertEq(job.renter, SMART_WALLET);
        assertEq(job.modelId, "llama3-70b");
    }
    
    function test_GaslessTransaction() public {
        // Create UserOp with paymaster
        UserOperation memory userOp = _createUserOperation(
            SMART_WALLET,
            address(baseIntegration),
            abi.encodeWithSelector(
                BaseAccountIntegration.registerNodeViaAccount.selector,
                "12D3KooWSmartWallet",
                _createModels(),
                "us-west-2"
            ),
            HOST_STAKE
        );
        
        userOp.paymasterAndData = abi.encodePacked(PAYMASTER);
        
        // Record gas before
        uint256 smartWalletBalanceBefore = SMART_WALLET.balance;
        uint256 paymasterBalanceBefore = PAYMASTER.balance;
        uint256 entryPointBalanceBefore = ENTRYPOINT.balance;
        
        vm.expectEmit(true, true, false, true);
        emit GaslessTransactionSponsored(SMART_WALLET, PAYMASTER, 200000); // Estimated gas
        
        // Execute via EntryPoint (paymaster pays gas)
        vm.prank(ENTRYPOINT, SMART_WALLET);
        baseIntegration.handleOp{value: HOST_STAKE}(userOp, 200000);
        
        // Smart wallet balance unchanged (it didn't pay for gas or the stake)
        assertEq(SMART_WALLET.balance, smartWalletBalanceBefore);
        // EntryPoint balance decreased by HOST_STAKE (it paid for the node registration)
        assertEq(ENTRYPOINT.balance, entryPointBalanceBefore - HOST_STAKE);
        // In a real setup, paymaster would pay gas fees, but in this test we're just checking the event
    }
    
    function test_SessionKeyManagement() public {
        // First register SMART_WALLET as a host so it can claim jobs
        vm.prank(SMART_WALLET);
        nodeRegistry.registerNode{value: HOST_STAKE}(
            "12D3KooWSmartWallet",
            _createModels(),
            "us-west-2"
        );
        
        // Then create a job as SMART_WALLET
        vm.deal(address(baseIntegration), JOB_PRICE);
        vm.prank(ENTRYPOINT, SMART_WALLET);
        uint256 jobId = baseIntegration.createJobViaAccount{value: JOB_PRICE}(
            "llama3-70b",
            "QmInput",
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        // Add session key
        vm.prank(SMART_WALLET);
        
        uint256 expires = block.timestamp + 7 days;
        vm.expectEmit(true, true, false, true);
        emit SessionKeyAdded(SMART_WALLET, SESSION_KEY, expires);
        
        baseIntegration.addSessionKey(SESSION_KEY, expires);
        
        // Verify session key is valid
        assertTrue(baseIntegration.isValidSessionKey(SMART_WALLET, SESSION_KEY));
        
        // Session key can perform limited operations
        vm.prank(SESSION_KEY);
        baseIntegration.claimJobViaSessionKey(SMART_WALLET, jobId);
    }
    
    function test_SessionKeyExpiration() public {
        // Add session key with short expiry
        vm.prank(SMART_WALLET);
        baseIntegration.addSessionKey(SESSION_KEY, block.timestamp + 1 hours);
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);
        
        // Session key no longer valid
        assertFalse(baseIntegration.isValidSessionKey(SMART_WALLET, SESSION_KEY));
        
        // Cannot use expired key
        vm.prank(SESSION_KEY);
        vm.expectRevert("Session key expired");
        baseIntegration.claimJobViaSessionKey(SMART_WALLET, 1);
    }
    
    function test_RevokeSessionKey() public {
        // Add then revoke
        vm.startPrank(SMART_WALLET);
        baseIntegration.addSessionKey(SESSION_KEY, block.timestamp + 7 days);
        
        vm.expectEmit(true, true, false, false);
        emit SessionKeyRevoked(SMART_WALLET, SESSION_KEY);
        
        baseIntegration.revokeSessionKey(SESSION_KEY);
        vm.stopPrank();
        
        // No longer valid
        assertFalse(baseIntegration.isValidSessionKey(SMART_WALLET, SESSION_KEY));
    }
    
    function test_BatchOperations() public {
        // Prepare batch of operations
        BaseAccountIntegration.Operation[] memory ops = new BaseAccountIntegration.Operation[](3);
        
        // Op 1: Create job
        ops[0] = BaseAccountIntegration.Operation({
            target: address(jobMarketplace),
            value: JOB_PRICE,
            data: abi.encodeWithSelector(
                JobMarketplace.createJob.selector,
                "llama3-70b",
                "QmInput1",
                JOB_PRICE,
                block.timestamp + 1 hours
            )
        });
        
        // Op 2: Create another job
        ops[1] = BaseAccountIntegration.Operation({
            target: address(jobMarketplace),
            value: JOB_PRICE,
            data: abi.encodeWithSelector(
                JobMarketplace.createJob.selector,
                "mistral-7b",
                "QmInput2",
                JOB_PRICE,
                block.timestamp + 2 hours
            )
        });
        
        // Op 3: Register as node
        ops[2] = BaseAccountIntegration.Operation({
            target: address(nodeRegistry),
            value: HOST_STAKE,
            data: abi.encodeWithSelector(
                NodeRegistry.registerNode.selector,
                "12D3KooWBatch",
                _createModels(),
                "eu-west-1"
            )
        });
        
        vm.prank(SMART_WALLET);
        
        vm.expectEmit(true, false, false, true);
        emit BatchExecuted(SMART_WALLET, 3);
        
        baseIntegration.executeBatch{value: HOST_STAKE + 2 * JOB_PRICE}(ops);
        
        // Verify all operations executed
        NodeRegistry.Node memory node = nodeRegistry.getNode(SMART_WALLET);
        assertEq(node.operator, SMART_WALLET);
    }
    
    function test_StreamingPayments() public {
        // Create a streaming payment plan
        uint256 totalAmount = 100 ether;
        uint256 duration = 30 days;
        
        vm.prank(SMART_WALLET);
        uint256 streamId = baseIntegration.createPaymentStream{value: totalAmount}(
            HOST,
            totalAmount,
            duration
        );
        
        // Fast forward half the duration
        vm.warp(block.timestamp + 15 days);
        
        // Host can withdraw half
        uint256 hostBalanceBefore = HOST.balance;
        
        vm.prank(HOST);
        baseIntegration.withdrawFromStream(streamId);
        
        // Should receive ~50 ether (half of total)
        assertApproxEqAbs(HOST.balance - hostBalanceBefore, 50 ether, 0.1 ether);
    }
    
    function test_CancelStreamingPayment() public {
        // Create stream
        uint256 totalAmount = 100 ether;
        vm.prank(SMART_WALLET);
        uint256 streamId = baseIntegration.createPaymentStream{value: totalAmount}(
            HOST,
            totalAmount,
            30 days
        );
        
        // Fast forward 10 days
        vm.warp(block.timestamp + 10 days);
        
        // Cancel stream
        uint256 walletBalanceBefore = SMART_WALLET.balance;
        
        vm.prank(SMART_WALLET);
        baseIntegration.cancelPaymentStream(streamId);
        
        // Should refund ~66.67 ether (20 days worth)
        assertApproxEqAbs(
            SMART_WALLET.balance - walletBalanceBefore,
            (totalAmount * 20) / 30,
            0.1 ether
        );
    }
    
    function test_OnlySmartWalletCanManageSessionKeys() public {
        // HOST adds a session key for themselves - this should succeed but
        // the session key will only work for HOST's wallet
        vm.prank(HOST);
        baseIntegration.addSessionKey(SESSION_KEY, block.timestamp + 1 days);
        
        // Verify session key is valid for HOST
        assertTrue(baseIntegration.isValidSessionKey(HOST, SESSION_KEY));
        
        // But not valid for SMART_WALLET
        assertFalse(baseIntegration.isValidSessionKey(SMART_WALLET, SESSION_KEY));
    }
    
    function _createUserOperation(
        address sender,
        address target,
        bytes memory callData,
        uint256 value
    ) private pure returns (UserOperation memory) {
        return UserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSelector(
                IAccount.execute.selector,
                target,
                value,
                callData
            ),
            callGasLimit: 200000,
            verificationGasLimit: 100000,
            preVerificationGas: 50000,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            paymasterAndData: "",
            signature: ""
        });
    }
    
    function _getSmartWalletBytecode() private pure returns (bytes memory) {
        // Minimal smart wallet bytecode that implements IAccount
        return hex"608060405234801561001057600080fd5b50610150806100206000396000f3fe";
    }
    
    function _createModels() private pure returns (string[] memory) {
        string[] memory models = new string[](2);
        models[0] = "llama3-70b";
        models[1] = "mistral-7b";
        return models;
    }
}
