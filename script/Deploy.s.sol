// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/NodeRegistry.sol";
import "../src/JobMarketplace.sol";
import "../src/PaymentEscrow.sol";
import "../src/ReputationSystem.sol";
import "../src/ProofSystem.sol";
import "../src/Governance.sol";
import "../src/GovernanceToken.sol";

contract DeployScript is Script {
    // Deployment parameters
    struct DeploymentParams {
        address deployer;
        address guardian;
        address treasury;
        address arbiter;
        uint256 initialStakeAmount;
        uint256 protocolFeePercent;
        uint256 governanceTokenSupply;
        string governanceTokenName;
        string governanceTokenSymbol;
    }
    
    // Deployed contracts
    struct DeployedContracts {
        NodeRegistry nodeRegistry;
        JobMarketplace jobMarketplace;
        PaymentEscrow paymentEscrow;
        ReputationSystem reputationSystem;
        ProofSystem proofSystem;
        Governance governance;
        GovernanceToken governanceToken;
    }
    
    // Events
    event DeploymentCompleted(
        address nodeRegistry,
        address jobMarketplace,
        address paymentEscrow,
        address reputationSystem,
        address proofSystem,
        address governance,
        address governanceToken
    );
    
    function run() external returns (
        address nodeRegistry,
        address jobMarketplace,
        address paymentEscrow,
        address reputationSystem,
        address proofSystem,
        address governance,
        address governanceToken
    ) {
        // Get deployment parameters from environment
        DeploymentParams memory params = getDeploymentParams();
        
        // Start broadcasting transactions
        vm.startBroadcast(params.deployer);
        
        // Deploy all contracts
        DeployedContracts memory contracts = deployAllContracts(params);
        
        // Configure contracts
        configureContracts(contracts, params);
        
        // Emit deployment event
        emitDeploymentEvent(contracts);
        
        vm.stopBroadcast();
        
        // Log deployment addresses
        console.log("=== Deployment Completed ===");
        console.log("NodeRegistry:", address(contracts.nodeRegistry));
        console.log("JobMarketplace:", address(contracts.jobMarketplace));
        console.log("PaymentEscrow:", address(contracts.paymentEscrow));
        console.log("ReputationSystem:", address(contracts.reputationSystem));
        console.log("ProofSystem:", address(contracts.proofSystem));
        console.log("Governance:", address(contracts.governance));
        console.log("GovernanceToken:", address(contracts.governanceToken));
        
        // Write deployment addresses to file
        writeDeploymentAddresses(contracts);
        
        return (
            address(contracts.nodeRegistry),
            address(contracts.jobMarketplace),
            address(contracts.paymentEscrow),
            address(contracts.reputationSystem),
            address(contracts.proofSystem),
            address(contracts.governance),
            address(contracts.governanceToken)
        );
    }
    
    function getDeploymentParams() internal view returns (DeploymentParams memory) {
        // Get chain-specific parameters
        uint256 chainId = block.chainid;
        
        if (chainId == 8453) {
            // Base mainnet
            return DeploymentParams({
                deployer: vm.envAddress("DEPLOYER_ADDRESS"),
                guardian: vm.envAddress("GUARDIAN_ADDRESS"),
                treasury: vm.envAddress("TREASURY_ADDRESS"),
                arbiter: vm.envAddress("ARBITER_ADDRESS"),
                initialStakeAmount: 100 ether,
                protocolFeePercent: 300, // 3%
                governanceTokenSupply: 10_000_000 * 10**18,
                governanceTokenName: "Fabstir Governance",
                governanceTokenSymbol: "FAB"
            });
        } else if (chainId == 84532) {
            // Base Sepolia
            return DeploymentParams({
                deployer: vm.envAddress("DEPLOYER_ADDRESS"),
                guardian: vm.envAddress("GUARDIAN_ADDRESS"),
                treasury: vm.envAddress("TREASURY_ADDRESS"),
                arbiter: vm.envAddress("ARBITER_ADDRESS"),
                initialStakeAmount: 0.1 ether,
                protocolFeePercent: 100, // 1%
                governanceTokenSupply: 10_000_000 * 10**18,
                governanceTokenName: "Fabstir Governance Test",
                governanceTokenSymbol: "FABT"
            });
        } else {
            // Local development
            address deployer = msg.sender;
            return DeploymentParams({
                deployer: deployer,
                guardian: deployer,
                treasury: deployer,
                arbiter: deployer,
                initialStakeAmount: 10 ether,
                protocolFeePercent: 250, // 2.5%
                governanceTokenSupply: 10_000_000 * 10**18,
                governanceTokenName: "Fabstir Governance Local",
                governanceTokenSymbol: "FABL"
            });
        }
    }
    
    function deployAllContracts(DeploymentParams memory params) 
        internal 
        returns (DeployedContracts memory) 
    {
        console.log("Deploying contracts...");
        
        // Deploy NodeRegistry
        NodeRegistry nodeRegistry = new NodeRegistry(params.initialStakeAmount);
        console.log("NodeRegistry deployed at:", address(nodeRegistry));
        
        // Deploy PaymentEscrow
        PaymentEscrow paymentEscrow = new PaymentEscrow(
            params.arbiter,
            params.protocolFeePercent
        );
        console.log("PaymentEscrow deployed at:", address(paymentEscrow));
        
        // Deploy JobMarketplace
        JobMarketplace jobMarketplace = new JobMarketplace(
            address(nodeRegistry)
        );
        console.log("JobMarketplace deployed at:", address(jobMarketplace));
        
        // Deploy ReputationSystem
        ReputationSystem reputationSystem = new ReputationSystem(
            address(nodeRegistry),
            address(jobMarketplace),
            params.deployer // governance will be updated later
        );
        console.log("ReputationSystem deployed at:", address(reputationSystem));
        
        // Deploy ProofSystem
        ProofSystem proofSystem = new ProofSystem(
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem)
        );
        console.log("ProofSystem deployed at:", address(proofSystem));
        
        // Deploy GovernanceToken
        GovernanceToken governanceToken = new GovernanceToken(
            params.governanceTokenName,
            params.governanceTokenSymbol,
            params.governanceTokenSupply
        );
        console.log("GovernanceToken deployed at:", address(governanceToken));
        
        // Deploy Governance
        Governance governance = new Governance(
            address(governanceToken),
            address(nodeRegistry),
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem),
            address(proofSystem)
        );
        console.log("Governance deployed at:", address(governance));
        
        return DeployedContracts({
            nodeRegistry: nodeRegistry,
            jobMarketplace: jobMarketplace,
            paymentEscrow: paymentEscrow,
            reputationSystem: reputationSystem,
            proofSystem: proofSystem,
            governance: governance,
            governanceToken: governanceToken
        });
    }
    
    function configureContracts(
        DeployedContracts memory contracts,
        DeploymentParams memory params
    ) internal {
        console.log("Configuring contracts...");
        
        // Configure PaymentEscrow
        contracts.paymentEscrow.setJobMarketplace(address(contracts.jobMarketplace));
        console.log("PaymentEscrow configured with JobMarketplace");
        
        // Configure ReputationSystem
        contracts.reputationSystem.addAuthorizedContract(address(contracts.jobMarketplace));
        console.log("ReputationSystem authorized JobMarketplace");
        
        // Configure ProofSystem
        contracts.proofSystem.grantVerifierRole(address(contracts.jobMarketplace));
        console.log("ProofSystem granted verifier role to JobMarketplace");
        
        // Configure NodeRegistry
        contracts.nodeRegistry.setGovernance(address(contracts.governance));
        console.log("NodeRegistry configured with Governance");
        
        // Configure JobMarketplace
        contracts.jobMarketplace.grantRole(keccak256("GUARDIAN_ROLE"), params.guardian);
        console.log("JobMarketplace granted guardian role to:", params.guardian);
        
        console.log("Contract configuration completed");
    }
    
    function emitDeploymentEvent(DeployedContracts memory contracts) internal {
        emit DeploymentCompleted(
            address(contracts.nodeRegistry),
            address(contracts.jobMarketplace),
            address(contracts.paymentEscrow),
            address(contracts.reputationSystem),
            address(contracts.proofSystem),
            address(contracts.governance),
            address(contracts.governanceToken)
        );
    }
    
    function writeDeploymentAddresses(DeployedContracts memory contracts) internal {
        string memory deploymentInfo = string(abi.encodePacked(
            "{\n",
            '  "nodeRegistry": "', vm.toString(address(contracts.nodeRegistry)), '",\n',
            '  "jobMarketplace": "', vm.toString(address(contracts.jobMarketplace)), '",\n',
            '  "paymentEscrow": "', vm.toString(address(contracts.paymentEscrow)), '",\n',
            '  "reputationSystem": "', vm.toString(address(contracts.reputationSystem)), '",\n',
            '  "proofSystem": "', vm.toString(address(contracts.proofSystem)), '",\n',
            '  "governance": "', vm.toString(address(contracts.governance)), '",\n',
            '  "governanceToken": "', vm.toString(address(contracts.governanceToken)), '"\n',
            "}"
        ));
        
        string memory filename = string(abi.encodePacked(
            "deployments/",
            vm.toString(block.chainid),
            "_deployment.json"
        ));
        
        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment addresses written to:", filename);
    }
}