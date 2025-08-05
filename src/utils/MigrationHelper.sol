// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../NodeRegistry.sol";
import "../JobMarketplace.sol";
import "../PaymentEscrow.sol";
import "../ReputationSystem.sol";
import "../ProofSystem.sol";
import "../interfaces/IJobMarketplace.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MigrationHelper is Ownable {
    uint256 private constant UNLOCKED = 1;
    uint256 private constant LOCKED = 2;
    uint256 private reentrancyStatus = UNLOCKED;
    
    modifier nonReentrant() {
        require(reentrancyStatus == UNLOCKED, "Reentrant call");
        reentrancyStatus = LOCKED;
        _;
        reentrancyStatus = UNLOCKED;
    }
    // Migration data structures
    struct MigrationPlan {
        address[] oldContracts;
        address[] newContracts;
        uint256 migrationStartBlock;
        uint256 migrationDeadline;
        bool emergencyMode;
        mapping(address => bool) migratedUsers;
    }

    struct ContractState {
        address contractAddress;
        string contractType;
        uint256 stateVersion;
        bytes serializedState;
        uint256 snapshotBlock;
    }

    struct MigrationResult {
        bool success;
        uint256 itemsMigrated;
        uint256 itemsFailed;
        uint256 gasUsed;
        string[] errors;
    }

    struct NodeData {
        address operator;
        string peerId;
        uint256 stake;
        bool active;
        string[] models;
        string region;
    }

    struct JobData {
        uint256 jobId;
        address client;
        string modelId;
        string inputHash;
        uint256 payment;
        address paymentToken;
        uint256 deadline;
        uint256 status;
        address assignedNode;
        string resultCID;
    }

    struct EscrowData {
        bytes32 escrowId;
        address renter;
        address host;
        uint256 amount;
        address token;
        uint256 status;
        bool refundRequested;
    }

    struct ReputationData {
        address node;
        uint256 score;
        uint256 completedJobs;
        uint256 failedJobs;
        uint256 totalEarned;
    }

    // Events
    event MigrationStarted(
        address indexed oldContract,
        address indexed newContract,
        uint256 deadline
    );

    event StateExported(
        address indexed contract_,
        uint256 itemCount,
        uint256 snapshotBlock
    );

    event StateImported(
        address indexed contract_,
        uint256 itemCount,
        uint256 gasUsed
    );

    event MigrationCompleted(
        address indexed oldContract,
        address indexed newContract,
        uint256 totalItems,
        uint256 successCount
    );

    event EmergencyMigrationTriggered(
        address indexed contract_,
        string reason
    );

    event RollbackExecuted(
        address indexed contract_,
        uint256 rollbackBlock
    );

    // Storage
    mapping(address => MigrationPlan) public migrationPlans;
    mapping(address => bool) public emergencyGuardians;
    uint256 public constant MAX_BATCH_SIZE = 100;
    uint256 public constant EMERGENCY_DELAY = 1 hours;

    constructor() Ownable(msg.sender) {}

    // ========== Node Registry Migration ==========

    function exportNodeRegistryState(address registry) 
        external 
        view 
        returns (ContractState memory) 
    {
        NodeRegistry nodeRegistry = NodeRegistry(payable(registry));
        address[] memory activeNodes = nodeRegistry.getActiveNodes();
        
        NodeData[] memory nodes = new NodeData[](activeNodes.length);
        
        for (uint256 i = 0; i < activeNodes.length; i++) {
            NodeRegistry.Node memory node = nodeRegistry.getNode(activeNodes[i]);
            nodes[i] = NodeData({
                operator: node.operator,
                peerId: node.peerId,
                stake: node.stake,
                active: node.active,
                models: node.models,
                region: node.region
            });
        }
        
        return ContractState({
            contractAddress: registry,
            contractType: "NodeRegistry",
            stateVersion: 1,
            serializedState: abi.encode(nodes),
            snapshotBlock: block.number
        });
    }

    function importNodeRegistryState(
        address newRegistry,
        ContractState calldata state
    ) external onlyOwner returns (MigrationResult memory) {
        require(
            keccak256(bytes(state.contractType)) == keccak256(bytes("NodeRegistry")),
            "Invalid contract type"
        );
        
        NodeData[] memory nodes = abi.decode(state.serializedState, (NodeData[]));
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        uint256 failed = 0;
        string[] memory errors = new string[](0);
        
        NodeRegistry registry = NodeRegistry(payable(newRegistry));
        
        for (uint256 i = 0; i < nodes.length; i++) {
            NodeData memory nodeData = nodes[i];
            
            try registry.addMigratedNode{value: nodeData.stake}(
                nodeData.operator,
                nodeData.peerId,
                nodeData.models,
                nodeData.region
            ) {
                migrated++;
            } catch {
                failed++;
            }
        }
        
        emit StateImported(newRegistry, migrated, gasStart - gasleft());
        
        return MigrationResult({
            success: failed == 0,
            itemsMigrated: migrated,
            itemsFailed: failed,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }

    function _migrateNode(NodeRegistry registry, NodeData memory nodeData) external {
        require(msg.sender == address(this), "Internal only");
        
        // Add node directly to registry with stake
        registry.addMigratedNode{value: nodeData.stake}(
            nodeData.operator,
            nodeData.peerId,
            nodeData.models,
            nodeData.region
        );
    }

    // ========== Job Marketplace Migration ==========

    function exportJobMarketplaceState(address marketplace)
        external
        view
        returns (ContractState memory)
    {
        // Get active jobs from marketplace
        uint256[] memory activeJobIds = _getActiveJobIds(marketplace);
        JobData[] memory jobs = new JobData[](activeJobIds.length);
        
        IJobMarketplace jobMarketplace = IJobMarketplace(marketplace);
        
        for (uint256 i = 0; i < activeJobIds.length; i++) {
            uint256 jobId = activeJobIds[i];
            JobMarketplace.Job memory job = JobMarketplace(address(jobMarketplace)).getJobStruct(jobId);
            
            jobs[i] = JobData({
                jobId: jobId,
                client: job.renter,
                modelId: job.modelId,
                inputHash: job.inputHash,
                payment: job.maxPrice,
                paymentToken: address(0), // ETH only for now
                deadline: job.deadline,
                status: uint256(job.status),
                assignedNode: job.assignedHost,
                resultCID: job.resultHash
            });
        }
        
        return ContractState({
            contractAddress: marketplace,
            contractType: "JobMarketplace",
            stateVersion: 1,
            serializedState: abi.encode(jobs),
            snapshotBlock: block.number
        });
    }

    function importJobMarketplaceState(
        address newMarketplace,
        ContractState calldata state
    ) external onlyOwner returns (MigrationResult memory) {
        require(
            keccak256(bytes(state.contractType)) == keccak256(bytes("JobMarketplace")),
            "Invalid contract type"
        );
        
        JobData[] memory jobs = abi.decode(state.serializedState, (JobData[]));
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        string[] memory errors = new string[](0);
        
        JobMarketplace marketplace = JobMarketplace(newMarketplace);
        
        for (uint256 i = 0; i < jobs.length; i++) {
            JobData memory job = jobs[i];
            marketplace.addMigratedJob(
                job.jobId,
                job.client,
                job.modelId,
                job.inputHash,
                job.payment,
                job.paymentToken,
                job.deadline,
                job.status,
                job.assignedNode,
                job.resultCID
            );
            migrated++;
        }
        
        emit StateImported(newMarketplace, migrated, gasStart - gasleft());
        
        return MigrationResult({
            success: true,
            itemsMigrated: migrated,
            itemsFailed: 0,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }

    // ========== Payment Escrow Migration ==========

    function exportPaymentEscrowState(address escrow)
        external
        view
        returns (ContractState memory)
    {
        // Get active escrows
        bytes32[] memory escrowIds = _getActiveEscrowIds(escrow);
        EscrowData[] memory escrows = new EscrowData[](escrowIds.length);
        
        PaymentEscrow paymentEscrow = PaymentEscrow(payable(escrow));
        
        for (uint256 i = 0; i < escrowIds.length; i++) {
            bytes32 escrowId = escrowIds[i];
            PaymentEscrow.Escrow memory escrowInfo = paymentEscrow.getEscrow(escrowId);
            
            escrows[i] = EscrowData({
                escrowId: escrowId,
                renter: escrowInfo.renter,
                host: escrowInfo.host,
                amount: escrowInfo.amount,
                token: escrowInfo.token,
                status: uint256(escrowInfo.status),
                refundRequested: escrowInfo.refundRequested
            });
        }
        
        return ContractState({
            contractAddress: escrow,
            contractType: "PaymentEscrow",
            stateVersion: 1,
            serializedState: abi.encode(escrows, address(escrow).balance),
            snapshotBlock: block.number
        });
    }

    function importPaymentEscrowState(
        address newEscrow,
        ContractState calldata state
    ) external onlyOwner returns (MigrationResult memory) {
        require(
            keccak256(bytes(state.contractType)) == keccak256(bytes("PaymentEscrow")),
            "Invalid contract type"
        );
        
        (EscrowData[] memory escrows, ) = abi.decode(
            state.serializedState, 
            (EscrowData[], uint256)
        );
        
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        string[] memory errors = new string[](0);
        
        PaymentEscrow paymentEscrow = PaymentEscrow(payable(newEscrow));
        
        for (uint256 i = 0; i < escrows.length; i++) {
            paymentEscrow.addMigratedEscrow(
                escrows[i].escrowId,
                escrows[i].renter,
                escrows[i].host,
                escrows[i].amount,
                escrows[i].token,
                0, // releaseTime not used
                escrows[i].status == 1, // isReleased
                escrows[i].status == 4  // isRefunded
            );
            migrated++;
        }
        
        emit StateImported(newEscrow, migrated, gasStart - gasleft());
        
        return MigrationResult({
            success: true,
            itemsMigrated: migrated,
            itemsFailed: 0,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }

    // ========== Reputation System Migration ==========

    function exportReputationState(address reputation)
        external
        view
        returns (ContractState memory)
    {
        ReputationSystem repSystem = ReputationSystem(reputation);
        address[] memory nodes = _getNodesWithReputation(repSystem);
        
        ReputationData[] memory reputations = new ReputationData[](nodes.length);
        
        for (uint256 i = 0; i < nodes.length; i++) {
            uint256 score = repSystem.getReputation(nodes[i]);
            
            reputations[i] = ReputationData({
                node: nodes[i],
                score: score,
                completedJobs: 0, // Would need getter in real implementation
                failedJobs: 0,
                totalEarned: 0
            });
        }
        
        return ContractState({
            contractAddress: reputation,
            contractType: "ReputationSystem",
            stateVersion: 1,
            serializedState: abi.encode(reputations),
            snapshotBlock: block.number
        });
    }

    function importReputationState(
        address newReputation,
        ContractState calldata state
    ) external onlyOwner returns (MigrationResult memory) {
        require(
            keccak256(bytes(state.contractType)) == keccak256(bytes("ReputationSystem")),
            "Invalid contract type"
        );
        
        ReputationData[] memory reputations = abi.decode(
            state.serializedState,
            (ReputationData[])
        );
        
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        string[] memory errors = new string[](0);
        
        ReputationSystem repSystem = ReputationSystem(newReputation);
        
        for (uint256 i = 0; i < reputations.length; i++) {
            repSystem.setMigratedReputation(
                reputations[i].node,
                reputations[i].score
            );
            migrated++;
        }
        
        emit StateImported(newReputation, migrated, gasStart - gasleft());
        
        return MigrationResult({
            success: true,
            itemsMigrated: migrated,
            itemsFailed: 0,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }

    // ========== Fund Transfer Functions ==========

    function transferEscrowFunds(
        address from,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(address(from).balance >= amount, "Insufficient balance");
        
        PaymentEscrow oldEscrow = PaymentEscrow(payable(from));
        
        // Emergency withdraw from old escrow
        oldEscrow.emergencyWithdraw(to, amount);
    }

    // ========== Emergency Functions ==========

    function emergencyExportState(address contract_)
        external
        view
        returns (ContractState memory)
    {
        // Determine contract type and export minimal state
        if (_isNodeRegistry(contract_)) {
            return this.exportNodeRegistryState(contract_);
        } else if (_isJobMarketplace(contract_)) {
            return this.exportJobMarketplaceState(contract_);
        } else if (_isPaymentEscrow(contract_)) {
            return this.exportPaymentEscrowState(contract_);
        } else if (_isReputationSystem(contract_)) {
            return this.exportReputationState(contract_);
        }
        
        revert("Unknown contract type");
    }

    function emergencyImportState(
        address newContract,
        ContractState calldata state
    ) external onlyOwner returns (MigrationResult memory) {
        // Fast import with minimal validation
        bytes32 contractTypeHash = keccak256(bytes(state.contractType));
        
        if (contractTypeHash == keccak256(bytes("NodeRegistry"))) {
            return _importNodeRegistryStateInternal(newContract, state);
        } else if (contractTypeHash == keccak256(bytes("JobMarketplace"))) {
            return _importJobMarketplaceStateInternal(newContract, state);
        } else if (contractTypeHash == keccak256(bytes("PaymentEscrow"))) {
            return _importPaymentEscrowStateInternal(newContract, state);
        } else if (contractTypeHash == keccak256(bytes("ReputationSystem"))) {
            return _importReputationStateInternal(newContract, state);
        }
        
        revert("Unknown contract type");
    }

    function emergencyExtractFunds(
        address from,
        address to,
        uint256 amount
    ) external nonReentrant {
        require(owner() == msg.sender || emergencyGuardians[msg.sender], "Not authorized");
        
        if (_isPaymentEscrow(from)) {
            PaymentEscrow(payable(from)).emergencyWithdraw(to, amount);
        } else {
            // Direct transfer for other contracts
            (bool success, ) = to.call{value: amount}("");
            require(success, "Transfer failed");
        }
    }

    // ========== Batch Processing ==========

    function migrateSpecificNodes(
        address from,
        address to,
        address[] calldata nodes
    ) external onlyOwner returns (MigrationResult memory) {
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        string[] memory errors = new string[](0);
        
        NodeRegistry oldRegistry = NodeRegistry(payable(from));
        NodeRegistry newRegistry = NodeRegistry(payable(to));
        
        for (uint256 i = 0; i < nodes.length; i++) {
            NodeRegistry.Node memory node = oldRegistry.getNode(nodes[i]);
            
            if (node.active) {
                newRegistry.addMigratedNode{value: node.stake}(
                    node.operator,
                    node.peerId,
                    node.models,
                    node.region
                );
                migrated++;
            }
        }
        
        return MigrationResult({
            success: true,
            itemsMigrated: migrated,
            itemsFailed: nodes.length - migrated,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }

    function importNodeRegistryChunk(
        address registry,
        ContractState calldata state,
        uint256 startIdx,
        uint256 endIdx
    ) external onlyOwner returns (MigrationResult memory) {
        NodeData[] memory allNodes = abi.decode(state.serializedState, (NodeData[]));
        require(endIdx <= allNodes.length, "End index out of bounds");
        
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        string[] memory errors = new string[](0);
        
        NodeRegistry nodeRegistry = NodeRegistry(payable(registry));
        
        for (uint256 i = startIdx; i < endIdx; i++) {
            try this._migrateNode(nodeRegistry, allNodes[i]) {
                migrated++;
            } catch {
                // Continue with next node
            }
        }
        
        return MigrationResult({
            success: true,
            itemsMigrated: migrated,
            itemsFailed: (endIdx - startIdx) - migrated,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }

    // ========== Integrity Checking ==========

    function exportWithIntegrityCheck(address contract_)
        external
        view
        returns (ContractState memory state, bytes32 checksum)
    {
        state = this.emergencyExportState(contract_);
        checksum = keccak256(state.serializedState);
    }

    function importWithIntegrityCheck(
        address newContract,
        ContractState calldata state,
        bytes32 expectedChecksum
    ) external onlyOwner returns (MigrationResult memory) {
        bytes32 actualChecksum = keccak256(state.serializedState);
        
        if (actualChecksum != expectedChecksum) {
            string[] memory errors = new string[](1);
            errors[0] = "Integrity check failed";
            
            return MigrationResult({
                success: false,
                itemsMigrated: 0,
                itemsFailed: 0,
                gasUsed: 5000,
                errors: errors
            });
        }
        
        return this.emergencyImportState(newContract, state);
    }

    // ========== Helper Functions ==========


    function _getActiveJobIds(address marketplace)
        internal
        view
        returns (uint256[] memory)
    {
        return JobMarketplace(marketplace).getActiveJobIds();
    }

    function _getActiveEscrowIds(address escrow)
        internal
        view
        returns (bytes32[] memory)
    {
        // This would need a getter in the real PaymentEscrow
        return new bytes32[](0);
    }

    function _getNodesWithReputation(ReputationSystem repSystem)
        internal
        view
        returns (address[] memory)
    {
        return repSystem.getNodesWithReputation();
    }

    function _isNodeRegistry(address contract_) internal view returns (bool) {
        try NodeRegistry(payable(contract_)).minimumStake() returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _isJobMarketplace(address contract_) internal view returns (bool) {
        try JobMarketplace(contract_).nodeRegistry() returns (NodeRegistry) {
            return true;
        } catch {
            return false;
        }
    }

    function _isPaymentEscrow(address contract_) internal view returns (bool) {
        try PaymentEscrow(payable(contract_)).feeBasisPoints() returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _isReputationSystem(address contract_) internal view returns (bool) {
        try ReputationSystem(contract_).nodeRegistry() returns (NodeRegistry) {
            return true;
        } catch {
            return false;
        }
    }

    // ========== Internal Import Functions ==========
    
    function _importNodeRegistryStateInternal(
        address newRegistry,
        ContractState calldata state
    ) internal returns (MigrationResult memory) {
        require(
            keccak256(bytes(state.contractType)) == keccak256(bytes("NodeRegistry")),
            "Invalid contract type"
        );
        
        NodeData[] memory nodes = abi.decode(state.serializedState, (NodeData[]));
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        uint256 failed = 0;
        string[] memory errors = new string[](0);
        
        NodeRegistry registry = NodeRegistry(payable(newRegistry));
        
        for (uint256 i = 0; i < nodes.length; i++) {
            NodeData memory nodeData = nodes[i];
            
            try registry.addMigratedNode{value: nodeData.stake}(
                nodeData.operator,
                nodeData.peerId,
                nodeData.models,
                nodeData.region
            ) {
                migrated++;
            } catch {
                failed++;
            }
        }
        
        emit StateImported(newRegistry, migrated, gasStart - gasleft());
        
        return MigrationResult({
            success: failed == 0,
            itemsMigrated: migrated,
            itemsFailed: failed,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }
    
    function _importJobMarketplaceStateInternal(
        address newMarketplace,
        ContractState calldata state
    ) internal returns (MigrationResult memory) {
        require(
            keccak256(bytes(state.contractType)) == keccak256(bytes("JobMarketplace")),
            "Invalid contract type"
        );
        
        JobData[] memory jobs = abi.decode(state.serializedState, (JobData[]));
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        string[] memory errors = new string[](0);
        
        JobMarketplace marketplace = JobMarketplace(newMarketplace);
        
        for (uint256 i = 0; i < jobs.length; i++) {
            JobData memory job = jobs[i];
            marketplace.addMigratedJob(
                job.jobId,
                job.client,
                job.modelId,
                job.inputHash,
                job.payment,
                job.paymentToken,
                job.deadline,
                job.status,
                job.assignedNode,
                job.resultCID
            );
            migrated++;
        }
        
        emit StateImported(newMarketplace, migrated, gasStart - gasleft());
        
        return MigrationResult({
            success: true,
            itemsMigrated: migrated,
            itemsFailed: 0,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }
    
    function _importPaymentEscrowStateInternal(
        address newEscrow,
        ContractState calldata state
    ) internal returns (MigrationResult memory) {
        require(
            keccak256(bytes(state.contractType)) == keccak256(bytes("PaymentEscrow")),
            "Invalid contract type"
        );
        
        (EscrowData[] memory escrows, ) = abi.decode(
            state.serializedState, 
            (EscrowData[], uint256)
        );
        
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        string[] memory errors = new string[](0);
        
        PaymentEscrow paymentEscrow = PaymentEscrow(payable(newEscrow));
        
        for (uint256 i = 0; i < escrows.length; i++) {
            paymentEscrow.addMigratedEscrow(
                escrows[i].escrowId,
                escrows[i].renter,
                escrows[i].host,
                escrows[i].amount,
                escrows[i].token,
                0, // releaseTime not used
                escrows[i].status == 1, // isReleased
                escrows[i].status == 4  // isRefunded
            );
            migrated++;
        }
        
        emit StateImported(newEscrow, migrated, gasStart - gasleft());
        
        return MigrationResult({
            success: true,
            itemsMigrated: migrated,
            itemsFailed: 0,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }
    
    function _importReputationStateInternal(
        address newReputation,
        ContractState calldata state
    ) internal returns (MigrationResult memory) {
        require(
            keccak256(bytes(state.contractType)) == keccak256(bytes("ReputationSystem")),
            "Invalid contract type"
        );
        
        ReputationData[] memory reputations = abi.decode(
            state.serializedState,
            (ReputationData[])
        );
        
        uint256 gasStart = gasleft();
        uint256 migrated = 0;
        string[] memory errors = new string[](0);
        
        ReputationSystem repSystem = ReputationSystem(newReputation);
        
        for (uint256 i = 0; i < reputations.length; i++) {
            repSystem.setMigratedReputation(
                reputations[i].node,
                reputations[i].score
            );
            migrated++;
        }
        
        emit StateImported(newReputation, migrated, gasStart - gasleft());
        
        return MigrationResult({
            success: true,
            itemsMigrated: migrated,
            itemsFailed: 0,
            gasUsed: gasStart - gasleft(),
            errors: errors
        });
    }

    // ========== Admin Functions ==========

    function addEmergencyGuardian(address guardian) external onlyOwner {
        emergencyGuardians[guardian] = true;
    }

    function removeEmergencyGuardian(address guardian) external onlyOwner {
        emergencyGuardians[guardian] = false;
    }

    // Receive function to accept funds during migration
    receive() external payable {}
}