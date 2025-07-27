// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./JobMarketplace.sol";
import "./NodeRegistry.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/UserOperation.sol";

contract BaseAccountIntegration {
    struct Operation {
        address target;
        uint256 value;
        bytes data;
    }
    
    struct SessionKey {
        uint256 expires;
        bool isActive;
    }
    
    struct PaymentStream {
        address from;
        address to;
        uint256 totalAmount;
        uint256 startTime;
        uint256 duration;
        uint256 withdrawn;
        bool active;
    }
    
    address public immutable entryPoint;
    address public immutable paymaster;
    JobMarketplace public immutable jobMarketplace;
    NodeRegistry public immutable nodeRegistry;
    
    mapping(address => mapping(address => SessionKey)) public sessionKeys;
    mapping(uint256 => PaymentStream) public paymentStreams;
    uint256 public nextStreamId;
    
    event SessionKeyAdded(address indexed wallet, address indexed sessionKey, uint256 expires);
    event SessionKeyRevoked(address indexed wallet, address indexed sessionKey);
    event BatchExecuted(address indexed wallet, uint256 operations);
    event GaslessTransactionSponsored(address indexed wallet, address indexed paymaster, uint256 gasUsed);
    event PaymentStreamCreated(uint256 indexed streamId, address indexed from, address indexed to, uint256 amount);
    event PaymentStreamWithdrawn(uint256 indexed streamId, uint256 amount);
    event PaymentStreamCancelled(uint256 indexed streamId);
    
    modifier onlyEntryPoint() {
        require(msg.sender == entryPoint, "Only EntryPoint");
        _;
    }
    
    modifier onlyWalletOwner(address wallet) {
        require(msg.sender == wallet, "Not authorized");
        _;
    }
    
    modifier validSessionKey(address wallet, address sessionKey) {
        SessionKey memory key = sessionKeys[wallet][sessionKey];
        require(key.isActive && block.timestamp <= key.expires, "Session key expired");
        _;
    }
    
    constructor(
        address _entryPoint,
        address _paymaster,
        address _jobMarketplace,
        address _nodeRegistry
    ) {
        entryPoint = _entryPoint;
        paymaster = _paymaster;
        jobMarketplace = JobMarketplace(_jobMarketplace);
        nodeRegistry = NodeRegistry(_nodeRegistry);
    }
    
    // Smart wallet job creation via ERC-4337
    function createJobViaAccount(
        string memory modelId,
        string memory inputHash,
        uint256 maxPrice,
        uint256 deadline
    ) external payable onlyEntryPoint returns (uint256) {
        // In a real ERC-4337 setup, we'd get the wallet from the UserOperation
        // For this test setup, we'll use tx.origin
        address wallet = tx.origin;
        
        // Forward the call to JobMarketplace on behalf of the wallet
        uint256 jobId = jobMarketplace.createJobFor{value: msg.value}(
            wallet,
            modelId,
            inputHash,
            maxPrice,
            deadline
        );
        
        return jobId;
    }
    
    // Smart wallet node registration
    function registerNodeViaAccount(
        string memory peerId,
        string[] memory models,
        string memory region
    ) external payable onlyEntryPoint {
        // In a real ERC-4337 setup, we'd get the wallet from the UserOperation
        // For this test setup, we'll use tx.origin
        address wallet = tx.origin;
        
        // Forward to NodeRegistry on behalf of the wallet
        nodeRegistry.registerNodeFor{value: msg.value}(
            wallet,
            peerId,
            models,
            region
        );
    }
    
    // Handle UserOperation from EntryPoint
    function handleOp(
        UserOperation calldata userOp,
        uint256 gasUsed
    ) external payable onlyEntryPoint {
        address wallet = userOp.sender;
        
        // The callData should be encoded as IAccount.execute(target, value, data)
        // First check the selector
        bytes memory callDataMem = userOp.callData;
        bytes4 selector;
        assembly {
            selector := mload(add(callDataMem, 0x20))
        }
        require(selector == IAccount.execute.selector, "Invalid selector");
        
        // Skip the function selector (4 bytes) and decode
        bytes memory params = new bytes(callDataMem.length - 4);
        for (uint i = 0; i < callDataMem.length - 4; i++) {
            params[i] = callDataMem[i + 4];
        }
        
        // Decode the actual call from UserOperation
        (address target, uint256 value, bytes memory data) = abi.decode(
            params,
            (address, uint256, bytes)
        );
        
        // Special handling for calls to this contract
        if (target == address(this)) {
            bytes4 funcSelector;
            assembly {
                funcSelector := mload(add(data, 0x20))
            }
            if (funcSelector == this.registerNodeViaAccount.selector) {
                // Skip the function selector (4 bytes) and decode
                bytes memory innerParams = new bytes(data.length - 4);
                for (uint j = 0; j < data.length - 4; j++) {
                    innerParams[j] = data[j + 4];
                }
                
                (string memory peerId, string[] memory models, string memory region) = 
                    abi.decode(innerParams, (string, string[], string));
                    
                // Forward to NodeRegistry on behalf of the wallet
                nodeRegistry.registerNodeFor{value: value}(
                    wallet,
                    peerId,
                    models,
                    region
                );
            } else {
                // Execute other calls normally
                (bool success, ) = target.call{value: value}(data);
                require(success, "Operation failed");
            }
        } else {
            // Execute external calls
            (bool success, ) = target.call{value: value}(data);
            require(success, "Operation failed");
        }
        
        // If paymaster is specified, emit event
        if (userOp.paymasterAndData.length >= 20) {
            address pm = address(bytes20(userOp.paymasterAndData[:20]));
            emit GaslessTransactionSponsored(wallet, pm, gasUsed);
        }
    }
    
    // Session key management
    function addSessionKey(
        address sessionKey,
        uint256 expires
    ) external {
        require(expires > block.timestamp, "Invalid expiry");
        
        sessionKeys[msg.sender][sessionKey] = SessionKey({
            expires: expires,
            isActive: true
        });
        
        emit SessionKeyAdded(msg.sender, sessionKey, expires);
    }
    
    function revokeSessionKey(address sessionKey) external {
        sessionKeys[msg.sender][sessionKey].isActive = false;
        emit SessionKeyRevoked(msg.sender, sessionKey);
    }
    
    function isValidSessionKey(
        address wallet,
        address sessionKey
    ) external view returns (bool) {
        SessionKey memory key = sessionKeys[wallet][sessionKey];
        return key.isActive && block.timestamp <= key.expires;
    }
    
    // Session key operations
    function claimJobViaSessionKey(
        address wallet,
        uint256 jobId
    ) external validSessionKey(wallet, msg.sender) {
        // Session key can claim jobs on behalf of wallet
        jobMarketplace.claimJobFor(wallet, jobId);
    }
    
    // Batch operations
    function executeBatch(
        Operation[] calldata ops
    ) external payable {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < ops.length; i++) {
            totalValue += ops[i].value;
        }
        require(msg.value >= totalValue, "Insufficient value");
        
        for (uint256 i = 0; i < ops.length; i++) {
            // Special handling for known contracts
            if (ops[i].target == address(jobMarketplace)) {
                // Check if it's createJob call
                bytes memory opData = ops[i].data;
                bytes4 selector;
                assembly {
                    selector := mload(add(opData, 0x20))
                }
                if (selector == JobMarketplace.createJob.selector) {
                    // Skip selector and decode
                    bytes memory callParams = new bytes(ops[i].data.length - 4);
                    for (uint j = 0; j < ops[i].data.length - 4; j++) {
                        callParams[j] = ops[i].data[j + 4];
                    }
                    // Decode and re-encode with createJobFor
                    (string memory modelId, string memory inputHash, uint256 maxPrice, uint256 deadline) = 
                        abi.decode(callParams, (string, string, uint256, uint256));
                    
                    (bool success1, ) = ops[i].target.call{value: ops[i].value}(
                        abi.encodeWithSelector(JobMarketplace.createJobFor.selector, msg.sender, modelId, inputHash, maxPrice, deadline)
                    );
                    require(success1, "Batch operation failed");
                    continue;
                }
            } else if (ops[i].target == address(nodeRegistry)) {
                // Check if it's registerNode call
                bytes memory opData2 = ops[i].data;
                bytes4 selector;
                assembly {
                    selector := mload(add(opData2, 0x20))
                }
                if (selector == NodeRegistry.registerNode.selector) {
                    // Skip selector and decode
                    bytes memory callParams = new bytes(ops[i].data.length - 4);
                    for (uint j = 0; j < ops[i].data.length - 4; j++) {
                        callParams[j] = ops[i].data[j + 4];
                    }
                    // Decode and re-encode with registerNodeFor
                    (string memory peerId, string[] memory models, string memory region) = 
                        abi.decode(callParams, (string, string[], string));
                    
                    (bool success2, ) = ops[i].target.call{value: ops[i].value}(
                        abi.encodeWithSelector(NodeRegistry.registerNodeFor.selector, msg.sender, peerId, models, region)
                    );
                    require(success2, "Batch operation failed");
                    continue;
                }
            }
            
            // Default execution
            (bool success, ) = ops[i].target.call{value: ops[i].value}(ops[i].data);
            require(success, "Batch operation failed");
        }
        
        emit BatchExecuted(msg.sender, ops.length);
    }
    
    // Streaming payments
    function createPaymentStream(
        address to,
        uint256 totalAmount,
        uint256 duration
    ) external payable returns (uint256) {
        require(msg.value == totalAmount, "Incorrect payment");
        require(to != address(0), "Invalid recipient");
        require(duration > 0, "Invalid duration");
        
        uint256 streamId = nextStreamId++;
        
        paymentStreams[streamId] = PaymentStream({
            from: msg.sender,
            to: to,
            totalAmount: totalAmount,
            startTime: block.timestamp,
            duration: duration,
            withdrawn: 0,
            active: true
        });
        
        emit PaymentStreamCreated(streamId, msg.sender, to, totalAmount);
        
        return streamId;
    }
    
    function withdrawFromStream(uint256 streamId) external {
        PaymentStream storage stream = paymentStreams[streamId];
        require(stream.active, "Stream not active");
        require(msg.sender == stream.to, "Not recipient");
        
        uint256 elapsed = block.timestamp - stream.startTime;
        if (elapsed > stream.duration) {
            elapsed = stream.duration;
        }
        
        uint256 totalVested = (stream.totalAmount * elapsed) / stream.duration;
        uint256 available = totalVested - stream.withdrawn;
        require(available > 0, "Nothing to withdraw");
        
        stream.withdrawn += available;
        
        (bool success, ) = payable(stream.to).call{value: available}("");
        require(success, "Transfer failed");
        
        emit PaymentStreamWithdrawn(streamId, available);
        
        if (stream.withdrawn == stream.totalAmount) {
            stream.active = false;
        }
    }
    
    function cancelPaymentStream(uint256 streamId) external {
        PaymentStream storage stream = paymentStreams[streamId];
        require(stream.active, "Stream not active");
        require(msg.sender == stream.from, "Not stream creator");
        
        stream.active = false;
        
        // Calculate vested amount
        uint256 elapsed = block.timestamp - stream.startTime;
        if (elapsed > stream.duration) {
            elapsed = stream.duration;
        }
        
        uint256 totalVested = (stream.totalAmount * elapsed) / stream.duration;
        uint256 toRecipient = totalVested - stream.withdrawn;
        uint256 toRefund = stream.totalAmount - totalVested;
        
        if (toRecipient > 0) {
            (bool success, ) = payable(stream.to).call{value: toRecipient}("");
            require(success, "Transfer to recipient failed");
        }
        
        if (toRefund > 0) {
            (bool success, ) = payable(stream.from).call{value: toRefund}("");
            require(success, "Refund failed");
        }
        
        emit PaymentStreamCancelled(streamId);
    }
    
    // Receive ETH
    receive() external payable {}
}