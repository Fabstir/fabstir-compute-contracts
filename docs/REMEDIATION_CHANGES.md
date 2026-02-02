# Remediation Changes

**Audit Firm**: AUDIT
**Testing Period**: January 27 - February 16, 2026
**Remediation Branch**: `fix/remediation-pre-report`
**Base Commit**: `8edc68b` (before remediation began)

## Commit History

| Commit | Finding ID | Slack Ref | Description |
|--------|------------|-----------|-------------|
| `e4f274d` | AUDIT-F1 | `slack-C0A61FZC8SH-p1769545156133729` | Remove dead `onlyRegisteredHost` modifier |
| `43064b2` | AUDIT-F2 | `slack-C0A61FZC8SH-p1769545156133729` | Require ProofSystem configuration for proof submission |
| `a9f8bce` | AUDIT-F2 | `slack-C0A61FZC8SH-p1769545156133729` | Update remediation progress documentation |
| `c91c2cb` | AUDIT-F3 | `slack-C0A61FZC8SH-p1769545156133729` | Separate `proofTimeoutWindow` from `proofInterval` |
| `0bc0194` | AUDIT-F4 | `slack-C0A61FZC8SH-p1769619714508749` | Include `modelId` in signature verification |
| `483682c` | AUDIT-F5 | `slack-C0A61FZC8SH-p1769608000786449` | Add `createSessionFromDepositForModel` function |
| (pending) | V2-DELEG | SDK Request | V2 Direct Payment Delegation for Smart Wallet |

## V2 Direct Payment Delegation (February 2, 2026)

**Branch**: `fix/v2-direct-payment-delegation`
**Purpose**: Enable Coinbase Smart Wallet sub-accounts to create sessions using primary account's USDC

### Deployment

| Component | Address | Transaction |
|-----------|---------|-------------|
| **Implementation** | `0xf5441bda610AbCDe71B96fe6051E738d2702f071` | `0xe6658f9b...` |
| **Proxy (upgraded)** | `0x95132177F964FF053C1E874b53CF74d819618E06` | `0x4b97890a...` |

### Functions Added

```solidity
// Authorization
function authorizeDelegate(address delegate, bool authorized) external;
function isDelegateAuthorized(address payer, address delegate) external view returns (bool);

// V2 Direct Payment (USDC only)
function createSessionForModelAsDelegate(...) external returns (uint256);
function createSessionAsDelegate(...) external returns (uint256);
```

### Custom Errors (Bytecode Optimization)

```solidity
error NotDelegate();
error ERC20Only();
error BadDelegateParams();
```

### Test Coverage

- **41 delegation tests** passing (authorization + security + direct payment)
- **754 total tests** passing

### Security Properties Verified

1. ✅ Unauthorized addresses cannot pull from payer
2. ✅ Revoked delegates fail after revocation
3. ✅ Delegate cannot exceed payer's ERC-20 approval
4. ✅ Session refunds go to payer (not delegate)
5. ✅ Pause mechanism blocks delegated functions
6. ✅ Cross-user authorization isolation

## Finding Summary

| Finding ID | Severity | Description | Status |
|------------|----------|-------------|--------|
| AUDIT-F1 | LOW | Dead code `onlyRegisteredHost` modifier | ✅ FIXED |
| AUDIT-F2 | HIGH | ProofSystem address(0) allows arbitrary proofs | ✅ FIXED |
| AUDIT-F3 | MEDIUM | `proofInterval` dual interpretation bug | ✅ FIXED |
| AUDIT-F4 | MEDIUM | Model validation missing in signature scheme | ✅ FIXED |
| AUDIT-F5 | LOW | Missing `createSessionFromDepositForModel()` | ✅ FIXED |

## Test Coverage

All fixes verified with comprehensive test suite:
- **Total Tests**: 713 passing
- **Test Files Added**:
  - `test/SecurityFixes/Remediation/test_dead_code_removal.t.sol`
  - `test/SecurityFixes/Remediation/test_proofsystem_required.t.sol`
  - `test/SecurityFixes/JobMarketplace/test_proof_timeout_window.t.sol`
  - `test/SecurityFixes/Remediation/test_model_signature.t.sol`
  - `test/SecurityFixes/Remediation/test_create_from_deposit_for_model.t.sol`

## Test Contract Deployments (Base Sepolia)

Deployed for testing WITHOUT upgrading audited proxies:

| Contract | Test Proxy | Test Implementation |
|----------|------------|---------------------|
| ProofSystem | `0xE8DCa89e1588bbbdc4F7D5F78263632B35401B31` | `0x56657bCBAE50AB656A9452f7B52e317650f90267` |
| JobMarketplace | `0x95132177F964FF053C1E874b53CF74d819618E06` | `0x06dB705BcBdda50A1712635fdC64A28d75de5603` |

## Audited Contracts (FROZEN - DO NOT UPGRADE)

| Contract | Audited Proxy | Status |
|----------|--------------|--------|
| JobMarketplace | `0x3CaCbf3f448B420918A93a88706B26Ab27a3523E` | FROZEN |
| ProofSystem | `0x5afB91977e69Cc5003288849059bc62d47E7deeb` | FROZEN |
| NodeRegistry | `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22` | FROZEN |
| ModelRegistry | `0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2` | FROZEN |
| HostEarnings | `0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0` | FROZEN |

## Breaking Changes

| Change | Impact | Migration |
|--------|--------|-----------|
| ProofSystem required | Sessions fail if ProofSystem not configured | Ensure ProofSystem is set before deployment |
| `proofTimeoutWindow` parameter | All session creation calls need new parameter | SDK must pass new parameter (60-3600 seconds) |
| `modelId` in signature | Hosts MUST include modelId in signed message | Host software update required |
| IProofSystem interface | Functions now require modelId parameter | Update all callers to pass modelId |

## Verification Commands

```bash
# Run all tests
forge test

# Run security fix tests only
forge test --match-path "test/SecurityFixes/**"

# Verify specific findings
forge test --match-contract DeadCodeRemovalTest      # F1
forge test --match-contract ProofSystemRequiredTest  # F2
forge test --match-contract ProofTimeoutWindowTest   # F3
forge test --match-contract ModelSignatureTest       # F4
forge test --match-contract CreateFromDepositForModelTest  # F5
```

## Retest Date

**March 10, 2026** - Auditors will retest all fixes
