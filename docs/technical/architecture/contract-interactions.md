# Contract Interaction Flows

This document details the interaction patterns between contracts in the Fabstir compute marketplace, providing sequence diagrams and code examples for common operations.

## Table of Contents

1. [Host Registration Flow](#host-registration-flow)
2. [Job Lifecycle Flow](#job-lifecycle-flow)
3. [Payment Processing Flow](#payment-processing-flow)
4. [Proof Verification Flow](#proof-verification-flow)
5. [Reputation Update Flow](#reputation-update-flow)
6. [Governance Execution Flow](#governance-execution-flow)
7. [ERC-4337 Integration Flow](#erc-4337-integration-flow)
8. [Emergency Response Flow](#emergency-response-flow)

---

## Host Registration Flow

### Sequence Diagram
```
User → FAB Token: approve(NodeRegistryFAB, 1000 FAB)
         │
         └─→ Set allowance

User → NodeRegistryFAB: registerNode(metadata)
         │
         ├─→ Transfer 1000 FAB from user
         ├─→ Check registration limits
         ├─→ Store node data
         ├─→ Add to active nodes list
         └─→ Emit NodeRegistered
```

### Code Example
```solidity
// FAB-based registration
function registerAsHost() external {
    // First approve FAB tokens
    uint256 stakeAmount = 1000 ether; // 1000 FAB
    fabToken.approve(address(nodeRegistryFAB), stakeAmount);
    
    // Register with metadata
    string memory metadata = "gpu:rtx4090,models:gpt-4;llama2,region:us-west";
    nodeRegistryFAB.registerNode(metadata);
}

// Registration with Sybil tracking
function registerControlledHost(address nodeOperator) external payable {
    nodeRegistry.registerControlledNode{value: 100 ether}(
        "QmPeerId456",
        nodeOperator
    );
    
    // Check if controller is suspicious
    if (nodeRegistry.isSuspiciousController(msg.sender)) {
        // Take appropriate action
    }
}
```

---

## Job Lifecycle Flow

### Complete Job Flow
```
1. Renter → JobMarketplace: createJob{value: payment}
              │
              ├─→ Validate parameters
              ├─→ Store job data
              └─→ Lock payment in escrow

2. Host → JobMarketplace: claimJob(jobId)
            │
            ├─→ Verify host in NodeRegistry
            ├─→ Check Sybil attacks
            ├─→ Assign job to host
            └─→ Update job status

3. Host → ProofSystem: submitProof(jobId, proof)
            │
            ├─→ Validate proof format
            ├─→ Store proof data
            └─→ Emit ProofSubmitted

4. Verifier → ProofSystem: verifyProof(jobId)
                │
                ├─→ Run verification
                ├─→ Update proof status
                └─→ Notify marketplace

5. Host → JobMarketplace: completeJob(jobId, resultHash, proof)
            │
            ├─→ Check proof verified
            ├─→ Transfer payment to host
            ├─→ Update reputation
            └─→ Emit JobCompleted
```

### Code Example
```solidity
// Complete flow implementation
contract JobFlowExample {
    IJobMarketplace marketplace;
    IProofSystem proofSystem;
    
    // Step 1: Post job
    function postAIJob(string memory prompt) external payable returns (uint256) {
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: "gpt-4",
            prompt: prompt,
            maxTokens: 4000,
            temperature: 700,  // 0.7 * 1000
            seed: 42,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 100,
            maxTimeToComplete: 3600,  // 1 hour
            requiresProof: true
        });
        
        return marketplace.postJob{value: msg.value}(details, requirements, msg.value);
    }
    
    // Step 2-3: Host claims and processes
    function processJob(uint256 jobId) external {
        // Claim job
        marketplace.claimJob(jobId);
        
        // Off-chain: Run AI inference
        bytes32 outputHash = runInference(jobId);
        
        // Generate and submit proof
        ProofSystem.EZKLProof memory proof = generateProof(
            jobId,
            outputHash
        );
        proofSystem.submitProof(jobId, proof);
        
        // Wait for verification...
        
        // Complete job
        marketplace.completeJob(
            jobId,
            string(abi.encodePacked(outputHash)),
            abi.encode(proof)
        );
    }
}
```

---

## Payment Processing Flow

### Escrow Release Flow
```
JobMarketplace → PaymentEscrow: createEscrow{value: payment}
                     │
                     ├─→ Store escrow data
                     └─→ Hold payment

On Completion:
Renter → JobMarketplace: releasePayment(jobId)
            │
            └─→ PaymentEscrow: releaseEscrow(escrowId)
                     │
                     ├─→ Calculate fees
                     ├─→ Transfer to host
                     └─→ Update fee balance
```

### Dispute Flow
```
Party → PaymentEscrow: disputeEscrow(escrowId)
             │
             └─→ Mark as disputed

Arbiter → PaymentEscrow: resolveDispute(escrowId, winner)
               │
               ├─→ If host wins: Pay host minus fee
               └─→ If renter wins: Full refund
```

### Code Example
```solidity
// Payment handling with escrow
contract PaymentHandler {
    IPaymentEscrow escrow;
    
    // Create escrow for job
    function createJobEscrow(
        bytes32 jobId,
        address host,
        address token,
        uint256 amount
    ) external payable {
        if (token == address(0)) {
            // ETH payment
            escrow.createEscrow{value: amount}(jobId, host, amount, token);
        } else {
            // ERC20 payment
            IERC20(token).approve(address(escrow), amount);
            escrow.createEscrow(jobId, host, amount, token);
        }
    }
    
    // Handle dispute
    function initiateDispute(bytes32 jobId) external {
        escrow.disputeEscrow(jobId);
        // Notify arbiter off-chain
    }
}
```

---

## Proof Verification Flow

### Verification with Challenge
```
1. ProofSystem: Proof submitted
       │
       └─→ Status: Submitted

2. Verifier → ProofSystem: verifyProof(jobId)
                 │
                 ├─→ Run EZKL verification
                 ├─→ Update status
                 └─→ If invalid: Update reputation

3. Challenger → ProofSystem: challengeProof{stake}(jobId)
                   │
                   ├─→ Lock stake
                   ├─→ Create challenge
                   └─→ Start timer

4. Verifier → ProofSystem: resolveChallenge(challengeId, result)
                 │
                 ├─→ If valid: Challenger loses stake
                 └─→ If invalid: Host penalized, challenger rewarded
```

### Code Example
```solidity
// Proof verification integration
contract ProofHandler {
    IProofSystem proofSystem;
    IERC20 stakeToken;
    
    // Submit proof for job
    function submitJobProof(
        uint256 jobId,
        bytes32 modelCommitment,
        bytes32 inputHash,
        bytes32 outputHash
    ) external {
        // Create EZKL proof structure
        uint256[] memory instances = new uint256[](3);
        instances[0] = uint256(modelCommitment);
        instances[1] = uint256(inputHash);
        instances[2] = uint256(outputHash);
        
        ProofSystem.EZKLProof memory proof = ProofSystem.EZKLProof({
            instances: instances,
            proof: generateProofData(),
            vk: getVerificationKey(),
            modelCommitment: modelCommitment,
            inputHash: inputHash,
            outputHash: outputHash
        });
        
        proofSystem.submitProof(jobId, proof);
    }
    
    // Challenge suspicious proof
    function challengeProof(uint256 jobId, bytes32 evidence) external {
        uint256 stakeAmount = 10 ether;
        
        // Approve stake
        stakeToken.approve(address(proofSystem), stakeAmount);
        
        // Submit challenge
        uint256 challengeId = proofSystem.challengeProof(
            jobId,
            evidence,
            stakeAmount
        );
        
        // Track challenge for monitoring
        trackChallenge(challengeId);
    }
}
```

---

## Reputation Update Flow

### Automatic Updates
```
JobMarketplace → ReputationSystem: recordJobCompletion(host, jobId, success)
                        │
                        ├─→ If success: +10 points
                        ├─→ If failure: -20 points
                        └─→ Update timestamp

ProofSystem → ReputationSystem: recordJobCompletion(host, jobId, false)
                     │
                     └─→ When proof invalid

Renter → ReputationSystem: rateHost(host, jobId, rating, feedback)
              │
              ├─→ Verify job completed
              ├─→ Add rating
              └─→ Bonus for high ratings
```

### Code Example
```solidity
// Reputation-aware job assignment
contract ReputationAwareMarketplace {
    IReputationSystem reputation;
    INodeRegistry registry;
    
    // Get best host for job
    function selectBestHost(
        address[] memory candidates
    ) public view returns (address) {
        address bestHost;
        uint256 bestScore = 0;
        
        for (uint i = 0; i < candidates.length; i++) {
            if (!registry.isActiveNode(candidates[i])) continue;
            
            uint256 score = reputation.getReputation(candidates[i]);
            if (score > bestScore) {
                bestScore = score;
                bestHost = candidates[i];
            }
        }
        
        require(bestHost != address(0), "No suitable host");
        return bestHost;
    }
    
    // Incentivize high-reputation hosts
    function calculatePayment(
        address host,
        uint256 basePayment
    ) public view returns (uint256) {
        if (reputation.isEligibleForIncentives(host)) {
            // 10% bonus for high reputation
            return (basePayment * 110) / 100;
        }
        return basePayment;
    }
}
```

---

## Governance Execution Flow

### Parameter Update Flow
```
1. Token Holder → Governance: proposeParameterUpdate(updates, description)
                    │
                    ├─→ Check proposal threshold
                    ├─→ Create proposal
                    └─→ Start voting delay

2. Token Holders → Governance: castVote(proposalId, support)
                      │
                      └─→ Record weighted votes

3. Anyone → Governance: queue(proposalId)
               │
               ├─→ Check quorum reached
               ├─→ Check majority support
               └─→ Set execution time

4. Anyone → Governance: execute(proposalId)
               │
               ├─→ Check time lock passed
               └─→ Execute parameter changes
```

### Code Example
```solidity
// Governance proposal flow
contract GovernanceExample {
    IGovernance governance;
    IGovernanceToken token;
    
    // Propose fee reduction
    function proposeFeeReduction() external {
        // Ensure voting power
        require(
            token.getVotes(msg.sender) >= 10000 ether,
            "Insufficient voting power"
        );
        
        Governance.ParameterUpdate[] memory updates = 
            new Governance.ParameterUpdate[](1);
            
        updates[0] = Governance.ParameterUpdate({
            targetContract: address(paymentEscrow),
            functionSelector: PaymentEscrow.setFee.selector,
            parameterName: "feeBasisPoints",
            newValue: 100  // 1% fee
        });
        
        uint256 proposalId = governance.proposeParameterUpdate(
            updates,
            "Reduce protocol fee to 1%"
        );
        
        // Vote immediately if possible
        governance.castVote(proposalId, true);
    }
    
    // Emergency pause
    function emergencyPause(address contract_) external {
        require(
            governance.hasRole(governance.EMERGENCY_ROLE(), msg.sender),
            "Not emergency admin"
        );
        
        governance.executeEmergencyAction("pause", contract_);
    }
}
```

---

## ERC-4337 Integration Flow

### Gasless Transaction Flow
```
1. User → Wallet: Sign UserOperation
           │
           └─→ Include paymaster

2. Bundler → EntryPoint: handleOps([userOp])
                │
                └─→ BaseAccountIntegration: handleOp(userOp)
                            │
                            ├─→ Decode operation
                            ├─→ Execute on behalf
                            └─→ Track gas usage

3. Paymaster → EntryPoint: Pay for gas
                 │
                 └─→ Emit sponsorship event
```

### Session Key Flow
```
1. Wallet → BaseAccountIntegration: addSessionKey(app, expiry)
                         │
                         └─→ Grant temporary permission

2. App → BaseAccountIntegration: claimJobViaSessionKey(wallet, jobId)
                      │
                      ├─→ Verify session key
                      └─→ Execute for wallet

3. Wallet → BaseAccountIntegration: revokeSessionKey(app)
                         │
                         └─→ Revoke permission
```

### Code Example
```solidity
// ERC-4337 integration
contract SmartWalletIntegration {
    IBaseAccountIntegration integration;
    IEntryPoint entryPoint;
    
    // Build UserOperation for job creation
    function buildJobCreationOp(
        address wallet,
        uint256 nonce,
        string memory modelId,
        uint256 payment
    ) public pure returns (UserOperation memory) {
        // Encode the call
        bytes memory callData = abi.encodeWithSelector(
            IAccount.execute.selector,
            address(integration),
            payment,
            abi.encodeWithSelector(
                BaseAccountIntegration.createJobViaAccount.selector,
                modelId,
                "inputHash",
                payment,
                block.timestamp + 1 hours
            )
        );
        
        return UserOperation({
            sender: wallet,
            nonce: nonce,
            initCode: "",
            callData: callData,
            callGasLimit: 200000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 30 gwei,
            maxPriorityFeePerGas: 2 gwei,
            paymasterAndData: abi.encodePacked(paymasterAddress),
            signature: ""  // To be signed
        });
    }
    
    // Session key management
    function setupAppIntegration(address app) external {
        // Grant 7-day session
        integration.addSessionKey(app, block.timestamp + 7 days);
        
        // App can now claim jobs
        // integration.claimJobViaSessionKey(msg.sender, jobId);
    }
}
```

---

## Emergency Response Flow

### Circuit Breaker Activation
```
Failure Detection → JobMarketplace: Internal trigger
                         │
                         ├─→ Increment failure count
                         ├─→ Check threshold
                         └─→ Auto-pause if exceeded

Manual Response → JobMarketplace: emergencyPause(reason)
                       │
                       ├─→ Check authorization
                       ├─→ Set paused state
                       └─→ Emit event

Recovery → JobMarketplace: unpause()
                │
                ├─→ Check cooldown
                └─→ Resume operations
```

### Governance Override
```
Governance → Target Contract: Emergency action
                   │
                   ├─→ Validate emergency role
                   ├─→ Execute action
                   └─→ Log for audit
```

### Code Example
```solidity
// Emergency response system
contract EmergencyResponse {
    IJobMarketplace marketplace;
    IGovernance governance;
    
    // Monitor and respond to failures
    function monitorHealth() external view returns (bool needsAction) {
        (
            uint256 failures,
            uint256 successes,
            uint256 suspicious,
            uint256 lastIncident
        ) = marketplace.getCircuitBreakerMetrics();
        
        // High failure rate
        if (failures > successes / 10) return true;
        
        // Recent incidents
        if (block.timestamp - lastIncident < 1 hours) return true;
        
        // Suspicious activity spike
        if (suspicious > 10) return true;
        
        return false;
    }
    
    // Graduated response
    function respondToThreat(uint256 threatLevel) external {
        require(hasEmergencyRole(), "Not authorized");
        
        if (threatLevel == 1) {
            // Level 1: Enable throttling
            marketplace.setCircuitBreakerLevel(1);
        } else if (threatLevel == 2) {
            // Level 2: Pause specific functions
            marketplace.pauseFunction("postJob");
            marketplace.pauseFunction("claimJob");
        } else if (threatLevel == 3) {
            // Level 3: Full pause
            marketplace.emergencyPause("Critical threat detected");
        }
    }
    
    // Coordinated recovery
    function coordinatedRecovery() external {
        require(hasEmergencyRole(), "Not authorized");
        
        // 1. Assess situation
        require(!monitorHealth(), "Still unhealthy");
        
        // 2. Gradual unpause
        marketplace.setCircuitBreakerLevel(1);  // Throttled
        
        // 3. Monitor
        // ... wait and observe ...
        
        // 4. Full recovery
        marketplace.setCircuitBreakerLevel(0);  // Normal
    }
}
```

---

## Best Practices for Contract Interactions

### 1. Always Verify State
```solidity
// Before claiming job
require(nodeRegistry.isActiveNode(msg.sender), "Not active host");
require(reputation.getReputation(msg.sender) >= minRep, "Low reputation");
```

### 2. Handle Failures Gracefully
```solidity
try marketplace.claimJob(jobId) {
    // Success path
} catch Error(string memory reason) {
    if (keccak256(bytes(reason)) == keccak256("Job expired")) {
        // Handle expiry
    } else {
        revert(reason);
    }
}
```

### 3. Batch When Possible
```solidity
// Instead of multiple transactions
Operation[] memory ops = buildBatchOperations();
integration.executeBatch{value: totalValue}(ops);
```

### 4. Monitor Events
```solidity
event JobCompleted(uint256 indexed jobId, string resultCID);

// Off-chain monitoring
marketplace.on("JobCompleted", (jobId, resultCID) => {
    processCompletion(jobId, resultCID);
});
```

### 5. Respect Access Control
```solidity
// Check roles before privileged operations
require(
    governance.hasRole(EMERGENCY_ROLE, msg.sender),
    "Emergency role required"
);
```

## Conclusion

These interaction patterns form the backbone of the Fabstir marketplace. Understanding these flows enables developers to build robust integrations and extend the platform's capabilities while maintaining security and efficiency.