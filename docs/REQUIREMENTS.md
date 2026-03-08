# Fabstir Compute Contracts - Formal Requirements Specification

**Version:** 2.0
**Last Updated:** March 8, 2026
**Status:** Production (Base Sepolia Testnet) — Post-Audit Remediation

---

## 1. System Purpose

### 1.1 Mission Statement

Fabstir Compute is a **decentralized peer-to-peer AI inference marketplace** that enables trustless, pay-per-token AI model inference by connecting GPU hosts with users seeking AI services, secured by cryptographic proofs and economic staking.

### 1.2 Problem Statement

Current AI inference services suffer from:
- **Centralization**: Single points of failure and control
- **Opaque pricing**: Users cannot verify they are charged fairly
- **Trust requirements**: Users must trust providers to deliver promised compute
- **Payment inefficiency**: Upfront payments for uncertain usage

### 1.3 Solution

Fabstir Compute solves these problems by:
- **Decentralization**: Any GPU owner can become a host
- **Transparent pricing**: On-chain price discovery and verification
- **Trustless operation**: Economic bonds (staking) secure honest behavior
- **Pay-per-token**: Users pay only for tokens actually generated

### 1.4 Target Users

| User Type | Description | Primary Actions |
|-----------|-------------|-----------------|
| **AI Users** | Developers, applications, end-users needing AI inference | Create sessions, pay for inference |
| **GPU Hosts** | Operators with GPU hardware running AI models | Register nodes, serve inference, earn fees |
| **FAB Holders** | Token holders participating in governance | Vote on model proposals |
| **Protocol Operators** | Fabstir team managing upgrades | Deploy, upgrade, configure contracts |

---

## 2. Actors and Roles

### 2.1 Actor Definitions

| Actor | Description | Authentication | Trust Level |
|-------|-------------|----------------|-------------|
| **Owner** | Contract deployer and governance administrator | Private key holder of deployment address | Highest - can upgrade contracts, pause system |
| **Host** | AI node operator providing GPU compute | Registered in NodeRegistry + staked FAB | Medium - economically bonded, can be slashed |
| **Depositor** | User paying for AI inference services | Any EOA or contract with funds | Low - only controls own sessions |
| **Treasury** | Protocol fee recipient address | Configured by owner | N/A - passive recipient |
| **Anyone** | Any external caller | None required | Lowest - limited to public functions |
| **Authorized Caller** | Contract authorized to call protected functions | Whitelisted by owner | Medium - inter-contract calls |

### 2.2 Actor Authentication

```
┌─────────────────────────────────────────────────────────────┐
│                    Authentication Flow                       │
├─────────────────────────────────────────────────────────────┤
│  Owner        → OwnableUpgradeable.onlyOwner modifier       │
│  Host         → nodes[msg.sender].operator != address(0)    │
│                 + nodes[msg.sender].active == true          │
│  Depositor    → sessionJobs[id].depositor == msg.sender     │
│  Authorized   → authorizedCallers[msg.sender] == true       │
│  Anyone       → No authentication required                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Actor Privileges Matrix

### 3.1 JobMarketplaceWithModelsUpgradeable

| Function | Owner | Admin† | Host | Depositor | Delegate | Treasury | Anyone |
|----------|:-----:|:------:|:----:|:---------:|:--------:|:--------:|:------:|
| `initialize()` | ✓ (once) | - | - | - | - | - | - |
| `pause()` / `unpause()` | ✓ | ✓ | - | - | - | - | - |
| `setTreasury()` | ✓ | - | - | - | - | - | - |
| `setUsdcAddress()` | ✓ | - | - | - | - | - | - |
| `setProofSystem()` | ✓ | ✓ | - | - | - | - | - |
| `setMinTokensFee()` | ✓ | - | - | - | - | - | - |
| `initializeChainConfig()` | ✓ | ✓ | - | - | - | - | - |
| `addAcceptedToken()` | ✓ | ✓ | - | - | - | - | - |
| `updateTokenMinDeposit()` | ✓ | ✓ | - | - | - | - | - |
| `updateTokenMaxDeposit()` | ✓ | ✓ | - | - | - | - | - |
| `createSessionJobForModel()` | - | - | - | ✓ | - | - | - |
| `createSessionJobForModelWithToken()` | - | - | - | ✓ | - | - | - |
| `createSessionFromDepositForModel()` | - | - | - | ✓ | - | - | - |
| `createSessionForModelAsDelegate()` | - | - | - | ✓ | ✓ | - | - |
| `depositNative()` / `depositToken()` | - | - | - | ✓ | - | - | - |
| `withdrawNative()` / `withdrawToken()` | - | - | - | ✓ | - | - | - |
| `authorizeDelegate()` | - | - | - | ✓ | - | - | - |
| `configureDelegate()` | - | - | - | ✓ | - | - | - |
| `submitProofOfWork()` | - | - | ✓* | - | - | - | - |
| `completeSessionJob()` | - | - | ✓* | ✓* | - | - | - |
| `triggerSessionTimeout()` | - | - | - | - | - | - | ✓ |
| `withdrawTreasuryNative()` | - | - | - | - | - | ✓ | - |
| `withdrawTreasuryTokens()` | - | - | - | - | - | ✓ | - |
| `withdrawAllTreasuryFees()` | - | - | - | - | - | ✓ | - |
| `upgradeToAndCall()` | ✓ | - | - | - | - | - | - |

*\* Only for sessions where actor is the host or depositor*

*† Admin = Owner OR Treasury address*

### 3.2 NodeRegistryWithModelsUpgradeable

| Function | Owner | Slashing Auth | Host | Anyone |
|----------|:-----:|:-------------:|:----:|:------:|
| `initialize()` | ✓ (once) | - | - | - |
| `registerNode()` | - | - | - | ✓‡ |
| `unregisterNode()` | - | - | ✓ | - |
| `updateSupportedModels()` | - | - | ✓ | - |
| `updateMetadata()` | - | - | ✓ | - |
| `updateApiUrl()` | - | - | ✓ | - |
| `setModelTokenPricing()` | - | - | ✓ | - |
| `clearModelTokenPricing()` | - | - | ✓ | - |
| `stake()` | - | - | ✓ | - |
| `updateModelRegistry()` | ✓ | - | - | - |
| `setSlashingAuthority()` | ✓ | - | - | - |
| `setTreasury()` | ✓ | - | - | - |
| `initializeSlashing()` | ✓ | - | - | - |
| `slashStake()` | - | ✓ | - | - |
| `repairCorruptNode()` | ✓ | - | - | - |
| `upgradeToAndCall()` | ✓ | - | - | - |
| `getModelPricing()` | - | - | - | ✓ |
| `getHostModelPrices()` | - | - | - | ✓ |
| `getNodeFullInfo()` | - | - | - | ✓ |
| `isActiveNode()` | - | - | - | ✓ |

*‡ Anyone with sufficient FAB stake can register as a host*

### 3.3 ModelRegistryUpgradeable

| Function | Owner | Anyone |
|----------|:-----:|:------:|
| `initialize()` | ✓ (once) | - |
| `addTrustedModel()` | ✓ | - |
| `batchAddTrustedModels()` | ✓ | - |
| `deactivateModel()` | ✓ | - |
| `reactivateModel()` | ✓ | - |
| `setModelRateLimit()` | ✓ | - |
| `withdrawRejectedFees()` | ✓ | - |
| `proposeModel()` | - | ✓ |
| `voteOnProposal()` | - | ✓ |
| `executeProposal()` | - | ✓ |
| `withdrawVotes()` | - | ✓ |
| `upgradeToAndCall()` | ✓ | - |
| `isModelApproved()` | - | ✓ |
| `isTrustedModel()` | - | ✓ |
| `getModelRateLimit()` | - | ✓ |

### 3.4 ProofSystemUpgradeable

| Function | Owner | AC | Anyone |
|----------|:-----:|:--:|:------:|
| `initialize()` | ✓ (once) | - | - |
| `setAuthorizedCaller()` | ✓ | - | - |
| `markProofUsed()` | - | ✓ | - |
| `upgradeToAndCall()` | ✓ | - | - |

*AC = Authorized Caller (JobMarketplace)*

> **Note**: Signature verification functions (`recordVerifiedProof`, `verifyHostSignature`, `verifyAndMarkComplete`, `verifyBatch`, `registerModelCircuit`) were removed as dead code — proof authentication is handled by `msg.sender == host` check in JobMarketplace.

### 3.5 HostEarningsUpgradeable

| Function | Owner | AC | Host | Anyone |
|----------|:-----:|:--:|:----:|:------:|
| `initialize()` | ✓ (once) | - | - | - |
| `setAuthorizedCaller()` | ✓ | - | - | - |
| `creditEarnings()` | - | ✓ | - | - |
| `withdraw()` | - | - | ✓ | - |
| `withdrawAll()` | - | - | ✓ | - |
| `withdrawMultiple()` | - | - | ✓ | - |
| `rescueTokens()` | ✓ | - | - | - |
| `upgradeToAndCall()` | ✓ | - | - | - |
| `getBalance()` | - | - | - | ✓ |
| `getBalances()` | - | - | - | ✓ |
| `getTokenStats()` | - | - | - | ✓ |

*AC = Authorized Caller (JobMarketplace)*

---

## 4. System Invariants

### 4.1 Fund Safety Invariants

| ID | Invariant | Enforcement |
|----|-----------|-------------|
| **FS-1** | Total withdrawable ≤ Total deposited - Total withdrawn | Balance tracking in sessionJobs |
| **FS-2** | Host cannot claim more than session deposit | `tokensUsed * pricePerToken <= deposit` check |
| **FS-3** | Session deposits are locked until completion/timeout | State machine prevents early withdrawal |
| **FS-4** | Treasury receives exactly FEE_BASIS_POINTS/10000 of host payment | Calculation in `_settleSessionPayments()` |
| **FS-5** | Refund = deposit - (tokensUsed × pricePerToken) | Calculated atomically in completion |
| **FS-6** | Host stake cannot be withdrawn while active | `unregisterNode()` requires full withdrawal |

### 4.2 State Machine Invariants

| ID | Invariant | Enforcement |
|----|-----------|-------------|
| **SM-1** | Session state transitions: Active → Completed/TimedOut | Status enum and require checks |
| **SM-2** | Completed sessions cannot be modified | `require(status == SessionStatus.Active)` |
| **SM-3** | Proofs can only be submitted to active sessions | Status check in `submitProofOfWork()` |
| **SM-4** | Timeout triggers after proofTimeoutWindow elapses or session exceeds maxDuration | Time check in `triggerSessionTimeout()` |
| **SM-5** | tokensUsed monotonically increases | `tokensUsed += tokensClaimed` only |

### 4.3 Access Control Invariants

| ID | Invariant | Enforcement |
|----|-----------|-------------|
| **AC-1** | Only session host can submit proofs | `require(session.host == msg.sender)` |
| **AC-2** | Only owner can upgrade contracts | `_authorizeUpgrade()` with onlyOwner |
| **AC-3** | Only owner/treasury can pause/unpause | `require(msg.sender == treasuryAddress \|\| msg.sender == owner())` |
| **AC-4** | Only registered nodes can serve sessions | Host validation in session creation |
| **AC-5** | Only owner can add trusted models | `onlyOwner` on `addTrustedModel()` |
| **AC-6** | Delegates can only spend authorized depositor's funds | `delegateConfigs` checked in `createSessionForModelAsDelegate()` |
| **AC-7** | Delegate spending cannot exceed configured caps | `maxPerSession` and `totalCap` enforced before session creation |
| **AC-8** | Only slashing authority can slash host stakes | `onlySlashingAuthority` modifier |

### 4.4 Economic Invariants

| ID | Invariant | Enforcement |
|----|-----------|-------------|
| **EC-1** | Host must stake MIN_STAKE (1000 FAB) to register | `require` in `registerNode()` |
| **EC-2** | Session price ≥ host model-token price | Price validation via `getModelPricing()` in session creation |
| **EC-3** | Model proposal requires PROPOSAL_FEE (100 FAB) | Transfer in `proposeModel()` |
| **EC-4** | Approval requires APPROVAL_THRESHOLD (100k FAB votes) | Check in `executeProposal()` |

---

## 5. Security Assumptions

### 5.1 Trust Model

```
┌─────────────────────────────────────────────────────────────┐
│                      Trust Hierarchy                         │
├─────────────────────────────────────────────────────────────┤
│  TRUSTED:                                                   │
│    • Owner key is secure and not compromised               │
│    • OpenZeppelin contracts are correctly implemented       │
│    • EVM execution is deterministic                         │
│                                                             │
│  ECONOMICALLY SECURED:                                      │
│    • Hosts behave honestly due to stake at risk            │
│    • Hosts submit accurate token counts (stake at risk)     │
│    • FAB token has market value (stake is meaningful)       │
│                                                             │
│  UNTRUSTED:                                                 │
│    • External callers (anyone)                              │
│    • Depositors (only trust own sessions)                   │
│    • Network participants (MEV, front-running possible)     │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Cryptographic Assumptions

| Assumption | Basis |
|------------|-------|
| SHA256/Keccak256 are collision-resistant | Standard assumption |
| Block timestamps accurate within 15 seconds | Ethereum consensus rules |

### 5.3 Economic Security Assumptions

| Assumption | Mitigation if Violated |
|------------|------------------------|
| Host stake (1000 FAB) exceeds attack profit | Adjustable MIN_STAKE, reputation system |
| FAB token maintains value | Minimum stake adjustable by governance |
| Hosts won't collude at scale | Distributed host network, monitoring |

### 5.4 Operational Assumptions

| Assumption | Dependency |
|------------|------------|
| Owner key management is secure | Multi-sig recommended for production |
| Contract upgrades are tested | Upgrade testing in staging environment |
| Treasury address is valid | Owner responsibility to configure |

---

## 6. Functional Requirements

### 6.1 Host Registration (FR-HOST)

| ID | Requirement | Contract | Function |
|----|-------------|----------|----------|
| FR-HOST-1 | Host must stake minimum 1000 FAB tokens | NodeRegistry | `registerNode()` |
| FR-HOST-2 | Host must specify at least one approved model | NodeRegistry | `registerNode()` |
| FR-HOST-3 | Host must provide non-empty metadata and API URL | NodeRegistry | `registerNode()` |
| FR-HOST-4 | Host must set per-model per-token pricing for each model+token combo | NodeRegistry | `setModelTokenPricing()` |
| FR-HOST-5 | Host can update pricing per model per token while active | NodeRegistry | `setModelTokenPricing()` |
| FR-HOST-6 | Host can unregister and reclaim stake | NodeRegistry | `unregisterNode()` |
| FR-HOST-7 | Host can add additional stake | NodeRegistry | `stake()` |
| FR-HOST-8 | Slashing authority can slash host stake with evidence | NodeRegistry | `slashStake()` |

### 6.2 Session Management (FR-SESSION)

| ID | Requirement | Contract | Function |
|----|-------------|----------|----------|
| FR-SESSION-1 | Depositor can create session with ETH | JobMarketplace | `createSessionJobForModel()` |
| FR-SESSION-2 | Depositor can create session with USDC | JobMarketplace | `createSessionJobForModelWithToken()` |
| FR-SESSION-3 | Session price must meet host minimum | JobMarketplace | Session creation |
| FR-SESSION-4 | Session must specify approved model | JobMarketplace | Session creation |
| FR-SESSION-5 | Host can submit proofs with CID evidence | JobMarketplace | `submitProofOfWork()` |
| FR-SESSION-6 | Proofs include proofCID and deltaCID for audit trail | JobMarketplace | `submitProofOfWork()` |
| FR-SESSION-7 | Session completion requires conversationCID | JobMarketplace | `completeSessionJob()` |
| FR-SESSION-8 | Session can be completed by host or depositor | JobMarketplace | `completeSessionJob()` |
| FR-SESSION-9 | Inactive session can be timed out by anyone | JobMarketplace | `triggerSessionTimeout()` |

### 6.3 Delegated Sessions (FR-DELEGATE)

| ID | Requirement | Contract | Function |
|----|-------------|----------|----------|
| FR-DELEGATE-1 | Depositor can authorize a delegate sub-account | JobMarketplace | `authorizeDelegate()` |
| FR-DELEGATE-2 | Depositor can configure delegate with spending limits | JobMarketplace | `configureDelegate()` |
| FR-DELEGATE-3 | Delegate config supports per-session cap, total cap, expiry, host/model scope | JobMarketplace | `configureDelegate()` |
| FR-DELEGATE-4 | Delegate can create sessions using depositor's funds | JobMarketplace | `createSessionForModelAsDelegate()` |
| FR-DELEGATE-5 | Delegate spending is tracked and enforced against caps | JobMarketplace | `createSessionForModelAsDelegate()` |
| FR-DELEGATE-6 | Session ownership stays with depositor (refunds go to depositor) | JobMarketplace | `createSessionForModelAsDelegate()` |
| FR-DELEGATE-7 | Depositor can revoke delegate authorization | JobMarketplace | `authorizeDelegate(delegate, false)` |

### 6.4 Deposit Management (FR-DEPOSIT)

| ID | Requirement | Contract | Function |
|----|-------------|----------|----------|
| FR-DEPOSIT-1 | Depositor can pre-deposit ETH | JobMarketplace | `depositNative()` |
| FR-DEPOSIT-2 | Depositor can pre-deposit ERC20 tokens | JobMarketplace | `depositToken()` |
| FR-DEPOSIT-3 | Depositor can create sessions from pre-deposited funds | JobMarketplace | `createSessionFromDepositForModel()` |
| FR-DEPOSIT-4 | Depositor can withdraw unused deposited funds | JobMarketplace | `withdrawNative()` / `withdrawToken()` |
| FR-DEPOSIT-5 | Locked balances (in active sessions) cannot be withdrawn | JobMarketplace | Balance tracking |

### 6.5 Payment Settlement (FR-PAYMENT)

| ID | Requirement | Contract | Function |
|----|-------------|----------|----------|
| FR-PAYMENT-1 | Host receives 90% of tokens used × price | JobMarketplace | `_settleSessionPayments()` |
| FR-PAYMENT-2 | Treasury receives 10% fee | JobMarketplace | `_settleSessionPayments()` |
| FR-PAYMENT-3 | Depositor receives refund of unused deposit | JobMarketplace | `_settleSessionPayments()` |
| FR-PAYMENT-4 | Host earnings accumulate in HostEarnings | HostEarnings | `creditEarnings*()` |
| FR-PAYMENT-5 | Host can withdraw accumulated earnings | HostEarnings | `withdraw*()` |

### 6.6 Model Governance (FR-MODEL)

| ID | Requirement | Contract | Function |
|----|-------------|----------|----------|
| FR-MODEL-1 | Owner can add trusted models (tier 1) | ModelRegistry | `addTrustedModel()` |
| FR-MODEL-2 | Anyone can propose models with 100 FAB fee | ModelRegistry | `proposeModel()` |
| FR-MODEL-3 | FAB holders can vote on proposals | ModelRegistry | `voteOnProposal()` |
| FR-MODEL-4 | Proposals execute after 3-day voting period | ModelRegistry | `executeProposal()` |
| FR-MODEL-5 | 100k FAB threshold required for approval | ModelRegistry | `executeProposal()` |
| FR-MODEL-6 | Voters can withdraw locked tokens after vote | ModelRegistry | `withdrawVotes()` |
| FR-MODEL-7 | Owner can set per-model rate limits (tokens/sec) | ModelRegistry | `setModelRateLimit()` |
| FR-MODEL-8 | Owner can batch-add trusted models | ModelRegistry | `batchAddTrustedModels()` |
| FR-MODEL-9 | Owner can withdraw accumulated rejected proposal fees | ModelRegistry | `withdrawRejectedFees()` |
| FR-MODEL-10 | Re-proposal cooldown (30 days) prevents spam | ModelRegistry | `_checkReproposalCooldown()` |

---

## 7. Non-Functional Requirements

### 7.1 Gas Efficiency

| Requirement | Target | Implementation |
|-------------|--------|----------------|
| Session creation | < 250k gas | Optimized struct packing |
| Proof submission | < 100k gas | Minimal state updates |
| Session completion | < 200k gas | Batch operations |
| Array removal | O(1) | Swap-and-pop pattern |

### 7.2 Upgradeability

| Requirement | Implementation |
|-------------|----------------|
| Contracts must be upgradeable | UUPS proxy pattern |
| State must survive upgrades | Storage gaps (50 slots) |
| Upgrades require owner authorization | `_authorizeUpgrade()` |

### 7.3 Security

| Requirement | Implementation |
|-------------|----------------|
| Reentrancy protection | `ReentrancyGuardTransient` (EIP-1153 transient storage) |
| Safe token transfers | OpenZeppelin SafeERC20 |
| Safe ETH transfers | `Address.sendValue()` |
| Access control | `onlyOwner`, admin checks, delegate configs |
| Emergency stop | `pause()`/`unpause()` |
| Delegate spending limits | `DelegateConfig` with per-session cap, total cap, expiry |

---

## 8. Cross-Reference: Code to Requirements

| Contract | Key Functions | Requirements |
|----------|---------------|--------------|
| JobMarketplace | `createSessionJobForModel()` | FR-SESSION-1, FR-SESSION-3, FR-SESSION-4 |
| JobMarketplace | `createSessionJobForModelWithToken()` | FR-SESSION-2, FR-SESSION-3, FR-SESSION-4 |
| JobMarketplace | `submitProofOfWork()` | FR-SESSION-5, FR-SESSION-6 |
| JobMarketplace | `completeSessionJob()` | FR-SESSION-7, FR-SESSION-8, FR-PAYMENT-1-3 |
| JobMarketplace | `depositNative()` / `depositToken()` | FR-DEPOSIT-1, FR-DEPOSIT-2 |
| JobMarketplace | `createSessionFromDepositForModel()` | FR-DEPOSIT-3 |
| JobMarketplace | `authorizeDelegate()` / `configureDelegate()` | FR-DELEGATE-1, FR-DELEGATE-2, FR-DELEGATE-3 |
| JobMarketplace | `createSessionForModelAsDelegate()` | FR-DELEGATE-4, FR-DELEGATE-5, FR-DELEGATE-6 |
| NodeRegistry | `registerNode()` | FR-HOST-1-3 |
| NodeRegistry | `setModelTokenPricing()` | FR-HOST-4, FR-HOST-5 |
| NodeRegistry | `slashStake()` | FR-HOST-8 |
| ModelRegistry | `proposeModel()` | FR-MODEL-2 |
| ModelRegistry | `executeProposal()` | FR-MODEL-4-5 |
| ModelRegistry | `setModelRateLimit()` | FR-MODEL-7 |
| HostEarnings | `withdraw()` / `withdrawAll()` | FR-PAYMENT-5 |
| ProofSystem | `markProofUsed()` | Proof replay protection |
