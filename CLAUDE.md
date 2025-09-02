# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the smart contracts repository for Fabstir P2P LLM marketplace on Base L2. The contracts enable direct host-renter interactions for AI model inference without centralized coordination.

## Development Commands

```bash
# Build contracts
forge build

# Run all tests
forge test

# Run tests with verbose output (logs)
forge test -vv

# Run tests with execution traces for failures
forge test -vvv

# Run specific test file
forge test --match-path test/NodeRegistry/test_registration.t.sol

# Run specific test function
forge test --match-test test_RegisterNode

# Run tests matching a contract name
forge test --match-contract NodeRegistryTest

# Format code
forge fmt

# Gas snapshots
forge snapshot

# Local node
anvil

# Deploy (example)
forge script script/Deploy.s.sol:DeployScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

## Architecture Overview

### Core System Design

The marketplace operates on a decentralized model where:
- **Hosts** register GPU nodes and stake ETH to participate
- **Renters** post jobs requiring specific AI models
- **Payment** is escrowed until job completion
- **Reputation** tracks host performance for quality-based routing
- **Governance** enables protocol upgrades via token voting

### Core Contracts

1. **NodeRegistry** (`src/NodeRegistry.sol`): Host registration and staking
   - Minimum stake: 100 ETH
   - Tracks node capabilities (models, regions)
   - Supports both direct registration and ERC-4337 account abstraction

2. **JobMarketplace** (`src/JobMarketplace.sol`): Job lifecycle management
   - States: Posted → Claimed → Completed
   - Integrates with NodeRegistry for host verification
   - Holds payment in escrow during execution
   - Enforces deadlines and access control
   - Supports USDC payments (Base Sepolia: 0x036CbD53842c5426634e7929541eC2318f3dCF7e)

3. **PaymentEscrow** (`src/PaymentEscrow.sol`): Multi-token payment handling
   - Supports ETH and ERC20 tokens
   - Automatic release on job completion
   - Refund mechanism for failed jobs

4. **ReputationSystem** (`src/ReputationSystem.sol`): Quality-based host routing
   - Tracks success rates and performance metrics
   - Used by marketplace for host selection
   - Affects job assignment priority

5. **ProofSystem** (`src/ProofSystem.sol`): EZKL-based proof verification
   - Verifies correctness of AI model outputs
   - Integrates with JobMarketplace for completion validation
   - Supports various proof types

6. **BaseAccountIntegration** (`src/BaseAccountIntegration.sol`): ERC-4337 support
   - Enables gasless transactions for users
   - Batch operations for efficiency
   - Integrates with all core contracts

7. **Governance** (`src/Governance.sol`) & **GovernanceToken** (`src/GovernanceToken.sol`)
   - OpenZeppelin Governor implementation
   - ERC20Votes token for voting power
   - Timelock controller for execution delay

### Contract Dependencies

```
NodeRegistry ← JobMarketplace → PaymentEscrow
     ↑              ↓                ↓
     |         ReputationSystem      |
     |              ↓                |
     └── BaseAccountIntegration ─────┘
                    ↓
               ProofSystem
```

## Testing Structure

```
test/
├── TestSetup.t.sol           # Base test contract with common setup
├── Setup/                    # Project structure tests
├── NodeRegistry/            # Host registration tests
├── JobMarketplace/          # Job lifecycle tests  
├── PaymentEscrow/           # Payment handling tests
├── Reputation/              # Reputation system tests
├── BaseAccount/             # ERC-4337 integration tests
├── ProofSystem/             # Proof verification tests
├── Governance/              # Governance mechanism tests
└── mocks/                   # Mock contracts for testing
```

## Key Implementation Details

### Payment & Economics
- Native ETH used for host staking (100 ETH minimum)
- Jobs support both ETH and ERC20 token payments
- USDC integration on Base Sepolia (0x036CbD53842c5426634e7929541eC2318f3dCF7e)
- Payment held in escrow until job completion
- No slashing mechanism implemented yet

### Security Considerations
- All contracts use reentrancy guards where applicable
- Access control via OpenZeppelin contracts
- Deadline enforcement prevents indefinite job claims
- No dispute resolution mechanism yet implemented

### Gas Optimization
- Batch operations supported via BaseAccountIntegration
- Efficient storage patterns for node and job data
- Events used for off-chain indexing

## Deployment

- **Target Network**: Base L2 mainnet
- **Testnet**: Base Sepolia
- **Local Development**: Anvil

### Recent Deployments
- Earnings Accumulation System deployed to Base Sepolia
- JobMarketplaceFABWithEarnings: `0xEB646BF2323a441698B256623F858c8787d70f9F`
- PaymentEscrowWithEarnings: `0x7abC91AF9E5aaFdc954Ec7a02238d0796Bbf9a3C`
- HostEarnings: `0xcbD91249cC8A7634a88d437Eaa083496C459Ef4E`

### Deploy Fresh Test Environment

When testing, you can deploy a fresh set of contracts to get a clean state:

```bash
# Quick deploy fresh test environment
./scripts/deploy-fresh-test.sh
```

This will:
- Deploy new JobMarketplace, PaymentEscrow, and HostEarnings contracts
- Job IDs start from 1 (clean slate)
- Keep existing NodeRegistry, FAB token, and USDC contracts
- Automatically configure all contract relationships
- Display new addresses to update in your client

After deployment, update your client with the new addresses shown in output.
See `docs/TEST_DEPLOYMENT.md` for detailed instructions.

## External Dependencies

- OpenZeppelin Contracts (v5.x)
- Forge Standard Library
- EZKL verifier contracts (for ProofSystem)

## USDC Job Posting

When posting jobs with USDC, ensure all struct fields are provided:

### JobDetails struct (6 fields required)
- modelId, prompt, maxTokens, temperature
- seed (uint32)
- resultFormat (string)

### JobRequirements struct (4 fields required)  
- minGPUMemory, maxTimeToComplete
- minReputationScore (uint256)
- requiresProof (bool)

See `docs/USDC_JOB_FIX.md` for detailed frontend integration guide.