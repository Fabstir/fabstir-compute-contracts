# Multi-Chain Usage Examples

This document provides practical examples of using JobMarketplaceWithModels across different chains and wallet types.

## Table of Contents
- [Native Token Operations](#native-token-operations)
- [Cross-Wallet Interactions](#cross-wallet-interactions)
- [Chain-Specific Examples](#chain-specific-examples)
- [SDK Integration Examples](#sdk-integration-examples)
- [Testing Examples](#testing-examples)

## Native Token Operations

### Example 1: ETH Operations on Base Sepolia

```javascript
// Connect to Base Sepolia
const provider = new ethers.JsonRpcProvider("https://sepolia.base.org");
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

// Contract setup
const marketplace = new ethers.Contract(
    "0xaa38e7fcf5d7944ef7c836e8451f3bf93b98364f",
    MARKETPLACE_ABI,
    wallet
);

// Deposit ETH
const depositTx = await marketplace.depositNative({
    value: ethers.parseEther("1.0")
});
await depositTx.wait();
console.log("Deposited 1 ETH");

// Check balance
const balance = await marketplace.userDepositsNative(wallet.address);
console.log("Native balance:", ethers.formatEther(balance), "ETH");

// Create session with ETH
const sessionTx = await marketplace.createSessionFromDeposit(
    hostAddress,                     // host
    ethers.ZeroAddress,              // native token (ETH)
    ethers.parseEther("0.5"),        // deposit amount
    ethers.parseEther("0.001"),      // price per token
    86400,                           // duration (1 day)
    10                               // proof interval
);
const receipt = await sessionTx.wait();
const sessionId = receipt.logs[0].args.sessionId;
console.log("Created session:", sessionId);

// Withdraw remaining ETH
const withdrawTx = await marketplace.withdrawNative(ethers.parseEther("0.5"));
await withdrawTx.wait();
console.log("Withdrew 0.5 ETH");
```

### Example 2: BNB Operations on opBNB (Future)

```javascript
// Connect to opBNB testnet (future deployment)
const provider = new ethers.JsonRpcProvider("https://opbnb-testnet-rpc.bnbchain.org");
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

// Same interface, different native token
const marketplace = new ethers.Contract(
    OPBNB_MARKETPLACE_ADDRESS, // Future deployment
    MARKETPLACE_ABI,
    wallet
);

// Deposit BNB (same function, different token)
const depositTx = await marketplace.depositNative({
    value: ethers.parseEther("0.1")  // 0.1 BNB
});
await depositTx.wait();
console.log("Deposited 0.1 BNB");

// Chain config will show BNB
const chainConfig = await marketplace.chainConfig();
console.log("Native token:", chainConfig.nativeTokenSymbol); // "BNB"
```

## Cross-Wallet Interactions

### Example 3: Smart Wallet Creates, EOA Completes

```javascript
// Smart wallet creates session
const smartWallet = await SmartWallet.create({
    owner: userAddress,
    entryPoint: "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
});

// Deposit through smart wallet
await smartWallet.execute([{
    target: marketplace.address,
    data: marketplace.interface.encodeFunctionData("depositNative"),
    value: ethers.parseEther("2.0")
}]);

// Create session through smart wallet
await smartWallet.execute([{
    target: marketplace.address,
    data: marketplace.interface.encodeFunctionData("createSessionFromDeposit", [
        hostAddress,
        ethers.ZeroAddress,
        ethers.parseEther("1.0"),
        ethers.parseEther("0.001"),
        86400,
        10
    ])
}]);

// EOA host completes session
const hostWallet = new ethers.Wallet(HOST_PRIVATE_KEY, provider);
const hostMarketplace = marketplace.connect(hostWallet);

// Wait for dispute window
await provider.send("evm_increaseTime", [3601]); // 1 hour + 1 second
await provider.send("evm_mine", []);

// Host completes and gets payment
await hostMarketplace.completeSessionJob(sessionId, "ipfs://conversation");
```

### Example 4: Batch Operations with Smart Wallet

```javascript
// Prepare batch operations
const operations = [
    // 1. Deposit native token
    {
        target: marketplace.address,
        data: marketplace.interface.encodeFunctionData("depositNative"),
        value: ethers.parseEther("3.0")
    },
    // 2. Deposit USDC
    {
        target: usdcContract.address,
        data: usdcContract.interface.encodeFunctionData("approve", [
            marketplace.address,
            ethers.parseUnits("1000", 6)
        ])
    },
    {
        target: marketplace.address,
        data: marketplace.interface.encodeFunctionData("depositToken", [
            usdcContract.address,
            ethers.parseUnits("1000", 6)
        ])
    },
    // 3. Create multiple sessions
    {
        target: marketplace.address,
        data: marketplace.interface.encodeFunctionData("createSessionFromDeposit", [
            host1Address,
            ethers.ZeroAddress,
            ethers.parseEther("1.0"),
            ethers.parseEther("0.001"),
            86400,
            10
        ])
    },
    {
        target: marketplace.address,
        data: marketplace.interface.encodeFunctionData("createSessionFromDeposit", [
            host2Address,
            usdcContract.address,
            ethers.parseUnits("500", 6),
            ethers.parseUnits("1", 6),
            86400,
            10
        ])
    }
];

// Execute all in one transaction
await smartWallet.executeBatch(operations);
```

## Chain-Specific Examples

### Example 5: Checking Chain Configuration

```javascript
async function getChainInfo(marketplaceAddress, providerUrl) {
    const provider = new ethers.JsonRpcProvider(providerUrl);
    const marketplace = new ethers.Contract(
        marketplaceAddress,
        MARKETPLACE_ABI,
        provider
    );

    const chainConfig = await marketplace.chainConfig();

    console.log("Chain Configuration:");
    console.log("- Native Token:", chainConfig.nativeTokenSymbol);
    console.log("- Native Wrapper:", chainConfig.nativeWrapper);
    console.log("- Stablecoin:", chainConfig.stablecoin);
    console.log("- Min Deposit:", ethers.formatEther(chainConfig.minDeposit));

    return chainConfig;
}

// Check Base Sepolia
await getChainInfo(
    "0xaa38e7fcf5d7944ef7c836e8451f3bf93b98364f",
    "https://sepolia.base.org"
);
// Output: Native Token: ETH, Min Deposit: 0.0002 ETH

// Check opBNB (future)
await getChainInfo(
    OPBNB_MARKETPLACE_ADDRESS,
    "https://opbnb-testnet-rpc.bnbchain.org"
);
// Output: Native Token: BNB, Min Deposit: 0.01 BNB
```

### Example 6: Multi-Chain Balance Query

```javascript
async function getAllBalances(userAddress, chains) {
    const balances = {};

    for (const chain of chains) {
        const provider = new ethers.JsonRpcProvider(chain.rpcUrl);
        const marketplace = new ethers.Contract(
            chain.marketplaceAddress,
            MARKETPLACE_ABI,
            provider
        );

        // Get native and token balances
        const nativeBalance = await marketplace.userDepositsNative(userAddress);
        const usdcBalance = await marketplace.userDepositsToken(
            userAddress,
            chain.usdcAddress
        );

        balances[chain.name] = {
            native: {
                amount: ethers.formatEther(nativeBalance),
                symbol: chain.nativeSymbol
            },
            usdc: ethers.formatUnits(usdcBalance, 6)
        };
    }

    return balances;
}

// Query across chains
const userBalances = await getAllBalances(userAddress, [
    {
        name: "Base Sepolia",
        rpcUrl: "https://sepolia.base.org",
        marketplaceAddress: "0xaa38e7fcf5d7944ef7c836e8451f3bf93b98364f",
        usdcAddress: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
        nativeSymbol: "ETH"
    },
    // Add more chains as deployed
]);
```

## SDK Integration Examples

### Example 7: TypeScript SDK with Multi-Chain Support

```typescript
interface ChainConfig {
    chainId: number;
    rpcUrl: string;
    marketplaceAddress: string;
    nativeSymbol: string;
}

class MultiChainMarketplace {
    private providers: Map<number, ethers.Provider>;
    private contracts: Map<number, ethers.Contract>;

    constructor(private chains: ChainConfig[]) {
        this.providers = new Map();
        this.contracts = new Map();

        for (const chain of chains) {
            const provider = new ethers.JsonRpcProvider(chain.rpcUrl);
            const contract = new ethers.Contract(
                chain.marketplaceAddress,
                MARKETPLACE_ABI,
                provider
            );

            this.providers.set(chain.chainId, provider);
            this.contracts.set(chain.chainId, contract);
        }
    }

    async deposit(
        chainId: number,
        amount: bigint,
        signer: ethers.Signer
    ): Promise<ethers.TransactionReceipt> {
        const contract = this.contracts.get(chainId);
        if (!contract) throw new Error(`Chain ${chainId} not configured`);

        const connectedContract = contract.connect(signer);
        const tx = await connectedContract.depositNative({ value: amount });
        return await tx.wait();
    }

    async createSession(
        chainId: number,
        params: SessionParams,
        signer: ethers.Signer
    ): Promise<bigint> {
        const contract = this.contracts.get(chainId);
        if (!contract) throw new Error(`Chain ${chainId} not configured`);

        const connectedContract = contract.connect(signer);
        const tx = await connectedContract.createSessionFromDeposit(
            params.host,
            params.token,
            params.deposit,
            params.pricePerToken,
            params.duration,
            params.proofInterval
        );

        const receipt = await tx.wait();
        return receipt.logs[0].args.sessionId;
    }

    async getBalances(
        userAddress: string,
        chainId?: number
    ): Promise<Record<string, any>> {
        if (chainId) {
            const contract = this.contracts.get(chainId);
            if (!contract) throw new Error(`Chain ${chainId} not configured`);

            return {
                native: await contract.userDepositsNative(userAddress),
                tokens: {} // Query specific tokens
            };
        }

        // Get balances across all chains
        const balances: Record<number, any> = {};
        for (const [id, contract] of this.contracts) {
            balances[id] = {
                native: await contract.userDepositsNative(userAddress)
            };
        }
        return balances;
    }
}

// Usage
const marketplace = new MultiChainMarketplace([
    {
        chainId: 84532, // Base Sepolia
        rpcUrl: "https://sepolia.base.org",
        marketplaceAddress: "0xaa38e7fcf5d7944ef7c836e8451f3bf93b98364f",
        nativeSymbol: "ETH"
    }
    // Add more chains as deployed
]);

// Deposit on Base Sepolia
await marketplace.deposit(84532, ethers.parseEther("1.0"), signer);

// Get balances across all chains
const balances = await marketplace.getBalances(userAddress);
```

### Example 8: React Hook for Multi-Chain

```typescript
import { useState, useEffect } from 'react';
import { useAccount, useChainId } from 'wagmi';

function useMultiChainBalance() {
    const { address } = useAccount();
    const chainId = useChainId();
    const [balances, setBalances] = useState<Record<number, any>>({});
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (!address) return;

        async function fetchBalances() {
            setLoading(true);
            try {
                const marketplace = new MultiChainMarketplace(SUPPORTED_CHAINS);
                const allBalances = await marketplace.getBalances(address);
                setBalances(allBalances);
            } catch (error) {
                console.error("Failed to fetch balances:", error);
            } finally {
                setLoading(false);
            }
        }

        fetchBalances();
    }, [address, chainId]);

    return { balances, loading, currentChainBalance: balances[chainId] };
}

// Component usage
function BalanceDisplay() {
    const { balances, loading, currentChainBalance } = useMultiChainBalance();

    if (loading) return <div>Loading balances...</div>;

    return (
        <div>
            <h3>Current Chain Balance</h3>
            <p>{ethers.formatEther(currentChainBalance?.native || 0n)} ETH</p>

            <h3>All Chain Balances</h3>
            {Object.entries(balances).map(([chainId, balance]) => (
                <div key={chainId}>
                    Chain {chainId}: {ethers.formatEther(balance.native)}
                </div>
            ))}
        </div>
    );
}
```

## Testing Examples

### Example 9: Forge Test for Multi-Chain

```solidity
// test/MultiChainScenario.t.sol
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/JobMarketplaceWithModels.sol";

contract MultiChainScenarioTest is Test {
    JobMarketplaceWithModels marketplace;
    address user = address(0x1);
    address host = address(0x2);

    function setUp() public {
        // Deploy with Base config
        marketplace = new JobMarketplaceWithModels(...);

        // Initialize as Base Sepolia
        JobMarketplaceWithModels.ChainConfig memory baseConfig =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: 0x4200000000000000000000000000000000000006,
                stablecoin: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,
                minDeposit: 0.0002 ether,
                nativeTokenSymbol: "ETH"
            });
        marketplace.initializeChainConfig(baseConfig);
    }

    function test_MultiChainDepositPattern() public {
        // User deposits ETH
        vm.deal(user, 10 ether);
        vm.prank(user);
        marketplace.depositNative{value: 1 ether}();

        // Check balance shows correctly
        assertEq(marketplace.userDepositsNative(user), 1 ether);

        // Create session using deposit
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDeposit(
            host,
            address(0), // native token
            0.5 ether,
            0.001 ether,
            1 days,
            10
        );

        // Balance reduced
        assertEq(marketplace.userDepositsNative(user), 0.5 ether);

        // Session created with correct depositor
        (,,,,,,,,, address depositor,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(depositor, user);
    }

    function test_SimulateOpBNB() public {
        // Re-initialize as opBNB
        vm.prank(address(marketplace));
        JobMarketplaceWithModels.ChainConfig memory bnbConfig =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: address(0x9999), // Mock WBNB
                stablecoin: address(0x8888),    // Mock USDC on opBNB
                minDeposit: 0.01 ether,
                nativeTokenSymbol: "BNB"
            });

        // Would fail - already initialized
        vm.expectRevert("Chain config already initialized");
        marketplace.initializeChainConfig(bnbConfig);
    }
}
```

### Example 10: JavaScript Integration Test

```javascript
// test/integration/multichain.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Multi-Chain Integration", function () {
    let marketplace;
    let user, host;

    beforeEach(async function () {
        [user, host] = await ethers.getSigners();

        // Deploy and configure for Base
        const Marketplace = await ethers.getContractFactory("JobMarketplaceWithModels");
        marketplace = await Marketplace.deploy(...);

        await marketplace.initializeChainConfig({
            nativeWrapper: "0x4200000000000000000000000000000000000006",
            stablecoin: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
            minDeposit: ethers.parseEther("0.0002"),
            nativeTokenSymbol: "ETH"
        });
    });

    it("Should handle ETH deposits and withdrawals", async function () {
        // Deposit
        await marketplace.connect(user).depositNative({
            value: ethers.parseEther("1.0")
        });

        // Check balance
        const balance = await marketplace.userDepositsNative(user.address);
        expect(balance).to.equal(ethers.parseEther("1.0"));

        // Withdraw
        await marketplace.connect(user).withdrawNative(ethers.parseEther("0.5"));

        // Check updated balance
        const newBalance = await marketplace.userDepositsNative(user.address);
        expect(newBalance).to.equal(ethers.parseEther("0.5"));
    });

    it("Should work with smart wallets", async function () {
        // Deploy mock smart wallet
        const SmartWallet = await ethers.getContractFactory("MockSmartWallet");
        const smartWallet = await SmartWallet.deploy(user.address);

        // Fund smart wallet
        await user.sendTransaction({
            to: smartWallet.address,
            value: ethers.parseEther("2.0")
        });

        // Execute deposit through smart wallet
        await smartWallet.execute(
            marketplace.address,
            ethers.parseEther("1.0"),
            marketplace.interface.encodeFunctionData("depositNative")
        );

        // Balance tracked to smart wallet address
        const balance = await marketplace.userDepositsNative(smartWallet.address);
        expect(balance).to.equal(ethers.parseEther("1.0"));
    });
});
```

## Summary

These examples demonstrate:

1. **Chain Agnostic**: Same interface works across ETH and BNB chains
2. **Wallet Agnostic**: Supports EOA, Smart Wallets, and Account Abstraction
3. **Flexible Patterns**: Inline payments or pre-funded deposits
4. **Gasless Options**: Anyone-can-complete enables gasless user experience
5. **SDK Ready**: Easy integration with TypeScript/JavaScript SDKs
6. **Testing Coverage**: Comprehensive test patterns for all scenarios

The multi-chain architecture ensures that as new chains are added, existing integrations continue to work with minimal changes.