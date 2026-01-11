# Security Audit Remediation Report V3 - Voting Improvements

**Report Date:** January 10, 2026
**Branch:** `fix/audit-remediation-v3`
**Network:** Base Sepolia (Chain ID: 84532)
**Contract:** `ModelRegistryUpgradeable.sol`

---

## Executive Summary

This report addresses voting mechanism improvements identified in the January 2026 security audit. Implementation focuses on the highest-value, lowest-complexity changes.

| Finding | Severity | Status |
|---------|----------|--------|
| Unfair Voting Model (whale sniping) | INFO | ✅ Fixed (Phase 14) |
| No Re-proposal After Rejection | INFO | ✅ Fixed (Phase 15) |
| No Community Model Removal | INFO | Acknowledged (Deferred) |

**Phases Overview:**

| Phase | Description | Lines | Status |
|-------|-------------|-------|--------|
| 14 | Vote Extension (Anti-Sniping) | ~25 | ✅ Complete |
| 15 | Re-proposal Cooldown System | ~25 | ✅ Complete |
| 16 | Multi-Type Proposals | ~75 | Deferred |

**Estimated Total:** ~50 lines of new code

---

## Deferred: Phase 16 (Multi-Type Proposals)

**Finding:** Community has no mechanism to remove problematic models.

**Status:** Acknowledged - Deferred to future version

**Rationale:**
- Adds ~75 lines of code (significant complexity increase)
- Owner-controlled deactivation provides adequate safety mechanism
- Community can request deactivation through off-chain governance
- Can be implemented in v2 if community feedback warrants

**Current Behavior (Retained):**
- Owner can deactivate/reactivate models via `deactivateModel()` / `reactivateModel()`
- Ensures rapid response to security issues without voting delay

---

## Phase 14: Vote Extension (Anti-Sniping)

**Severity:** Code Quality / Governance Improvement (INFO)
**Date:** January 10, 2026

### Original Finding

> The system does not prevent last-minute whale attacks. A single whale user might decline certain AI models from being accepted at the last moment, leaving no time for the community to respond.

**Attack Scenario:**
```
Day 1-2: Community votes FOR (90,000 FAB)
Day 3, 23:59: Whale votes AGAINST (150,000 FAB)
Day 3, 24:00: Voting ends — REJECTED
Community had no time to respond.
```

**Solution:** If a large vote arrives near the deadline, extend voting to give the community time to respond.

---

### 14.1 Add Extension Constants and State Variables

**Goal:** Add constants for extension parameters and tracking fields.

**New Constants:**
```solidity
uint256 public constant EXTENSION_THRESHOLD = 10000 * 10**18; // 10k FAB triggers extension
uint256 public constant EXTENSION_WINDOW = 4 hours;           // Last 4 hours is "danger zone"
uint256 public constant EXTENSION_DURATION = 1 days;          // Extend by 1 day
uint256 public constant MAX_EXTENSIONS = 3;                   // Cap at 3 extensions
```

**Updated Struct Fields:**
```solidity
struct ModelProposal {
    // ... existing fields ...
    uint256 endTime;        // Dynamic end time (replaces proposalTime + DURATION)
    uint8 extensionCount;   // Track number of extensions
}
```

**Tasks:**

- [x] Write test: `EXTENSION_THRESHOLD` constant equals `10000 * 10**18`
- [x] Write test: `EXTENSION_WINDOW` constant equals `4 hours`
- [x] Write test: `EXTENSION_DURATION` constant equals `1 days`
- [x] Write test: `MAX_EXTENSIONS` constant equals `3`
- [x] Add `EXTENSION_THRESHOLD` constant
- [x] Add `EXTENSION_WINDOW` constant
- [x] Add `EXTENSION_DURATION` constant
- [x] Add `MAX_EXTENSIONS` constant
- [x] Add `endTime` field to `ModelProposal` struct
- [x] Add `extensionCount` field to `ModelProposal` struct

---

### 14.2 Update Proposal Creation

**Goal:** Initialize `endTime` when creating proposals.

**Current Code:**
```solidity
proposals[modelId] = ModelProposal({
    // ...
    proposalTime: block.timestamp,
    // ...
});
```

**Updated Code:**
```solidity
proposals[modelId] = ModelProposal({
    // ...
    proposalTime: block.timestamp,
    endTime: block.timestamp + PROPOSAL_DURATION,
    extensionCount: 0,
    // ...
});
```

**Tasks:**

- [x] Write test: New proposal has `endTime` = `block.timestamp + PROPOSAL_DURATION`
- [x] Write test: New proposal has `extensionCount` = `0`
- [x] Update `proposeModel()` to set `endTime`
- [x] Update `proposeModel()` to set `extensionCount = 0`

---

### 14.3 Add Cumulative Late Vote Tracking

**Goal:** Track cumulative votes in the extension window to prevent split-vote attacks.

**New State Variable:**
```solidity
mapping(bytes32 => uint256) public lateVotes; // modelId => cumulative late votes
```

**New Event:**
```solidity
event VotingExtended(bytes32 indexed modelId, uint256 newEndTime, uint8 extensionCount);
```

**Tasks:**

- [x] Write test: `lateVotes` mapping is accessible and returns 0 initially
- [x] Write test: `VotingExtended` event is emitted with correct parameters
- [x] Add `lateVotes` mapping
- [x] Add `VotingExtended` event

---

### 14.4 Update Vote Function with Extension Logic

**Goal:** Implement anti-sniping extension in `voteOnProposal()`.

**Extension Logic:**
```solidity
function voteOnProposal(bytes32 modelId, uint256 amount, bool support) external {
    ModelProposal storage proposal = proposals[modelId];
    require(proposal.proposalTime > 0, "Proposal does not exist");
    require(!proposal.executed, "Proposal already executed");
    require(block.timestamp <= proposal.endTime, "Voting period ended");  // Use endTime

    // ... existing vote logic ...

    // Anti-sniping extension logic
    uint256 timeUntilEnd = proposal.endTime - block.timestamp;
    if (timeUntilEnd <= EXTENSION_WINDOW) {
        lateVotes[modelId] += amount;

        if (
            lateVotes[modelId] >= EXTENSION_THRESHOLD &&
            proposal.extensionCount < MAX_EXTENSIONS
        ) {
            proposal.endTime += EXTENSION_DURATION;
            proposal.extensionCount++;
            lateVotes[modelId] = 0;  // Reset for next potential extension
            emit VotingExtended(modelId, proposal.endTime, proposal.extensionCount);
        }
    }

    emit VoteCast(modelId, msg.sender, amount, support);
}
```

**Tasks:**

- [x] Write test: Vote outside extension window does NOT trigger extension
- [x] Write test: Small vote (< threshold) in extension window does NOT trigger extension
- [x] Write test: Large vote (>= threshold) in extension window DOES trigger extension
- [x] Write test: Extension increases `endTime` by `EXTENSION_DURATION`
- [x] Write test: Extension increments `extensionCount`
- [x] Write test: Extension resets `lateVotes[modelId]` to 0
- [x] Write test: Cumulative small votes reaching threshold trigger extension
- [x] Write test: Cannot extend beyond `MAX_EXTENSIONS`
- [x] Write test: Voting after original end time but before extended end time succeeds
- [x] Update `voteOnProposal()` to check `endTime` instead of calculated time
- [x] Add late vote tracking logic
- [x] Add extension trigger logic
- [x] Emit `VotingExtended` event

---

### 14.5 Update Execute Proposal

**Goal:** Use `endTime` for execution timing.

**Current Code:**
```solidity
require(block.timestamp > proposal.proposalTime + PROPOSAL_DURATION, "Voting still active");
```

**Updated Code:**
```solidity
require(block.timestamp > proposal.endTime, "Voting still active");
```

**Tasks:**

- [x] Write test: Cannot execute before `endTime`
- [x] Write test: Can execute after `endTime`
- [x] Write test: Can execute after extended `endTime`
- [x] Update `executeProposal()` to use `endTime`

---

### 14.6 Update Withdraw Votes

**Goal:** Use `endTime` for withdrawal timing.

**Current Code:**
```solidity
require(proposal.executed ||
        block.timestamp > proposal.proposalTime + PROPOSAL_DURATION + 7 days,
        "Cannot withdraw yet");
```

**Updated Code:**
```solidity
require(proposal.executed ||
        block.timestamp > proposal.endTime + 7 days,
        "Cannot withdraw yet");
```

**Tasks:**

- [x] Write test: Cannot withdraw before `endTime + 7 days` if not executed
- [x] Write test: Can withdraw after `endTime + 7 days` even if not executed
- [x] Update `withdrawVotes()` to use `endTime`

---

### Phase 14 Summary

| Sub-phase | Description | Status |
|-----------|-------------|--------|
| 14.1 | Add extension constants and state variables | ✅ Complete |
| 14.2 | Update proposal creation | ✅ Complete |
| 14.3 | Add cumulative late vote tracking | ✅ Complete |
| 14.4 | Update vote function with extension logic | ✅ Complete |
| 14.5 | Update execute proposal | ✅ Complete |
| 14.6 | Update withdraw votes | ✅ Complete |

---

## Phase 15: Re-proposal Cooldown System

**Severity:** Code Quality / Governance Improvement (INFO)

### Original Finding

> The system does not allow the same model to be proposed twice, disabling the ability to change the community decision in future.

**Current Problem:**
```solidity
require(proposals[modelId].proposalTime == 0, "Proposal already exists");
// After rejection, proposalTime is still non-zero
// Model can NEVER be proposed again
```

**Solution:** Allow re-proposal after a cooldown period (30 days).

---

### 15.1 Add Cooldown Constants and State Variables

**Goal:** Add infrastructure for tracking proposal execution times.

**New Constant:**
```solidity
uint256 public constant REPROPOSAL_COOLDOWN = 30 days;
```

**New State Variable:**
```solidity
mapping(bytes32 => uint256) public lastProposalExecutionTime; // modelId => timestamp
```

**Tasks:**

- [x] Write test: `REPROPOSAL_COOLDOWN` constant equals `30 days`
- [x] Write test: `lastProposalExecutionTime` mapping is accessible
- [x] Add `REPROPOSAL_COOLDOWN` constant
- [x] Add `lastProposalExecutionTime` mapping

---

### 15.2 Add Cooldown Helper Functions

**Goal:** Create internal helpers for cooldown checks.

**New Functions:**
```solidity
function _checkReproposalCooldown(bytes32 modelId) internal view {
    uint256 lastExecution = lastProposalExecutionTime[modelId];
    if (lastExecution > 0) {
        require(
            block.timestamp >= lastExecution + REPROPOSAL_COOLDOWN,
            "Must wait cooldown period"
        );
    }
}

function _clearOldProposal(bytes32 modelId) internal {
    if (proposals[modelId].executed) {
        delete proposals[modelId];
    }
    require(proposals[modelId].endTime == 0, "Active proposal exists");
}
```

**Tasks:**

- [x] Write test: `_checkReproposalCooldown` passes when no previous proposal (tested via 15.3)
- [x] Write test: `_checkReproposalCooldown` reverts within cooldown period (tested via 15.3)
- [x] Write test: `_checkReproposalCooldown` passes after cooldown expires (tested via 15.3)
- [x] Write test: `_clearOldProposal` deletes executed proposals (tested via 15.3)
- [x] Write test: `_clearOldProposal` reverts if active proposal exists (tested via 15.3)
- [x] Add `_checkReproposalCooldown()` function
- [x] Add `_clearOldProposal()` function

---

### 15.3 Update Propose Model for Re-proposals

**Goal:** Allow re-proposing rejected models after cooldown.

**Updated Logic:**
```solidity
function proposeModel(...) external {
    bytes32 modelId = getModelId(huggingfaceRepo, fileName);
    require(models[modelId].timestamp == 0, "Model already exists");

    // Check cooldown and clear old proposal
    _checkReproposalCooldown(modelId);
    _clearOldProposal(modelId);

    // ... rest of function
}
```

**Tasks:**

- [x] Write test: Re-proposing immediately after rejection reverts
- [x] Write test: Re-proposing after cooldown succeeds
- [x] Write test: Re-proposing approved model still blocked (model exists)
- [x] Write test: Old proposal data is cleared on re-proposal
- [x] Update `proposeModel()` with cooldown check
- [x] Update `proposeModel()` with old proposal cleanup

---

### 15.4 Update Execute Proposal to Track Time

**Goal:** Record execution time for cooldown tracking.

**Addition to `executeProposal()`:**
```solidity
proposal.executed = true;
lastProposalExecutionTime[modelId] = block.timestamp;  // Track for cooldown
```

**Tasks:**

- [x] Write test: `lastProposalExecutionTime` is set on execution
- [x] Write test: `lastProposalExecutionTime` is set for both approved and rejected
- [x] Update `executeProposal()` to set `lastProposalExecutionTime`

---

### Phase 15 Summary

| Sub-phase | Description | Status |
|-----------|-------------|--------|
| 15.1 | Add cooldown constants and state variables | ✅ Complete |
| 15.2 | Add cooldown helper functions | ✅ Complete |
| 15.3 | Update propose model for re-proposals | ✅ Complete |
| 15.4 | Update execute proposal to track time | ✅ Complete |

---

## Model Lifecycle After Implementation

```
    ┌──────────┐   Add Proposal    ┌──────────┐
    │   None   │ ────────────────► │  Active  │
    │(no model)│   (approved)      │          │
    └──────────┘                   └──────────┘
         ▲                              │
         │                              │ Owner deactivates
         │                              │ (existing function)
         │                              ▼
         │                         ┌──────────┐
         │                         │ Inactive │
         │                         │          │
         │                         └──────────┘
         │                              │
         │                              │ Owner reactivates
         │                              │ (existing function)
         │                              │
    Re-propose after ◄──────────────────┘
    30 day cooldown
    (if Add rejected)
```

**Note:** Community deactivation/reactivation deferred to future version. Owner retains control for security responsiveness.

---

## Breaking Changes

| Change | Old Signature | New Signature |
|--------|---------------|---------------|
| `ModelProposal` struct | 7 fields | 9 fields (+endTime, +extensionCount) |

**Events:** No changes (Phase 16 deferred)

---

## Test Files to Create

| File | Coverage |
|------|----------|
| `test/SecurityFixes/ModelRegistry/test_vote_extension.t.sol` | Phase 14 |
| `test/SecurityFixes/ModelRegistry/test_reproposal_cooldown.t.sol` | Phase 15 |

---

## Verification Commands

```bash
# Run all voting improvement tests
forge test --match-path "test/SecurityFixes/ModelRegistry/*.sol" -vv

# Run specific phase tests
forge test --match-contract VoteExtensionTest -vv
forge test --match-contract ReproposalCooldownTest -vv

# Full test suite
forge test
```

---

## Summary

| Metric | Value |
|--------|-------|
| New lines of code | ~50 |
| New constants | 5 |
| New mappings | 2 |
| New events | 1 |
| Struct field additions | 2 |
| New functions | 2 (internal helpers) |
| Modified functions | 4 |

**Audit Impact:** Minimal - focused changes with clear purpose, no new external attack surface.

---

**Report Generated:** January 10, 2026
