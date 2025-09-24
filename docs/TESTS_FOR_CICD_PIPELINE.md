# Tests for CI/CD Pipeline

## Overview

This document defines the test suite requirements for the GitHub Actions CI/CD pipeline. All tests listed in the "Required for Deployment" section MUST pass before any deployment to testnet or mainnet.

**Last Updated**: January 2025
**Current Test Coverage**: ~40 tests across 8 contracts
**Critical Coverage Gap**: JobMarketplaceWithModels, NodeRegistryWithModels, ModelRegistry, HostEarnings

## Current Test Coverage Status

### Existing Test Contracts

| Contract | Test File | Number of Tests | Status |
|----------|-----------|-----------------|--------|
| ProofSystem | test_basic_verification.t.sol | 6 | ✅ Complete |
| ProofSystem | test_batch_verification.t.sol | 8 | ✅ Complete |
| ProofSystem | test_proof_replay.t.sol | 6 | ✅ Complete |
| ProofSystem | test_batch_events.t.sol | 7 | ✅ Complete |
| ProofSystem | test_circuit_registry.t.sol | 6 | ✅ Complete |
| ProofSystem | test_model_mapping.t.sol | 7 | ✅ Complete |
| Project Setup | test_project_structure.t.sol | 3 | ✅ Complete |
| Deploy | test_minimal_deployment.t.sol | 1 | ⚠️ Placeholder |
| **JobMarketplaceWithModels** | None | 0 | ❌ **MISSING** |
| **NodeRegistryWithModels** | None | 0 | ❌ **MISSING** |
| **ModelRegistry** | None | 0 | ❌ **MISSING** |
| **HostEarnings** | None | 0 | ❌ **MISSING** |

### Coverage Analysis

```bash
# Check current coverage
forge coverage --report=summary

# Current coverage status:
# - ProofSystem: ~85% coverage
# - JobMarketplaceWithModels: 0% (no tests)
# - NodeRegistryWithModels: 0% (no tests)
# - ModelRegistry: 0% (no tests)
# - HostEarnings: 0% (no tests)
```

## CI/CD Test Pipeline Structure

### Priority 1: Build & Compilation ✅ REQUIRED

These must pass or deployment is blocked immediately:

```bash
# Ensure all contracts compile
forge build

# Check for compiler warnings
forge build 2>&1 | grep -i warning && exit 1 || exit 0
```

### Priority 2: Core Contract Tests ❌ REQUIRED (Currently Missing)

These critical tests MUST be created and pass:

```bash
# JobMarketplaceWithModels tests (MUST CREATE)
forge test --match-contract JobMarketplaceTest -vv

# NodeRegistryWithModels tests (MUST CREATE)
forge test --match-contract NodeRegistryTest -vv

# ModelRegistry tests (MUST CREATE)
forge test --match-contract ModelRegistryTest -vv

# HostEarnings tests (MUST CREATE)
forge test --match-contract HostEarningsTest -vv
```

### Priority 3: Existing ProofSystem Tests ✅ AVAILABLE

These tests exist and should pass:

```bash
# Run all ProofSystem tests
forge test --match-path "test/ProofSystem/*.t.sol" -vv

# Individual ProofSystem test files
forge test --match-path test/ProofSystem/test_basic_verification.t.sol -vv
forge test --match-path test/ProofSystem/test_batch_verification.t.sol -vv
forge test --match-path test/ProofSystem/test_proof_replay.t.sol -vv
forge test --match-path test/ProofSystem/test_batch_events.t.sol -vv
forge test --match-path test/ProofSystem/test_circuit_registry.t.sol -vv
forge test --match-path test/ProofSystem/test_model_mapping.t.sol -vv
```

### Priority 4: Integration Tests ⚠️ RECOMMENDED

End-to-end flow tests (should be created):

```bash
# Full session lifecycle test (MUST CREATE)
forge test --match-contract SessionIntegrationTest -vv

# Payment flow test (MUST CREATE)
forge test --match-contract PaymentFlowTest -vv

# Model validation test (MUST CREATE)
forge test --match-contract ModelValidationTest -vv
```

### Priority 5: Gas & Performance ⚠️ OPTIONAL

Performance benchmarks:

```bash
# Gas snapshot comparison
forge snapshot --check

# Generate gas report
forge test --gas-report
```

## GitHub Actions Workflow

Create `.github/workflows/test.yml`:

```yaml
name: Smart Contract Test Suite

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  FOUNDRY_PROFILE: ci

jobs:
  check:
    name: Foundry Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1
        with:
          version: nightly

      - name: Check contract sizes
        run: forge build --sizes

      - name: Run compilation
        run: |
          forge build
          if forge build 2>&1 | grep -i warning; then
            echo "::error::Compilation warnings detected"
            exit 1
          fi

      - name: Run existing tests (ProofSystem)
        run: |
          forge test --match-path "test/ProofSystem/*.t.sol" -vv

      - name: Run project structure tests
        run: |
          forge test --match-path "test/Setup/*.t.sol" -vv

      # TODO: Uncomment when core contract tests are created
      # - name: Run core contract tests
      #   run: |
      #     forge test --match-contract JobMarketplaceTest -vv
      #     forge test --match-contract NodeRegistryTest -vv
      #     forge test --match-contract ModelRegistryTest -vv
      #     forge test --match-contract HostEarningsTest -vv

      - name: Check gas snapshots
        run: forge snapshot --check
        continue-on-error: true  # Don't fail on gas changes initially

      - name: Generate test report
        if: always()
        run: forge test --summary > test-report.txt

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: test-report.txt

      # Coverage check (set threshold once tests are complete)
      # - name: Check coverage
      #   run: |
      #     COVERAGE=$(forge coverage --report=summary | grep "Total" | awk '{print $2}' | sed 's/%//')
      #     echo "Coverage: $COVERAGE%"
      #     if (( $(echo "$COVERAGE < 80" | bc -l) )); then
      #       echo "::error::Coverage $COVERAGE% is below 80% threshold"
      #       exit 1
      #     fi

  deployment-gate:
    name: Deployment Gate Check
    runs-on: ubuntu-latest
    needs: check
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Check test results
        run: |
          echo "✅ All tests passed - deployment gate cleared"
          echo "⚠️ WARNING: Core contract tests are missing!"
          echo "Before production deployment, ensure:"
          echo "- JobMarketplaceWithModels tests exist"
          echo "- NodeRegistryWithModels tests exist"
          echo "- ModelRegistry tests exist"
          echo "- HostEarnings tests exist"
```

## Critical Missing Tests (Must Create Before Production)

### 1. test/JobMarketplace/test_session_creation.t.sol

```solidity
// Critical scenarios to test:
// - Create session with ETH payment
// - Create session with USDC payment
// - Validate model requirements
// - Check treasury fee calculation (10%)
// - Verify deposit minimums
// - Test with unregistered host (should fail)
// - Test with unapproved model (should fail)
```

### 2. test/JobMarketplace/test_proof_submission.t.sol

```solidity
// Critical scenarios to test:
// - Submit valid proof
// - Verify proof validation
// - Check payment calculations
// - Verify host earnings credit
// - Test proof replay prevention
// - Test invalid proof rejection
```

### 3. test/JobMarketplace/test_session_completion.t.sol

```solidity
// Critical scenarios to test:
// - Complete session with proofs
// - Complete session without proofs
// - Verify payment distribution
// - Check treasury fee deduction (10%)
// - Test refund calculations
// - Verify HostEarnings integration
```

### 4. test/NodeRegistry/test_host_registration.t.sol

```solidity
// Critical scenarios to test:
// - Register host with models
// - Validate model assignments
// - Check stake requirements
// - Test duplicate registration
// - Verify model validation
```

### 5. test/ModelRegistry/test_model_management.t.sol

```solidity
// Critical scenarios to test:
// - Add approved model
// - Remove model
// - Check model validation
// - Test governance controls
// - Verify only 2 models allowed
```

### 6. test/HostEarnings/test_earnings_accumulation.t.sol

```solidity
// Critical scenarios to test:
// - Credit host earnings
// - Withdraw accumulated earnings
// - Test multiple tokens
// - Verify access controls
// - Check reentrancy protection
```

### 7. test/Integration/test_full_session_flow.t.sol

```solidity
// End-to-end test:
// 1. Register host with model
// 2. Create session job
// 3. Submit proofs
// 4. Complete session
// 5. Verify payments
// 6. Withdraw earnings
```

## Local Development Testing

### Quick Test Commands

```bash
# Run all tests
forge test

# Run with verbose output (see logs)
forge test -vv

# Run with traces (debugging)
forge test -vvv

# Run specific test file
forge test --match-path test/ProofSystem/test_basic_verification.t.sol

# Run specific test function
forge test --match-test test_VerificationWithValidProof

# Run tests matching pattern
forge test --match-contract ProofSystem

# Gas reporting
forge test --gas-report

# Coverage report
forge coverage --report=lcov
```

### Pre-Deployment Checklist

Before deploying to any network:

```bash
# 1. Ensure compilation succeeds
forge build

# 2. Run all existing tests
forge test

# 3. Check contract sizes (must be under 24KB)
forge build --sizes

# 4. Verify no compiler warnings
forge build 2>&1 | grep -i warning

# 5. Run gas snapshots
forge snapshot

# 6. Check coverage (target: >80%)
forge coverage --report=summary
```

## Deployment Blocking Conditions

The CI/CD pipeline should **BLOCK deployment** if:

1. ❌ Compilation fails
2. ❌ Any existing test fails
3. ❌ Contract size exceeds 24KB
4. ❌ Compiler warnings present
5. ⚠️ Coverage below 80% (warning, not blocking initially)
6. ⚠️ Gas usage increased >10% (warning, not blocking)

## Test Maintenance

### When Adding New Features

1. Write tests FIRST (TDD approach)
2. Ensure tests fail initially
3. Implement feature
4. Verify tests pass
5. Update this document with new test requirements

### Test File Naming Convention

```
test/[ContractName]/test_[functionality].t.sol
```

Examples:
- `test/JobMarketplace/test_session_creation.t.sol`
- `test/NodeRegistry/test_host_registration.t.sol`
- `test/Integration/test_full_flow.t.sol`

## Emergency Deployment Override

In case of critical hotfix requiring deployment without full test suite:

```bash
# Run minimal safety checks only
forge build && \
forge test --match-path "test/ProofSystem/*.t.sol" && \
echo "⚠️ EMERGENCY DEPLOYMENT - Full test suite bypassed"
```

**NOTE**: This should be followed immediately by:
1. Creating missing tests
2. Full regression testing
3. Post-deployment validation

## Recommendations

### Immediate Actions Required

1. **CRITICAL**: Create tests for JobMarketplaceWithModels
2. **CRITICAL**: Create tests for NodeRegistryWithModels
3. **HIGH**: Create tests for ModelRegistry
4. **HIGH**: Create tests for HostEarnings
5. **MEDIUM**: Set up GitHub Actions workflow
6. **LOW**: Add coverage badges to README

### Test Coverage Targets

| Contract | Current | Target | Priority |
|----------|---------|--------|----------|
| JobMarketplaceWithModels | 0% | 90% | CRITICAL |
| NodeRegistryWithModels | 0% | 85% | CRITICAL |
| ProofSystem | 85% | 90% | LOW |
| ModelRegistry | 0% | 80% | HIGH |
| HostEarnings | 0% | 85% | HIGH |

## Conclusion

The current test suite is **insufficient for production deployment**. The ProofSystem has good coverage, but the core business logic contracts (JobMarketplace, NodeRegistry) completely lack tests.

**DO NOT deploy to mainnet** until:
1. All Priority 1 & 2 tests are created and passing
2. Coverage exceeds 80% for core contracts
3. Integration tests validate end-to-end flows
4. Gas optimization tests show acceptable costs

This document should be updated as new tests are created and coverage improves.