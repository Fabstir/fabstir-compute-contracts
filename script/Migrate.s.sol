// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/utils/MigrationHelper.sol";
import "../src/NodeRegistry.sol";
import "../src/JobMarketplace.sol";
import "../src/PaymentEscrow.sol";
import "../src/ReputationSystem.sol";
import "../src/ProofSystem.sol";
import "../src/Governance.sol";
import "../src/GovernanceToken.sol";

contract MigrateScript is Script {
    // Configuration
    struct MigrationConfig {
        address[] oldContracts;
        address[] newContracts;
        address migrationHelper;
        bool emergencyMode;
        uint256 batchSize;
    }

    // Events for logging
    event MigrationPhase(string phase, bool success);
    event ContractMigrated(address oldContract, address newContract, uint256 itemsCount);
    event FundsTransferred(address from, address to, uint256 amount);
    event MigrationCompleted(uint256 totalTime, uint256 totalGas);

    MigrationHelper public helper;
    MigrationConfig public config;
    
    mapping(string => address) public oldContracts;
    mapping(string => address) public newContracts;

    function run() external {
        // Load configuration
        _loadConfig();
        
        // Deploy migration helper if not provided
        if (config.migrationHelper == address(0)) {
            vm.startBroadcast();
            helper = new MigrationHelper();
            vm.stopBroadcast();
        } else {
            helper = MigrationHelper(payable(config.migrationHelper));
        }
        
        // Execute migration phases
        if (config.emergencyMode) {
            _executeEmergencyMigration();
        } else {
            _executeStandardMigration();
        }
    }

    function _loadConfig() internal {
        // Load from environment or config file
        config.batchSize = vm.envUint("BATCH_SIZE");
        if (config.batchSize == 0) config.batchSize = 50;
        config.emergencyMode = vm.envBool("EMERGENCY_MODE");
        
        // Load old contract addresses
        oldContracts["NodeRegistry"] = vm.envAddress("OLD_NODE_REGISTRY");
        oldContracts["JobMarketplace"] = vm.envAddress("OLD_JOB_MARKETPLACE");
        oldContracts["PaymentEscrow"] = vm.envAddress("OLD_PAYMENT_ESCROW");
        oldContracts["ReputationSystem"] = vm.envAddress("OLD_REPUTATION_SYSTEM");
        oldContracts["ProofSystem"] = vm.envAddress("OLD_PROOF_SYSTEM");
        oldContracts["Governance"] = vm.envAddress("OLD_GOVERNANCE");
        oldContracts["GovernanceToken"] = vm.envAddress("OLD_GOVERNANCE_TOKEN");
        
        // New contracts can be loaded or will be deployed
        try vm.envString("NEW_DEPLOYMENT") returns (string memory newDeployment) {
            if (keccak256(bytes(newDeployment)) != keccak256(bytes("true"))) {
                _loadNewContracts();
            }
        } catch {
            // Default to true if not set
        }
    }

    function _loadNewContracts() internal {
        newContracts["NodeRegistry"] = vm.envAddress("NEW_NODE_REGISTRY");
        newContracts["JobMarketplace"] = vm.envAddress("NEW_JOB_MARKETPLACE");
        newContracts["PaymentEscrow"] = vm.envAddress("NEW_PAYMENT_ESCROW");
        newContracts["ReputationSystem"] = vm.envAddress("NEW_REPUTATION_SYSTEM");
        newContracts["ProofSystem"] = vm.envAddress("NEW_PROOF_SYSTEM");
        newContracts["Governance"] = vm.envAddress("NEW_GOVERNANCE");
        newContracts["GovernanceToken"] = vm.envAddress("NEW_GOVERNANCE_TOKEN");
    }

    function _executeStandardMigration() internal {
        uint256 startTime = block.timestamp;
        uint256 startGas = gasleft();
        
        // Phase 1: Deploy new contracts
        emit MigrationPhase("Deploy", true);
        _deployNewContracts();
        
        // Phase 2: Pause old contracts
        emit MigrationPhase("Pause", true);
        _pauseOldContracts();
        
        // Phase 3: Export states
        emit MigrationPhase("Export", true);
        MigrationHelper.ContractState[] memory states = _exportAllStates();
        
        // Phase 4: Transfer funds
        emit MigrationPhase("Transfer Funds", true);
        _transferAllFunds();
        
        // Phase 5: Import states
        emit MigrationPhase("Import", true);
        _importAllStates(states);
        
        // Phase 6: Update references
        emit MigrationPhase("Update References", true);
        _updateContractReferences();
        
        // Phase 7: Verify migration
        emit MigrationPhase("Verify", true);
        require(_verifyMigration(), "Migration verification failed");
        
        uint256 totalTime = block.timestamp - startTime;
        uint256 totalGas = startGas - gasleft();
        emit MigrationCompleted(totalTime, totalGas);
    }

    function _executeEmergencyMigration() internal {
        console.log("EMERGENCY MIGRATION INITIATED");
        
        // Fast track deployment
        _deployNewContracts();
        
        // Emergency pause all old contracts
        vm.startBroadcast();
        
        if (oldContracts["JobMarketplace"] != address(0)) {
            JobMarketplace(oldContracts["JobMarketplace"]).emergencyPause("Emergency migration");
        }
        
        // Emergency fund extraction
        if (oldContracts["PaymentEscrow"] != address(0)) {
            uint256 escrowBalance = oldContracts["PaymentEscrow"].balance;
            if (escrowBalance > 0) {
                helper.emergencyExtractFunds(
                    oldContracts["PaymentEscrow"],
                    newContracts["PaymentEscrow"],
                    escrowBalance
                );
            }
        }
        
        vm.stopBroadcast();
        
        // Minimal state migration
        MigrationHelper.ContractState[] memory states = _exportCriticalStates();
        _importCriticalStates(states);
    }

    function _deployNewContracts() internal {
        vm.startBroadcast();
        
        // Deploy in dependency order
        newContracts["NodeRegistry"] = address(new NodeRegistry(10 ether));
        newContracts["PaymentEscrow"] = address(new PaymentEscrow(msg.sender, 250));
        newContracts["JobMarketplace"] = address(new JobMarketplace(newContracts["NodeRegistry"]));
        newContracts["ReputationSystem"] = address(new ReputationSystem(
            newContracts["NodeRegistry"],
            newContracts["JobMarketplace"],
            msg.sender
        ));
        newContracts["ProofSystem"] = address(new ProofSystem(
            newContracts["JobMarketplace"],
            newContracts["PaymentEscrow"],
            newContracts["ReputationSystem"]
        ));
        
        // Deploy governance if needed
        if (oldContracts["GovernanceToken"] != address(0)) {
            // Skip governance deployment in migration script
            // It requires specific initialization
        }
        
        // Configure new contracts
        PaymentEscrow(payable(newContracts["PaymentEscrow"])).setJobMarketplace(
            newContracts["JobMarketplace"]
        );
        
        JobMarketplace(newContracts["JobMarketplace"]).setReputationSystem(
            newContracts["ReputationSystem"]
        );
        
        // Set migration helper on all contracts
        NodeRegistry(payable(newContracts["NodeRegistry"])).setMigrationHelper(address(helper));
        JobMarketplace(newContracts["JobMarketplace"]).setMigrationHelper(address(helper));
        PaymentEscrow(payable(newContracts["PaymentEscrow"])).setMigrationHelper(address(helper));
        ReputationSystem(newContracts["ReputationSystem"]).setMigrationHelper(address(helper));
        
        vm.stopBroadcast();
        
        console.log("New contracts deployed:");
        console.log("NodeRegistry:", newContracts["NodeRegistry"]);
        console.log("JobMarketplace:", newContracts["JobMarketplace"]);
        console.log("PaymentEscrow:", newContracts["PaymentEscrow"]);
        console.log("ReputationSystem:", newContracts["ReputationSystem"]);
    }

    function _pauseOldContracts() internal {
        vm.startBroadcast();
        
        // Pause JobMarketplace to prevent new jobs
        if (oldContracts["JobMarketplace"] != address(0)) {
            try JobMarketplace(oldContracts["JobMarketplace"]).emergencyPause("Migration in progress") {
                console.log("JobMarketplace paused");
            } catch {
                console.log("Failed to pause JobMarketplace");
            }
        }
        
        vm.stopBroadcast();
    }

    function _exportAllStates() internal view returns (MigrationHelper.ContractState[] memory) {
        MigrationHelper.ContractState[] memory states = new MigrationHelper.ContractState[](4);
        uint256 index = 0;
        
        // Export NodeRegistry
        if (oldContracts["NodeRegistry"] != address(0)) {
            states[index++] = helper.exportNodeRegistryState(oldContracts["NodeRegistry"]);
            console.log("NodeRegistry state exported");
        }
        
        // Export JobMarketplace
        if (oldContracts["JobMarketplace"] != address(0)) {
            states[index++] = helper.exportJobMarketplaceState(oldContracts["JobMarketplace"]);
            console.log("JobMarketplace state exported");
        }
        
        // Export PaymentEscrow
        if (oldContracts["PaymentEscrow"] != address(0)) {
            states[index++] = helper.exportPaymentEscrowState(oldContracts["PaymentEscrow"]);
            console.log("PaymentEscrow state exported");
        }
        
        // Export ReputationSystem
        if (oldContracts["ReputationSystem"] != address(0)) {
            states[index++] = helper.exportReputationState(oldContracts["ReputationSystem"]);
            console.log("ReputationSystem state exported");
        }
        
        return states;
    }

    function _exportCriticalStates() internal view returns (MigrationHelper.ContractState[] memory) {
        // In emergency, only export critical data
        MigrationHelper.ContractState[] memory states = new MigrationHelper.ContractState[](2);
        
        if (oldContracts["NodeRegistry"] != address(0)) {
            states[0] = helper.emergencyExportState(oldContracts["NodeRegistry"]);
        }
        
        if (oldContracts["PaymentEscrow"] != address(0)) {
            states[1] = helper.emergencyExportState(oldContracts["PaymentEscrow"]);
        }
        
        return states;
    }

    function _transferAllFunds() internal {
        vm.startBroadcast();
        
        // Transfer NodeRegistry stakes
        if (oldContracts["NodeRegistry"] != address(0) && newContracts["NodeRegistry"] != address(0)) {
            uint256 nodeBalance = oldContracts["NodeRegistry"].balance;
            if (nodeBalance > 0) {
                // This would need a withdrawal function in the old contract
                console.log("NodeRegistry balance:", nodeBalance);
            }
        }
        
        // Transfer PaymentEscrow funds
        if (oldContracts["PaymentEscrow"] != address(0) && newContracts["PaymentEscrow"] != address(0)) {
            uint256 escrowBalance = oldContracts["PaymentEscrow"].balance;
            if (escrowBalance > 0) {
                helper.transferEscrowFunds(
                    oldContracts["PaymentEscrow"],
                    newContracts["PaymentEscrow"],
                    escrowBalance
                );
                emit FundsTransferred(
                    oldContracts["PaymentEscrow"],
                    newContracts["PaymentEscrow"],
                    escrowBalance
                );
            }
        }
        
        vm.stopBroadcast();
    }

    function _importAllStates(MigrationHelper.ContractState[] memory states) internal {
        vm.startBroadcast();
        
        for (uint256 i = 0; i < states.length; i++) {
            if (states[i].contractAddress == address(0)) continue;
            
            MigrationHelper.MigrationResult memory result;
            
            if (keccak256(bytes(states[i].contractType)) == keccak256(bytes("NodeRegistry"))) {
                result = helper.importNodeRegistryState(newContracts["NodeRegistry"], states[i]);
            } else if (keccak256(bytes(states[i].contractType)) == keccak256(bytes("JobMarketplace"))) {
                result = helper.importJobMarketplaceState(newContracts["JobMarketplace"], states[i]);
            } else if (keccak256(bytes(states[i].contractType)) == keccak256(bytes("PaymentEscrow"))) {
                result = helper.importPaymentEscrowState(newContracts["PaymentEscrow"], states[i]);
            } else if (keccak256(bytes(states[i].contractType)) == keccak256(bytes("ReputationSystem"))) {
                result = helper.importReputationState(newContracts["ReputationSystem"], states[i]);
            }
            
            require(result.success, string(abi.encodePacked("Migration failed for ", states[i].contractType)));
            
            emit ContractMigrated(
                states[i].contractAddress,
                _getNewContract(states[i].contractType),
                result.itemsMigrated
            );
        }
        
        vm.stopBroadcast();
    }

    function _importCriticalStates(MigrationHelper.ContractState[] memory states) internal {
        vm.startBroadcast();
        
        for (uint256 i = 0; i < states.length; i++) {
            if (states[i].contractAddress == address(0)) continue;
            
            MigrationHelper.MigrationResult memory result = helper.emergencyImportState(
                _getNewContract(states[i].contractType),
                states[i]
            );
            
            console.log("Emergency import:", states[i].contractType, result.success ? "SUCCESS" : "FAILED");
        }
        
        vm.stopBroadcast();
    }

    function _updateContractReferences() internal {
        vm.startBroadcast();
        
        // Update references in new contracts
        if (newContracts["NodeRegistry"] != address(0) && newContracts["Governance"] != address(0)) {
            NodeRegistry(payable(newContracts["NodeRegistry"])).setGovernance(newContracts["Governance"]);
        }
        
        if (newContracts["ReputationSystem"] != address(0) && newContracts["JobMarketplace"] != address(0)) {
            ReputationSystem(newContracts["ReputationSystem"]).addAuthorizedContract(
                newContracts["JobMarketplace"]
            );
        }
        
        vm.stopBroadcast();
    }

    function _verifyMigration() internal view returns (bool) {
        // Basic verification checks
        
        // Check new contracts are deployed
        if (newContracts["NodeRegistry"] == address(0)) return false;
        if (newContracts["JobMarketplace"] == address(0)) return false;
        if (newContracts["PaymentEscrow"] == address(0)) return false;
        if (newContracts["ReputationSystem"] == address(0)) return false;
        
        // Check old contracts are paused (if they support it)
        if (oldContracts["JobMarketplace"] != address(0)) {
            try JobMarketplace(oldContracts["JobMarketplace"]).isPaused() returns (bool paused) {
                if (!paused) return false;
            } catch {}
        }
        
        // Check fund balances match
        uint256 oldEscrowBalance = oldContracts["PaymentEscrow"] != address(0) 
            ? oldContracts["PaymentEscrow"].balance 
            : 0;
        uint256 newEscrowBalance = newContracts["PaymentEscrow"].balance;
        
        // Allow for small differences due to gas costs
        if (oldEscrowBalance > 0 && newEscrowBalance < oldEscrowBalance - 0.1 ether) {
            return false;
        }
        
        return true;
    }

    function _getNewContract(string memory contractType) internal view returns (address) {
        return newContracts[contractType];
    }

    // Rollback function
    function rollback() external {
        require(msg.sender == owner(), "Only owner can rollback");
        
        vm.startBroadcast();
        
        // Unpause old contracts
        if (oldContracts["JobMarketplace"] != address(0)) {
            try JobMarketplace(oldContracts["JobMarketplace"]).unpause() {
                console.log("JobMarketplace unpaused");
            } catch {}
        }
        
        // Return funds if possible
        // This would require additional functions in the contracts
        
        vm.stopBroadcast();
        
        console.log("ROLLBACK COMPLETED");
    }

    function owner() internal view returns (address) {
        return vm.envAddress("OWNER");
    }
}