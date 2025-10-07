# IMPLEMENTATION-MARKET.md - Host-Controlled Pricing Implementation

## Overview
Transform the LLM marketplace from fixed-price protocol to true marketplace where hosts control their pricing. Add contract-level enforcement of host minimum pricing to prevent clients from creating sessions below host requirements.

## Repository
fabstir-compute-contracts

## Goals
- Enable hosts to set their own minimum pricing
- Enforce pricing validation at contract level
- Maintain backward compatibility where possible
- Support dynamic pricing updates by hosts
- Provide price discovery for clients

## Critical Design Decisions
- **Price Range**: 100-100,000 (0.0001 to 0.1 USDC per token for MVP)
- **Default Price**: No default - hosts must explicitly set pricing
- **Validation**: Client's pricePerToken must be >= host's minPricePerToken
- **No Migration**: Pre-MVP hosts will re-register with new pricing parameter

---

## Phase 1: NodeRegistry Pricing Infrastructure

### Sub-phase 1.1: Add Pricing to Node Struct ⏳
Add minimum price per token field to Node struct.

**Tasks:**
- [ ] Add `minPricePerToken` field to Node struct in NodeRegistryWithModels.sol
- [ ] Verify struct compiles with new field
- [ ] Write test file `test/NodeRegistry/test_pricing_struct.t.sol`
- [ ] Test: Node struct includes minPricePerToken field
- [ ] Test: Default value is accessible via public nodes mapping

**Implementation:**
```solidity
struct Node {
    address operator;
    uint256 stakedAmount;
    bool active;
    string metadata;
    string apiUrl;
    bytes32[] supportedModels;
    uint256 minPricePerToken;  // NEW: Minimum acceptable price per token
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (line ~19)

**Tests:**
```solidity
// test/NodeRegistry/test_pricing_struct.t.sol
function test_NodeStructHasPricingField() public {
    // Verify struct compilation and field access
}
```

---

### Sub-phase 1.2: Update registerNode() Function ⏳
Add pricing parameter to node registration with validation.

**Tasks:**
- [ ] Add `minPricePerToken` parameter to registerNode() function signature
- [ ] Add validation: `require(minPricePerToken >= 100, "Price too low")`
- [ ] Add validation: `require(minPricePerToken <= 100000, "Price too high")`
- [ ] Set minPricePerToken in Node struct initialization
- [ ] Write test file `test/NodeRegistry/test_pricing_registration.t.sol`
- [ ] Test: Register with valid price (2000) succeeds
- [ ] Test: Register with too low price (50) fails
- [ ] Test: Register with too high price (200000) fails
- [ ] Test: Register with minimum valid price (100) succeeds
- [ ] Test: Register with maximum valid price (100000) succeeds
- [ ] Test: Verify price stored correctly in nodes mapping

**Implementation:**
```solidity
function registerNode(
    string memory metadata,
    string memory apiUrl,
    bytes32[] memory modelIds,
    uint256 minPricePerToken  // NEW PARAMETER
) external nonReentrant {
    require(minPricePerToken >= 100, "Price too low");
    require(minPricePerToken <= 100000, "Price too high");

    // ... existing validation ...

    nodes[msg.sender] = Node({
        operator: msg.sender,
        stakedAmount: MIN_STAKE,
        active: true,
        metadata: metadata,
        apiUrl: apiUrl,
        supportedModels: modelIds,
        minPricePerToken: minPricePerToken  // NEW
    });

    // ... rest of function ...
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (registerNode function, line ~56)

**Tests:**
```solidity
// test/NodeRegistry/test_pricing_registration.t.sol
function test_RegisterWithValidPrice() public { /* ... */ }
function test_RegisterWithTooLowPrice() public { /* ... */ }
function test_RegisterWithTooHighPrice() public { /* ... */ }
function test_RegisterWithMinValidPrice() public { /* ... */ }
function test_RegisterWithMaxValidPrice() public { /* ... */ }
function test_PriceStoredCorrectly() public { /* ... */ }
```

---

### Sub-phase 1.3: Add PricingUpdated Event ⏳
Add event for tracking pricing changes.

**Tasks:**
- [ ] Add `PricingUpdated` event declaration
- [ ] Write test file `test/NodeRegistry/test_pricing_events.t.sol`
- [ ] Test: Event definition compiles
- [ ] Test: Event can be emitted with correct parameters

**Implementation:**
```solidity
event PricingUpdated(address indexed operator, uint256 newMinPrice);
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (events section, line ~35)

**Tests:**
```solidity
// test/NodeRegistry/test_pricing_events.t.sol
function test_PricingUpdatedEventExists() public { /* ... */ }
```

---

### Sub-phase 1.4: Add updatePricing() Function ⏳
Allow hosts to update their minimum pricing dynamically.

**Tasks:**
- [ ] Create updatePricing() function with newMinPrice parameter
- [ ] Add validation: caller must be registered
- [ ] Add validation: caller must be active
- [ ] Add validation: price >= 100
- [ ] Add validation: price <= 100000
- [ ] Update nodes[msg.sender].minPricePerToken
- [ ] Emit PricingUpdated event
- [ ] Write test file `test/NodeRegistry/test_pricing_updates.t.sol`
- [ ] Test: Registered host can update pricing
- [ ] Test: Update with valid price succeeds
- [ ] Test: Update with too low price fails
- [ ] Test: Update with too high price fails
- [ ] Test: Non-registered address cannot update
- [ ] Test: Inactive host cannot update
- [ ] Test: PricingUpdated event emitted correctly
- [ ] Test: Price stored correctly after update

**Implementation:**
```solidity
function updatePricing(uint256 newMinPrice) external {
    require(nodes[msg.sender].operator != address(0), "Not registered");
    require(nodes[msg.sender].active, "Not active");
    require(newMinPrice >= 100, "Price too low");
    require(newMinPrice <= 100000, "Price too high");

    nodes[msg.sender].minPricePerToken = newMinPrice;

    emit PricingUpdated(msg.sender, newMinPrice);
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (new function after registerNode)

**Tests:**
```solidity
// test/NodeRegistry/test_pricing_updates.t.sol
function test_RegisteredHostCanUpdatePricing() public { /* ... */ }
function test_UpdateWithValidPrice() public { /* ... */ }
function test_UpdateWithTooLowPrice() public { /* ... */ }
function test_UpdateWithTooHighPrice() public { /* ... */ }
function test_NonRegisteredCannotUpdate() public { /* ... */ }
function test_InactiveHostCannotUpdate() public { /* ... */ }
function test_PricingUpdatedEventEmitted() public { /* ... */ }
function test_PriceStoredAfterUpdate() public { /* ... */ }
```

---

### Sub-phase 1.5: Add getNodePricing() View Function ⏳
Add convenience function to query host pricing.

**Tasks:**
- [ ] Create getNodePricing() view function
- [ ] Return nodes[operator].minPricePerToken
- [ ] Write test file `test/NodeRegistry/test_pricing_queries.t.sol`
- [ ] Test: Returns correct price for registered host
- [ ] Test: Returns 0 for non-registered address
- [ ] Test: Returns updated price after updatePricing()

**Implementation:**
```solidity
function getNodePricing(address operator) external view returns (uint256) {
    return nodes[operator].minPricePerToken;
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (new function in view functions section)

**Tests:**
```solidity
// test/NodeRegistry/test_pricing_queries.t.sol
function test_GetPricingForRegisteredHost() public { /* ... */ }
function test_GetPricingForNonRegistered() public { /* ... */ }
function test_GetPricingAfterUpdate() public { /* ... */ }
```

---

### Sub-phase 1.6: Update getNodeFullInfo() ⏳
Update existing view function to include pricing information.

**Tasks:**
- [ ] Add `uint256` return type for minPricePerToken
- [ ] Return node.minPricePerToken as last value
- [ ] Write test file `test/NodeRegistry/test_full_info_pricing.t.sol`
- [ ] Test: getNodeFullInfo returns 7 fields (was 6)
- [ ] Test: 7th field is minPricePerToken
- [ ] Test: Returns correct pricing value
- [ ] Test: Works with updated pricing

**Implementation:**
```solidity
function getNodeFullInfo(address operator) external view returns (
    address,
    uint256,
    bool,
    string memory,
    string memory,
    bytes32[] memory,
    uint256  // NEW: minPricePerToken
) {
    Node storage node = nodes[operator];
    return (
        node.operator,
        node.stakedAmount,
        node.active,
        node.metadata,
        node.apiUrl,
        node.supportedModels,
        node.minPricePerToken  // NEW
    );
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (getNodeFullInfo function, line ~236)

**Tests:**
```solidity
// test/NodeRegistry/test_full_info_pricing.t.sol
function test_GetNodeFullInfoReturnsSevenFields() public { /* ... */ }
function test_SeventhFieldIsMinPricePerToken() public { /* ... */ }
function test_ReturnsCorrectPricing() public { /* ... */ }
function test_WorksWithUpdatedPricing() public { /* ... */ }
```

---

## Phase 2: JobMarketplace Price Validation

### Sub-phase 2.1: Add Price Validation to createSessionFromDeposit() ⏳
Validate client's pricePerToken meets host's minimum.

**Tasks:**
- [ ] Add price validation at start of createSessionFromDeposit()
- [ ] Query: `Node memory node = nodeRegistry.nodes(host)`
- [ ] Require: `pricePerToken >= node.minPricePerToken`
- [ ] Error message: "Price below host minimum"
- [ ] Write test file `test/JobMarketplace/test_price_validation_deposit.t.sol`
- [ ] Test: Session with price above minimum succeeds
- [ ] Test: Session with price equal to minimum succeeds
- [ ] Test: Session with price below minimum fails
- [ ] Test: Host with no pricing (0) fails registration (handled in Phase 1)

**Implementation:**
```solidity
function createSessionFromDeposit(
    address host,
    address paymentToken,
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval
) external nonReentrant returns (uint256 sessionId) {
    // NEW: Validate price meets host minimum
    Node memory node = nodeRegistry.nodes(host);
    require(pricePerToken >= node.minPricePerToken, "Price below host minimum");

    // ... rest of existing function unchanged ...
}
```

**Files Modified:**
- `src/JobMarketplaceWithModels.sol` (createSessionFromDeposit, line ~632)

**Tests:**
```solidity
// test/JobMarketplace/test_price_validation_deposit.t.sol
function test_SessionWithPriceAboveMinimum() public { /* ... */ }
function test_SessionWithPriceEqualToMinimum() public { /* ... */ }
function test_SessionWithPriceBelowMinimum() public { /* ... */ }
```

---

### Sub-phase 2.2: Add Price Validation to createSessionJob() ⏳
Validate pricing for native token sessions.

**Tasks:**
- [ ] Add price validation at start of createSessionJob()
- [ ] Query: `Node memory node = nodeRegistry.nodes(host)`
- [ ] Require: `pricePerToken >= node.minPricePerToken`
- [ ] Error message: "Price below host minimum"
- [ ] Write test file `test/JobMarketplace/test_price_validation_native.t.sol`
- [ ] Test: Native session with price above minimum succeeds
- [ ] Test: Native session with price equal to minimum succeeds
- [ ] Test: Native session with price below minimum fails

**Implementation:**
```solidity
function createSessionJob(
    address host,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval
) external payable nonReentrant returns (uint256 jobId) {
    // NEW: Validate price meets host minimum
    Node memory node = nodeRegistry.nodes(host);
    require(pricePerToken >= node.minPricePerToken, "Price below host minimum");

    // ... rest of existing function unchanged ...
}
```

**Files Modified:**
- `src/JobMarketplaceWithModels.sol` (createSessionJob, line ~215)

**Tests:**
```solidity
// test/JobMarketplace/test_price_validation_native.t.sol
function test_NativeSessionWithPriceAboveMinimum() public { /* ... */ }
function test_NativeSessionWithPriceEqualToMinimum() public { /* ... */ }
function test_NativeSessionWithPriceBelowMinimum() public { /* ... */ }
```

---

### Sub-phase 2.3: Add Price Validation to createSessionJobWithToken() ⏳
Validate pricing for ERC20 token sessions.

**Tasks:**
- [ ] Add price validation at start of createSessionJobWithToken()
- [ ] Query: `Node memory node = nodeRegistry.nodes(host)`
- [ ] Require: `pricePerToken >= node.minPricePerToken`
- [ ] Error message: "Price below host minimum"
- [ ] Write test file `test/JobMarketplace/test_price_validation_token.t.sol`
- [ ] Test: Token session with price above minimum succeeds
- [ ] Test: Token session with price equal to minimum succeeds
- [ ] Test: Token session with price below minimum fails

**Implementation:**
```solidity
function createSessionJobWithToken(
    address host,
    address token,
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval
) external returns (uint256 jobId) {
    // NEW: Validate price meets host minimum
    Node memory node = nodeRegistry.nodes(host);
    require(pricePerToken >= node.minPricePerToken, "Price below host minimum");

    // ... rest of existing function unchanged ...
}
```

**Files Modified:**
- `src/JobMarketplaceWithModels.sol` (createSessionJobWithToken, line ~259)

**Tests:**
```solidity
// test/JobMarketplace/test_price_validation_token.t.sol
function test_TokenSessionWithPriceAboveMinimum() public { /* ... */ }
function test_TokenSessionWithPriceEqualToMinimum() public { /* ... */ }
function test_TokenSessionWithPriceBelowMinimum() public { /* ... */ }
```

---

## Phase 3: Integration Testing

### Sub-phase 3.1: End-to-End Pricing Flow ⏳
Test complete flow from registration to session creation.

**Tasks:**
- [ ] Write test file `test/Integration/test_pricing_flow.t.sol`
- [ ] Test: Register host with pricing → create session above minimum → succeeds
- [ ] Test: Register host → update pricing higher → create session with old price → fails
- [ ] Test: Register host → update pricing lower → create session with new price → succeeds
- [ ] Test: Multiple hosts with different pricing → sessions respect individual pricing
- [ ] Test: Query pricing via getNodePricing() → matches registered value
- [ ] Test: Query pricing via getNodeFullInfo() → matches registered value

**Tests:**
```solidity
// test/Integration/test_pricing_flow.t.sol
function test_CompleteFlowRegistrationToSession() public { /* ... */ }
function test_UpdatePricingAffectsSessions() public { /* ... */ }
function test_LowerPricingEnablesMoreSessions() public { /* ... */ }
function test_MultipleHostsDifferentPricing() public { /* ... */ }
function test_GetNodePricingMatchesRegistered() public { /* ... */ }
function test_GetNodeFullInfoMatchesPricing() public { /* ... */ }
```

---

## Phase 4: Deployment

### Sub-phase 4.1: Build and Verify ⏳
Compile contracts and verify all tests pass.

**Tasks:**
- [ ] Run `forge clean`
- [ ] Run `forge build`
- [ ] Verify both contracts compile successfully
- [ ] Run all tests: `forge test`
- [ ] Verify all pricing tests pass
- [ ] Extract ABIs from build artifacts

**Commands:**
```bash
forge clean
forge build
forge test --match-path "test/NodeRegistry/test_pricing*.t.sol"
forge test --match-path "test/JobMarketplace/test_price_validation*.t.sol"
forge test --match-path "test/Integration/test_pricing_flow.t.sol"
forge test  # Run all tests
```

---

### Sub-phase 4.2: Deploy NodeRegistryWithModels ⏳
Deploy updated NodeRegistry to Base Sepolia.

**Tasks:**
- [ ] Deploy NodeRegistryWithModels contract
- [ ] Record deployment address
- [ ] Record deployment block
- [ ] Record deployment transaction hash
- [ ] Verify contract on BaseScan
- [ ] Test registration with pricing on deployed contract

**Commands:**
```bash
source .env
forge create src/NodeRegistryWithModels.sol:NodeRegistryWithModels \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --constructor-args $FAB_TOKEN_ADDRESS $MODEL_REGISTRY_ADDRESS \
  --legacy
```

---

### Sub-phase 4.3: Deploy JobMarketplaceWithModels ⏳
Deploy updated JobMarketplace pointing to new NodeRegistry.

**Tasks:**
- [ ] Deploy JobMarketplaceWithModels contract with new NodeRegistry address
- [ ] Record deployment address
- [ ] Record deployment block
- [ ] Record deployment transaction hash
- [ ] Verify contract on BaseScan
- [ ] Configure ProofSystem: call setProofSystem()
- [ ] Authorize in HostEarnings: call setAuthorizedCaller()
- [ ] Test session creation with price validation

**Commands:**
```bash
source .env
forge create src/JobMarketplaceWithModels.sol:JobMarketplaceWithModels \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --constructor-args $NEW_NODE_REGISTRY_ADDRESS $HOST_EARNINGS_ADDRESS 1000 30 \
  --legacy

# Configure
cast send $NEW_MARKETPLACE_ADDRESS "setProofSystem(address)" $PROOF_SYSTEM_ADDRESS \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" --legacy

cast send $HOST_EARNINGS_ADDRESS "setAuthorizedCaller(address,bool)" $NEW_MARKETPLACE_ADDRESS true \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" --legacy
```

---

### Sub-phase 4.4: Extract ABIs and Documentation ⏳
Generate client ABIs and update documentation.

**Tasks:**
- [ ] Extract NodeRegistryWithModels ABI to client-abis/
- [ ] Extract JobMarketplaceWithModels ABI to client-abis/
- [ ] Update CONTRACT_ADDRESSES.md with new deployments
- [ ] Update DEPLOYMENT_INFO.json with deployment details
- [ ] Update client-abis/README.md with pricing feature documentation
- [ ] Measure gas costs for new functions
- [ ] Create deployment report JSON

**Commands:**
```bash
cat out/NodeRegistryWithModels.sol/NodeRegistryWithModels.json | jq '.abi' > client-abis/NodeRegistryWithModels-CLIENT-ABI.json
cat out/JobMarketplaceWithModels.sol/JobMarketplaceWithModels.json | jq '.abi' > client-abis/JobMarketplaceWithModels-CLIENT-ABI.json
```

**Deployment Report Format:**
```json
{
  "network": "Base Sepolia",
  "chainId": 84532,
  "deploymentDate": "2025-01-XX",
  "contracts": {
    "NodeRegistryWithModels": {
      "address": "0x...",
      "deploymentBlock": 123456,
      "txHash": "0x...",
      "verified": true,
      "verificationUrl": "https://sepolia.basescan.org/address/0x..."
    },
    "JobMarketplaceWithModels": {
      "address": "0x...",
      "deploymentBlock": 123457,
      "txHash": "0x...",
      "verified": true,
      "verificationUrl": "https://sepolia.basescan.org/address/0x..."
    }
  },
  "gasCosts": {
    "registerNode": "~XXX,XXX gas",
    "updatePricing": "~XX,XXX gas",
    "createSessionFromDeposit": "~XXX,XXX gas"
  }
}
```

---

## Completion Criteria

All sub-phases marked with `[x]` and:
- [ ] All tests passing (NodeRegistry + JobMarketplace + Integration)
- [ ] Contracts deployed to Base Sepolia
- [ ] Contracts verified on BaseScan
- [ ] ABIs extracted and documented
- [ ] Gas costs measured and documented
- [ ] Deployment report provided
- [ ] SDK developer can register hosts with pricing
- [ ] SDK developer can create sessions with price validation

---

## Notes

### TDD Approach
Each sub-phase follows strict TDD:
1. Write tests FIRST (show them failing)
2. Implement minimal code to pass tests
3. Verify tests pass
4. Mark sub-phase complete

### Backward Compatibility
- Existing contracts remain functional
- New deployments required due to struct changes
- No migration needed (pre-MVP, hosts will re-register)
- All session creation functions gain price validation

### Security Considerations
- Price validation prevents race conditions (client can't front-run pricing changes)
- Hosts control their own pricing (no admin override)
- Price bounds prevent extreme values (100-100,000 range)
- Public nodes mapping allows on-chain price discovery
