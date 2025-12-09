# IMPLEMENTATION-FLEXIBLE-PRICING.md - Per-Model and Multi-Token Pricing

## Overview

Extend the LLM marketplace to support flexible pricing: per-model pricing (different prices for different AI models) and multi-token pricing (different stablecoins with different minimum prices). All changes are backward compatible - existing SDK and node code continues working with only contract address updates.

## Repository

fabstir-compute-contracts

## Goals

- Enable hosts to set different minimum prices per AI model
- Enable hosts to set different minimum prices per stablecoin token
- Add admin function to accept new stablecoin tokens
- Maintain 100% backward compatibility (existing code works unchanged)
- Support incremental project upgrades (per-model first, multi-token later)

## Design Principles

### Backward Compatibility Guarantee

| Component | Change Required |
|-----------|-----------------|
| Existing SDK code | **None** - same function signatures |
| Existing node code | **None** - same registration flow |
| Contract addresses | **Yes** - new deployment addresses |
| Existing hosts | **None** - default pricing still works |

### Fallback Pricing Logic

When determining host's minimum price:
1. Check model+token specific price → if set, use it
2. Fall back to model-specific price → if set, use it
3. Fall back to token-specific price → if set, use it
4. Fall back to default stable/native price (existing behavior)

This ensures existing code always gets valid pricing via the default fallback.

## Implementation Progress

**Overall Status: IN PROGRESS (22%)**

- [ ] **Phase 1: Per-Model Pricing Infrastructure** (4/5 sub-phases)
  - [x] Sub-phase 1.1: Add Per-Model Pricing Mappings ✅
  - [x] Sub-phase 1.2: Add setModelPricing() Function ✅
  - [x] Sub-phase 1.3: Add getModelPricing() View Function ✅
  - [x] Sub-phase 1.4: Add clearModelPricing() Function ✅
- [ ] **Phase 2: Multi-Token Support** (0/4 sub-phases)
- [ ] **Phase 3: Model-Aware Sessions** (0/3 sub-phases)
- [ ] **Phase 4: Integration Testing** (0/2 sub-phases)
- [ ] **Phase 5: Deployment** (0/4 sub-phases)

**Last Updated:** 2025-12-09

---

## Phase 1: Per-Model Pricing Infrastructure

Add per-model pricing mappings and functions to NodeRegistryWithModels while preserving existing default pricing.

### Sub-phase 1.1: Add Per-Model Pricing Mappings

Add storage mappings for model-specific pricing outside the Node struct (preserves struct compatibility).

**Tasks:**
- [x] Add `mapping(address => mapping(bytes32 => uint256)) public modelPricingNative` after Node struct
- [x] Add `mapping(address => mapping(bytes32 => uint256)) public modelPricingStable` after Node struct
- [x] Verify contract compiles with new mappings
- [x] Write test file `test/NodeRegistry/test_model_pricing_storage.t.sol`
- [x] Test: Mappings are accessible and default to 0
- [x] Test: Mappings can store values without affecting Node struct

**Implementation:**
```solidity
// After Node struct definition (line ~33)
// Per-model pricing overrides (operator => modelId => price)
mapping(address => mapping(bytes32 => uint256)) public modelPricingNative;
mapping(address => mapping(bytes32 => uint256)) public modelPricingStable;
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (add mappings after line 38)

**Completion Notes (2025-12-09):**
- Added mappings at lines 42-43 in NodeRegistryWithModels.sol
- 6 new tests in test_model_pricing_storage.t.sol (all passing)
- 141 existing tests still passing (backward compatible)
- TDD: RED phase confirmed (compilation failed), GREEN phase achieved

**Tests:**
```solidity
// test/NodeRegistry/test_model_pricing_storage.t.sol
function test_ModelPricingMappingsExist() public { /* ... */ }
function test_ModelPricingDefaultsToZero() public { /* ... */ }
function test_ModelPricingDoesNotAffectNodeStruct() public { /* ... */ }
```

---

### Sub-phase 1.2: Add setModelPricing() Function

Allow hosts to set model-specific pricing that overrides default pricing.

**Tasks:**
- [x] Create `setModelPricing(bytes32 modelId, uint256 nativePrice, uint256 stablePrice)` function
- [x] Add validation: caller must be registered
- [x] Add validation: caller must be active
- [x] Add validation: model must be in host's supportedModels
- [x] Add validation: prices within MIN/MAX ranges (0 = use default)
- [x] Store prices in modelPricingNative and modelPricingStable mappings
- [x] Add `ModelPricingUpdated` event
- [x] Write test file `test/NodeRegistry/test_model_pricing_setter.t.sol`
- [x] Test: Registered host can set model pricing
- [x] Test: Setting price to 0 clears override (uses default)
- [x] Test: Non-registered address cannot set model pricing
- [x] Test: Cannot set pricing for unsupported model
- [x] Test: Invalid prices rejected
- [x] Test: ModelPricingUpdated event emitted

**Implementation:**
```solidity
event ModelPricingUpdated(address indexed operator, bytes32 indexed modelId, uint256 nativePrice, uint256 stablePrice);

function setModelPricing(bytes32 modelId, uint256 nativePrice, uint256 stablePrice) external {
    require(nodes[msg.sender].operator != address(0), "Not registered");
    require(nodes[msg.sender].active, "Node not active");
    require(_nodeSupportsModel(msg.sender, modelId), "Model not supported");

    // Validate prices (0 means use default, otherwise must be in range)
    if (nativePrice > 0) {
        require(nativePrice >= MIN_PRICE_PER_TOKEN_NATIVE, "Native price below minimum");
        require(nativePrice <= MAX_PRICE_PER_TOKEN_NATIVE, "Native price above maximum");
    }
    if (stablePrice > 0) {
        require(stablePrice >= MIN_PRICE_PER_TOKEN_STABLE, "Stable price below minimum");
        require(stablePrice <= MAX_PRICE_PER_TOKEN_STABLE, "Stable price above maximum");
    }

    modelPricingNative[msg.sender][modelId] = nativePrice;
    modelPricingStable[msg.sender][modelId] = stablePrice;

    emit ModelPricingUpdated(msg.sender, modelId, nativePrice, stablePrice);
}

function _nodeSupportsModel(address operator, bytes32 modelId) internal view returns (bool) {
    bytes32[] memory models = nodes[operator].supportedModels;
    for (uint i = 0; i < models.length; i++) {
        if (models[i] == modelId) return true;
    }
    return false;
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (add event + function)

**Tests:**
```solidity
// test/NodeRegistry/test_model_pricing_setter.t.sol
function test_RegisteredHostCanSetModelPricing() public { /* ... */ }
function test_SettingPriceToZeroClearsOverride() public { /* ... */ }
function test_NonRegisteredCannotSetModelPricing() public { /* ... */ }
function test_CannotSetPricingForUnsupportedModel() public { /* ... */ }
function test_InvalidPricesRejected() public { /* ... */ }
function test_ModelPricingUpdatedEventEmitted() public { /* ... */ }
```

**Completion Notes (2025-12-09):**
- Added ModelPricingUpdated event at line 55
- Added setModelPricing function at lines 235-254
- Added _nodeSupportsModel helper at lines 259-265
- 16 new tests in test_model_pricing_setter.t.sol (all passing)
- 157 total tests passing (backward compatible)
- TDD: RED phase confirmed, GREEN phase achieved

---

### Sub-phase 1.3: Add getModelPricing() View Function

Query model-specific pricing with fallback to default.

**Tasks:**
- [x] Create `getModelPricing(address operator, bytes32 modelId, address token)` view function
- [x] Implement fallback logic: model-specific → default
- [x] Return 0 if operator not registered
- [x] Write test file `test/NodeRegistry/test_model_pricing_queries.t.sol`
- [x] Test: Returns model-specific price when set
- [x] Test: Falls back to default when model price is 0
- [x] Test: Returns correct price for native vs stable token
- [x] Test: Returns 0 for non-registered operator

**Implementation:**
```solidity
function getModelPricing(address operator, bytes32 modelId, address token) external view returns (uint256) {
    if (nodes[operator].operator == address(0)) return 0;

    if (token == address(0)) {
        // Native token - check model-specific, fall back to default
        uint256 modelPrice = modelPricingNative[operator][modelId];
        return modelPrice > 0 ? modelPrice : nodes[operator].minPricePerTokenNative;
    } else {
        // Stablecoin - check model-specific, fall back to default
        uint256 modelPrice = modelPricingStable[operator][modelId];
        return modelPrice > 0 ? modelPrice : nodes[operator].minPricePerTokenStable;
    }
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (add view function)

**Tests:**
```solidity
// test/NodeRegistry/test_model_pricing_queries.t.sol
function test_ReturnsModelSpecificPriceWhenSet() public { /* ... */ }
function test_FallsBackToDefaultWhenModelPriceZero() public { /* ... */ }
function test_ReturnsCorrectPriceForNativeVsStable() public { /* ... */ }
function test_ReturnsZeroForNonRegisteredOperator() public { /* ... */ }
```

**Completion Notes (2025-12-09):**
- Added getModelPricing function at lines 376-388
- Implements fallback: model-specific → default pricing
- 13 new tests in test_model_pricing_queries.t.sol (all passing)
- 170 total tests passing (backward compatible)
- TDD: RED phase confirmed, GREEN phase achieved

---

### Sub-phase 1.4: Add clearModelPricing() Function

Allow hosts to clear all model-specific pricing at once.

**Tasks:**
- [x] Create `clearModelPricing(bytes32 modelId)` function
- [x] Clear both native and stable model pricing
- [x] Add validation: caller must be registered
- [x] Emit ModelPricingUpdated event with zero prices
- [x] Write test file `test/NodeRegistry/test_model_pricing_clear.t.sol`
- [x] Test: Clears model pricing successfully
- [x] Test: After clearing, getModelPricing returns default
- [x] Test: Non-registered cannot clear

**Implementation:**
```solidity
function clearModelPricing(bytes32 modelId) external {
    require(nodes[msg.sender].operator != address(0), "Not registered");

    modelPricingNative[msg.sender][modelId] = 0;
    modelPricingStable[msg.sender][modelId] = 0;

    emit ModelPricingUpdated(msg.sender, modelId, 0, 0);
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (add function)

**Tests:**
```solidity
// test/NodeRegistry/test_model_pricing_clear.t.sol
function test_ClearsModelPricingSuccessfully() public { /* ... */ }
function test_AfterClearingReturnsDefault() public { /* ... */ }
function test_NonRegisteredCannotClear() public { /* ... */ }
```

**Completion Notes (2025-12-09):**
- Added clearModelPricing function at lines 261-268
- 8 new tests in test_model_pricing_clear.t.sol (all passing)
- 178 total tests passing (backward compatible)
- TDD: RED phase confirmed, GREEN phase achieved

---

### Sub-phase 1.5: Add getHostModelPrices() Batch Query

Efficient batch query for all model prices for a host.

**Tasks:**
- [ ] Create `getHostModelPrices(address operator)` view function
- [ ] Return arrays: modelIds[], nativePrices[], stablePrices[]
- [ ] Include both model-specific overrides and effective prices
- [ ] Write test file `test/NodeRegistry/test_model_pricing_batch.t.sol`
- [ ] Test: Returns all supported models with prices
- [ ] Test: Returns effective price (override or default)
- [ ] Test: Empty arrays for non-registered operator

**Implementation:**
```solidity
function getHostModelPrices(address operator) external view returns (
    bytes32[] memory modelIds,
    uint256[] memory nativePrices,
    uint256[] memory stablePrices
) {
    bytes32[] memory models = nodes[operator].supportedModels;
    uint256 len = models.length;

    modelIds = models;
    nativePrices = new uint256[](len);
    stablePrices = new uint256[](len);

    uint256 defaultNative = nodes[operator].minPricePerTokenNative;
    uint256 defaultStable = nodes[operator].minPricePerTokenStable;

    for (uint i = 0; i < len; i++) {
        uint256 modelNative = modelPricingNative[operator][models[i]];
        uint256 modelStable = modelPricingStable[operator][models[i]];

        nativePrices[i] = modelNative > 0 ? modelNative : defaultNative;
        stablePrices[i] = modelStable > 0 ? modelStable : defaultStable;
    }

    return (modelIds, nativePrices, stablePrices);
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (add view function)

**Tests:**
```solidity
// test/NodeRegistry/test_model_pricing_batch.t.sol
function test_ReturnsAllSupportedModelsWithPrices() public { /* ... */ }
function test_ReturnsEffectivePriceOverrideOrDefault() public { /* ... */ }
function test_EmptyArraysForNonRegisteredOperator() public { /* ... */ }
```

---

## Phase 2: Multi-Token Support

Add per-token pricing and admin token management.

### Sub-phase 2.1: Add Per-Token Pricing Mapping

Add storage for token-specific pricing overrides.

**Tasks:**
- [ ] Add `mapping(address => mapping(address => uint256)) public customTokenPricing`
- [ ] Mapping is: operator => token address => minimum price
- [ ] Verify contract compiles
- [ ] Write test file `test/NodeRegistry/test_token_pricing_storage.t.sol`
- [ ] Test: Mapping is accessible and defaults to 0
- [ ] Test: Mapping does not affect existing pricing

**Implementation:**
```solidity
// Per-token pricing overrides (operator => tokenAddress => price)
mapping(address => mapping(address => uint256)) public customTokenPricing;
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (add mapping after model pricing mappings)

**Tests:**
```solidity
// test/NodeRegistry/test_token_pricing_storage.t.sol
function test_TokenPricingMappingExists() public { /* ... */ }
function test_TokenPricingDefaultsToZero() public { /* ... */ }
function test_TokenPricingDoesNotAffectExisting() public { /* ... */ }
```

---

### Sub-phase 2.2: Add setTokenPricing() Function

Allow hosts to set token-specific pricing.

**Tasks:**
- [ ] Create `setTokenPricing(address token, uint256 price)` function
- [ ] Add validation: caller must be registered and active
- [ ] Add validation: token cannot be address(0) (use updatePricingNative for native)
- [ ] Add validation: price in valid range (0 = use default)
- [ ] Add `TokenPricingUpdated` event
- [ ] Write test file `test/NodeRegistry/test_token_pricing_setter.t.sol`
- [ ] Test: Registered host can set token pricing
- [ ] Test: Setting price to 0 clears override
- [ ] Test: Cannot set pricing for native token address(0)
- [ ] Test: Invalid prices rejected
- [ ] Test: TokenPricingUpdated event emitted

**Implementation:**
```solidity
event TokenPricingUpdated(address indexed operator, address indexed token, uint256 price);

function setTokenPricing(address token, uint256 price) external {
    require(nodes[msg.sender].operator != address(0), "Not registered");
    require(nodes[msg.sender].active, "Node not active");
    require(token != address(0), "Use updatePricingNative for native token");

    if (price > 0) {
        require(price >= MIN_PRICE_PER_TOKEN_STABLE, "Price below minimum");
        require(price <= MAX_PRICE_PER_TOKEN_STABLE, "Price above maximum");
    }

    customTokenPricing[msg.sender][token] = price;

    emit TokenPricingUpdated(msg.sender, token, price);
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (add event + function)

**Tests:**
```solidity
// test/NodeRegistry/test_token_pricing_setter.t.sol
function test_RegisteredHostCanSetTokenPricing() public { /* ... */ }
function test_SettingPriceToZeroClearsOverride() public { /* ... */ }
function test_CannotSetPricingForNativeToken() public { /* ... */ }
function test_InvalidPricesRejected() public { /* ... */ }
function test_TokenPricingUpdatedEventEmitted() public { /* ... */ }
```

---

### Sub-phase 2.3: Update getNodePricing() with Token Fallback

Modify existing function to check token-specific pricing first.

**Tasks:**
- [ ] Modify `getNodePricing(address operator, address token)` function
- [ ] For non-native tokens: check customTokenPricing first, fall back to default stable
- [ ] Native token behavior unchanged
- [ ] Write test file `test/NodeRegistry/test_token_pricing_queries.t.sol`
- [ ] Test: Returns token-specific price when set
- [ ] Test: Falls back to default stable when token price is 0
- [ ] Test: Native token returns minPricePerTokenNative (unchanged)
- [ ] Test: Existing tests still pass (backward compatibility)

**Implementation:**
```solidity
function getNodePricing(address operator, address token) external view returns (uint256) {
    if (token == address(0)) {
        // Native token - unchanged behavior
        return nodes[operator].minPricePerTokenNative;
    } else {
        // Stablecoin - check custom pricing first, fall back to default
        uint256 customPrice = customTokenPricing[operator][token];
        if (customPrice > 0) {
            return customPrice;
        }
        return nodes[operator].minPricePerTokenStable;
    }
}
```

**Files Modified:**
- `src/NodeRegistryWithModels.sol` (modify getNodePricing function)

**Tests:**
```solidity
// test/NodeRegistry/test_token_pricing_queries.t.sol
function test_ReturnsTokenSpecificPriceWhenSet() public { /* ... */ }
function test_FallsBackToDefaultStableWhenTokenPriceZero() public { /* ... */ }
function test_NativeTokenReturnsNativePrice() public { /* ... */ }
function test_ExistingBehaviorUnchanged() public { /* ... */ }
```

---

### Sub-phase 2.4: Add Admin Token Acceptance Function

Add function to JobMarketplace for accepting new stablecoin tokens.

**Tasks:**
- [ ] Create `addAcceptedToken(address token, uint256 minDeposit)` function in JobMarketplaceWithModels
- [ ] Add validation: only treasury can call
- [ ] Add validation: token not already accepted
- [ ] Add validation: minDeposit > 0
- [ ] Set acceptedTokens[token] = true and tokenMinDeposits[token] = minDeposit
- [ ] Add `TokenAccepted` event
- [ ] Write test file `test/JobMarketplace/test_token_acceptance.t.sol`
- [ ] Test: Treasury can add accepted token
- [ ] Test: Non-treasury cannot add token
- [ ] Test: Cannot add already accepted token
- [ ] Test: Cannot add with zero minDeposit
- [ ] Test: TokenAccepted event emitted
- [ ] Test: Sessions can be created with newly accepted token

**Implementation:**
```solidity
event TokenAccepted(address indexed token, uint256 minDeposit);

function addAcceptedToken(address token, uint256 minDeposit) external {
    require(msg.sender == treasuryAddress, "Only treasury");
    require(!acceptedTokens[token], "Token already accepted");
    require(minDeposit > 0, "Invalid minimum deposit");
    require(token != address(0), "Invalid token address");

    acceptedTokens[token] = true;
    tokenMinDeposits[token] = minDeposit;

    emit TokenAccepted(token, minDeposit);
}
```

**Files Modified:**
- `src/JobMarketplaceWithModels.sol` (add event + function)

**Tests:**
```solidity
// test/JobMarketplace/test_token_acceptance.t.sol
function test_TreasuryCanAddAcceptedToken() public { /* ... */ }
function test_NonTreasuryCannotAddToken() public { /* ... */ }
function test_CannotAddAlreadyAcceptedToken() public { /* ... */ }
function test_CannotAddWithZeroMinDeposit() public { /* ... */ }
function test_TokenAcceptedEventEmitted() public { /* ... */ }
function test_SessionsCanBeCreatedWithNewToken() public { /* ... */ }
```

---

## Phase 3: Model-Aware Sessions

Add optional model parameter to session creation for per-model pricing validation.

### Sub-phase 3.1: Add Session Model Tracking

Add mapping to track which model is used in each session.

**Tasks:**
- [ ] Add `mapping(uint256 => bytes32) public sessionModel` to JobMarketplaceWithModels
- [ ] Verify contract compiles
- [ ] Write test file `test/JobMarketplace/test_session_model_storage.t.sol`
- [ ] Test: Mapping is accessible and defaults to bytes32(0)
- [ ] Test: Existing session creation still works (model = bytes32(0))

**Implementation:**
```solidity
// Session model tracking (sessionId => modelId)
mapping(uint256 => bytes32) public sessionModel;
```

**Files Modified:**
- `src/JobMarketplaceWithModels.sol` (add mapping after existing session mappings)

**Tests:**
```solidity
// test/JobMarketplace/test_session_model_storage.t.sol
function test_SessionModelMappingExists() public { /* ... */ }
function test_SessionModelDefaultsToZero() public { /* ... */ }
function test_ExistingSessionCreationStillWorks() public { /* ... */ }
```

---

### Sub-phase 3.2: Add createSessionJobForModel() Function

New function for model-aware session creation with per-model pricing.

**Tasks:**
- [ ] Create `createSessionJobForModel(address host, bytes32 modelId, uint256 pricePerToken, ...)` function
- [ ] Validate host supports the specified model
- [ ] Query model-specific pricing from NodeRegistry
- [ ] Validate pricePerToken >= model-specific minimum
- [ ] Store modelId in sessionModel mapping
- [ ] Emit enhanced event with modelId
- [ ] Write test file `test/JobMarketplace/test_session_model_creation.t.sol`
- [ ] Test: Session created with correct model pricing validation
- [ ] Test: Fails if host doesn't support model
- [ ] Test: Fails if price below model-specific minimum
- [ ] Test: Model stored in sessionModel mapping
- [ ] Test: Works with model override pricing
- [ ] Test: Falls back to default pricing when no model override

**Implementation:**
```solidity
event SessionJobCreatedForModel(
    uint256 indexed jobId,
    address indexed requester,
    address indexed host,
    bytes32 modelId,
    uint256 deposit
);

function createSessionJobForModel(
    address host,
    bytes32 modelId,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval
) external payable nonReentrant returns (uint256 jobId) {
    require(msg.value >= MIN_DEPOSIT, "Insufficient deposit");
    require(msg.value <= 1000 ether, "Deposit too large");
    require(pricePerToken > 0, "Invalid price");
    require(maxDuration > 0 && maxDuration <= 365 days, "Invalid duration");
    require(proofInterval > 0, "Invalid proof interval");
    require(host != address(0), "Invalid host");

    // Validate host supports this model
    require(nodeRegistry.nodeSupportsModel(host, modelId), "Host does not support model");

    _validateProofRequirements(proofInterval, msg.value, pricePerToken);
    _validateHostRegistration(host);

    // Get model-specific pricing (falls back to default if not set)
    uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, address(0));
    require(pricePerToken >= hostMinPrice, "Price below host minimum for model");

    jobId = nextJobId++;

    // Store model for this session
    sessionModel[jobId] = modelId;

    SessionJob storage session = sessionJobs[jobId];
    session.id = jobId;
    session.depositor = msg.sender;
    session.requester = msg.sender;
    session.host = host;
    session.paymentToken = address(0);
    session.deposit = msg.value;
    session.pricePerToken = pricePerToken;
    session.maxDuration = maxDuration;
    session.startTime = block.timestamp;
    session.lastProofTime = block.timestamp;
    session.proofInterval = proofInterval;
    session.status = SessionStatus.Active;

    userDepositsNative[msg.sender] += msg.value;
    userSessions[msg.sender].push(jobId);
    hostSessions[host].push(jobId);

    emit SessionJobCreated(jobId, msg.sender, host, msg.value);
    emit SessionJobCreatedForModel(jobId, msg.sender, host, modelId, msg.value);

    return jobId;
}
```

**Files Modified:**
- `src/JobMarketplaceWithModels.sol` (add event + function)

**Tests:**
```solidity
// test/JobMarketplace/test_session_model_creation.t.sol
function test_SessionCreatedWithModelPricingValidation() public { /* ... */ }
function test_FailsIfHostDoesNotSupportModel() public { /* ... */ }
function test_FailsIfPriceBelowModelMinimum() public { /* ... */ }
function test_ModelStoredInSessionModelMapping() public { /* ... */ }
function test_WorksWithModelOverridePricing() public { /* ... */ }
function test_FallsBackToDefaultPricingWhenNoOverride() public { /* ... */ }
```

---

### Sub-phase 3.3: Add createSessionJobForModelWithToken() Function

Token version of model-aware session creation.

**Tasks:**
- [ ] Create `createSessionJobForModelWithToken(address host, bytes32 modelId, address token, ...)` function
- [ ] Validate host supports the specified model
- [ ] Query model-specific pricing for the token
- [ ] Validate pricePerToken >= model-specific minimum for token
- [ ] Store modelId in sessionModel mapping
- [ ] Write test file `test/JobMarketplace/test_session_model_token.t.sol`
- [ ] Test: Session created with USDC and model pricing
- [ ] Test: Fails if price below model-specific stable minimum
- [ ] Test: Works with custom token pricing for model

**Implementation:**
```solidity
function createSessionJobForModelWithToken(
    address host,
    bytes32 modelId,
    address token,
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval
) external returns (uint256 jobId) {
    require(acceptedTokens[token], "Token not accepted");
    uint256 minRequired = tokenMinDeposits[token];
    require(minRequired > 0, "Token not configured");
    require(deposit >= minRequired, "Insufficient deposit");
    require(deposit > 0, "Zero deposit");
    require(deposit <= 1000 ether, "Deposit too large");
    require(pricePerToken > 0, "Invalid price");
    require(maxDuration > 0 && maxDuration <= 365 days, "Invalid duration");
    require(proofInterval > 0, "Invalid proof interval");
    require(host != address(0), "Invalid host");

    // Validate host supports this model
    require(nodeRegistry.nodeSupportsModel(host, modelId), "Host does not support model");

    _validateHostRegistration(host);
    _validateProofRequirements(proofInterval, deposit, pricePerToken);

    // Get model-specific pricing for this token (falls back appropriately)
    uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, token);
    require(pricePerToken >= hostMinPrice, "Price below host minimum for model");

    IERC20(token).transferFrom(msg.sender, address(this), deposit);

    jobId = nextJobId++;

    // Store model for this session
    sessionModel[jobId] = modelId;

    SessionJob storage session = sessionJobs[jobId];
    session.id = jobId;
    session.depositor = msg.sender;
    session.requester = msg.sender;
    session.host = host;
    session.paymentToken = token;
    session.deposit = deposit;
    session.pricePerToken = pricePerToken;
    session.maxDuration = maxDuration;
    session.startTime = block.timestamp;
    session.lastProofTime = block.timestamp;
    session.proofInterval = proofInterval;
    session.status = SessionStatus.Active;

    userDepositsToken[msg.sender][token] += deposit;
    userSessions[msg.sender].push(jobId);
    hostSessions[host].push(jobId);

    emit SessionJobCreated(jobId, msg.sender, host, deposit);
    emit SessionJobCreatedForModel(jobId, msg.sender, host, modelId, deposit);

    return jobId;
}
```

**Files Modified:**
- `src/JobMarketplaceWithModels.sol` (add function)

**Tests:**
```solidity
// test/JobMarketplace/test_session_model_token.t.sol
function test_SessionCreatedWithUSDCAndModelPricing() public { /* ... */ }
function test_FailsIfPriceBelowModelStableMinimum() public { /* ... */ }
function test_WorksWithCustomTokenPricingForModel() public { /* ... */ }
```

---

## Phase 4: Integration Testing

End-to-end tests ensuring backward compatibility and new features work together.

### Sub-phase 4.1: Backward Compatibility Tests

Verify all existing functionality works unchanged.

**Tasks:**
- [ ] Write test file `test/Integration/test_backward_compatibility.t.sol`
- [ ] Test: registerNode() with default pricing still works
- [ ] Test: createSessionJob() without model still works
- [ ] Test: createSessionJobWithToken() without model still works
- [ ] Test: getNodePricing() returns correct default values
- [ ] Test: Existing session flow unchanged
- [ ] Test: All existing tests still pass

**Tests:**
```solidity
// test/Integration/test_backward_compatibility.t.sol
function test_RegisterNodeWithDefaultPricingWorks() public { /* ... */ }
function test_CreateSessionJobWithoutModelWorks() public { /* ... */ }
function test_CreateSessionJobWithTokenWithoutModelWorks() public { /* ... */ }
function test_GetNodePricingReturnsCorrectDefaults() public { /* ... */ }
function test_ExistingSessionFlowUnchanged() public { /* ... */ }
```

---

### Sub-phase 4.2: Full Feature Integration Tests

Test complete flows with new features.

**Tasks:**
- [ ] Write test file `test/Integration/test_flexible_pricing_flow.t.sol`
- [ ] Test: Host registers → sets model pricing → client creates model session
- [ ] Test: Host registers → sets token pricing → client creates session with new token
- [ ] Test: Treasury adds new token → host sets pricing → client uses new token
- [ ] Test: Multiple hosts with different model prices for same model
- [ ] Test: Price fallback chain works correctly
- [ ] Test: Batch query returns correct effective prices

**Tests:**
```solidity
// test/Integration/test_flexible_pricing_flow.t.sol
function test_HostSetsModelPricingClientCreatesSession() public { /* ... */ }
function test_HostSetsTokenPricingClientUsesNewToken() public { /* ... */ }
function test_TreasuryAddsTokenHostSetsPricingClientUses() public { /* ... */ }
function test_MultipleHostsDifferentModelPrices() public { /* ... */ }
function test_PriceFallbackChainWorksCorrectly() public { /* ... */ }
function test_BatchQueryReturnsEffectivePrices() public { /* ... */ }
```

---

## Phase 5: Deployment

### Sub-phase 5.1: Build and Verify

Compile contracts and verify all tests pass.

**Tasks:**
- [ ] Run `forge clean`
- [ ] Run `forge build`
- [ ] Verify both contracts compile successfully
- [ ] Run all tests: `forge test`
- [ ] Verify all tests pass (existing + new)
- [ ] Run gas snapshots for new functions

**Commands:**
```bash
forge clean
forge build
forge test
forge snapshot
```

---

### Sub-phase 5.2: Deploy NodeRegistryWithModels

Deploy updated NodeRegistry to Base Sepolia.

**Tasks:**
- [ ] Deploy NodeRegistryWithModels contract
- [ ] Record deployment address
- [ ] Record deployment transaction hash
- [ ] Verify contract on BaseScan
- [ ] Test model pricing functions on deployed contract

**Commands:**
```bash
forge script script/DeployNodeRegistryWithModels.s.sol:DeployNodeRegistryWithModels \
  --rpc-url https://sepolia.base.org --broadcast --legacy
```

---

### Sub-phase 5.3: Deploy JobMarketplaceWithModels

Deploy updated JobMarketplace pointing to new NodeRegistry.

**Tasks:**
- [ ] Deploy JobMarketplaceWithModels contract with new NodeRegistry address
- [ ] Record deployment address
- [ ] Record deployment transaction hash
- [ ] Verify contract on BaseScan
- [ ] Configure ProofSystem: call setProofSystem()
- [ ] Authorize in HostEarnings: call setAuthorizedCaller()
- [ ] Test token acceptance function
- [ ] Test model-aware session creation

**Commands:**
```bash
forge script script/DeployJobMarketplaceWithModels.s.sol:DeployJobMarketplaceWithModels \
  --rpc-url https://sepolia.base.org --broadcast --legacy
```

---

### Sub-phase 5.4: Documentation and ABIs

Update all documentation and extract ABIs.

**Tasks:**
- [ ] Extract NodeRegistryWithModels ABI to client-abis/
- [ ] Extract JobMarketplaceWithModels ABI to client-abis/
- [ ] Update CONTRACT_ADDRESSES.md with new deployments
- [ ] Update CLAUDE.md with new features
- [ ] Update client-abis/README.md with new function documentation
- [ ] Create migration guide for SDK developers
- [ ] Follow complete checklist in docs/CONTRACT_DEPLOYMENT_CHECKLIST.md

**Commands:**
```bash
cat out/NodeRegistryWithModels.sol/NodeRegistryWithModels.json | jq '.abi' > client-abis/NodeRegistryWithModels-CLIENT-ABI.json
cat out/JobMarketplaceWithModels.sol/JobMarketplaceWithModels.json | jq '.abi' > client-abis/JobMarketplaceWithModels-CLIENT-ABI.json
```

---

## Completion Criteria

All sub-phases marked with `[x]` and:
- [ ] All existing tests still passing
- [ ] All new tests passing
- [ ] Contracts deployed to Base Sepolia
- [ ] Contracts verified on BaseScan
- [ ] ABIs extracted and documented
- [ ] Backward compatibility verified
- [ ] SDK can continue using existing functions
- [ ] SDK can optionally use new model-aware functions
- [ ] New tokens can be added without redeployment

---

## Upgrade Path for SDK/Node Projects

### Phase 1: Immediate (Address Update Only)
1. Update contract addresses in configuration
2. All existing code works unchanged
3. Hosts use default pricing for all models

### Phase 2: Add Per-Model Pricing Support
1. Host registration adds `setModelPricing()` calls
2. Client session creation switches to `createSessionJobForModel()`
3. Price discovery uses `getModelPricing()` or `getHostModelPrices()`

### Phase 3: Add Multi-Token Support
1. Host registration adds `setTokenPricing()` calls
2. Client can use newly accepted stablecoins
3. Treasury adds new tokens as needed

---

## Notes

### TDD Approach
Each sub-phase follows strict TDD:
1. Write tests FIRST (show them failing)
2. Implement minimal code to pass tests
3. Verify tests pass
4. Mark sub-phase complete

### Backward Compatibility
- All existing function signatures unchanged
- New functions added alongside existing ones
- Fallback pricing ensures existing code works
- No migration needed for existing hosts

### Security Considerations
- Price validation prevents underpaying hosts
- Model support validation prevents invalid sessions
- Treasury-only token acceptance prevents spam tokens
- Price bounds prevent extreme values

### Gas Considerations
- Mappings add minimal storage overhead
- Fallback logic adds ~2000 gas per call
- Batch queries reduce RPC calls for clients
