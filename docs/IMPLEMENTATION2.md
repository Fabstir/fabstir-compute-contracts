## IMPLEMENTATION2.md - Session-Based Jobs for fabstir-compute-contracts

### Overview
Extend JobMarketplaceFABWithS5.sol to support session-based jobs with upfront deposits. Users make all blockchain transactions while hosts operate read-only.

### Repository
fabstir-compute-contracts

### Goals
- Add session job type with escrow deposits
- Enable conversational AI without per-prompt gas
- Hosts require no wallet or gas fees
- Usage-based settlement at session end
- Leverage existing contract infrastructure

---

## Phase 1: Core Session Functionality

### Sub-phase 1.1: Extend Job Structure
Add session support to existing JobMarketplaceFAB contract.

**Updates to `contracts/JobMarketplaceFABWithS5.sol`**:
- Add `JobType` enum (SinglePrompt, Session)
- Add `SessionDetails` struct
- Extend existing `Job` struct
- Add session tracking mappings

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_job_types.t.sol`
- `test/JobMarketplace/SessionJobs/test_session_struct.t.sol`
- `test/JobMarketplace/SessionJobs/test_storage_layout.t.sol`

### Sub-phase 1.2: Session Creation
Implement session job creation with deposit locking.

**New Functions**:
- `createSessionJob()` - Create with host assignment
- `_lockSessionDeposit()` - Internal deposit handler
- `getSessionRequirements()` - Validation helper

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_create_session.t.sol`
- `test/JobMarketplace/SessionJobs/test_deposit_lock.t.sol`
- `test/JobMarketplace/SessionJobs/test_host_assignment.t.sol`
- `test/JobMarketplace/SessionJobs/test_validation.t.sol`

### Sub-phase 1.3: Session Completion
Implement user-controlled completion and payment.

**New Functions**:
- `completeSession()` - User completes with usage
- `_calculateSessionPayment()` - Token-based pricing
- `_processSessionRefund()` - Return unused deposit

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_completion.t.sol`
- `test/JobMarketplace/SessionJobs/test_payment_calc.t.sol`
- `test/JobMarketplace/SessionJobs/test_refunds.t.sol`
- `test/JobMarketplace/SessionJobs/test_user_only.t.sol`

### Sub-phase 1.4: Timeout Mechanism
Protect both parties with automatic timeout.

**New Functions**:
- `triggerSessionTimeout()` - Public timeout function
- `_isSessionExpired()` - Check expiry
- `_releaseTimeoutPayment()` - Pay host on timeout

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_timeout.t.sol`
- `test/JobMarketplace/SessionJobs/test_timeout_payment.t.sol`
- `test/JobMarketplace/SessionJobs/test_timeout_edge_cases.t.sol`

---

## Phase 2: Host Read Interface

### Sub-phase 2.1: View Functions
Create read-only interface for hosts.

**New View Functions**:
- `getActiveSessionsForHost()` - List host's sessions
- `getSessionDetails()` - Full session info
- `canHostProcessSession()` - Eligibility check
- `getSessionMetrics()` - Usage statistics

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_host_views.t.sol`
- `test/JobMarketplace/SessionJobs/test_session_queries.t.sol`
- `test/JobMarketplace/SessionJobs/test_metrics.t.sol`

### Sub-phase 2.2: Event System
Add comprehensive events for monitoring.

**New Events**:
- `SessionJobCreated`
- `SessionJobCompleted` 
- `SessionJobTimedOut`
- `SessionJobCancelled`

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_events.t.sol`
- `test/JobMarketplace/SessionJobs/test_event_data.t.sol`

---

## Phase 3: Payment Integration

### Sub-phase 3.1: USDC Support
Integrate with existing PaymentEscrow for USDC.

**Integration Points**:
- Use PaymentEscrow for deposit holding
- Support USDC as payment token
- Calculate USD-based pricing

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_usdc_payment.t.sol`
- `test/JobMarketplace/SessionJobs/test_escrow_integration.t.sol`
- `test/JobMarketplace/SessionJobs/test_pricing.t.sol`

### Sub-phase 3.2: Fee Handling
Integrate with existing fee distribution.

**Updates**:
- Apply platform fee to sessions
- Distribute to treasury/stakers
- Track session volume metrics

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_platform_fee.t.sol`
- `test/JobMarketplace/SessionJobs/test_fee_distribution.t.sol`

---

## Phase 4: Advanced Features

### Sub-phase 4.1: Session Extensions
Allow deposit top-ups for longer sessions.

**New Functions**:
- `extendSession()` - Add more deposit
- `_updateSessionLimits()` - Adjust parameters

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_extension.t.sol`
- `test/JobMarketplace/SessionJobs/test_topup.t.sol`

### Sub-phase 4.2: Early Termination
Support user-initiated cancellation.

**New Functions**:
- `cancelSession()` - Early termination
- `_calculateEarlyTerminationFee()` - Penalty calculation

**Test Files**:
- `test/JobMarketplace/SessionJobs/test_cancellation.t.sol`
- `test/JobMarketplace/SessionJobs/test_penalties.t.sol`

---

## Phase 5: Security & Optimization

### Sub-phase 5.1: Security Measures
Harden session job security.

**Security Implementations**:
- Reentrancy guards on payment functions
- Strict access control
- Deposit limits and sanity checks
- Rate limiting considerations

**Test Files**:
- `test/Security/SessionJobs/test_reentrancy.t.sol`
- `test/Security/SessionJobs/test_access.t.sol`
- `test/Security/SessionJobs/test_limits.t.sol`
- `test/Security/SessionJobs/test_dos.t.sol`

### Sub-phase 5.2: Gas Optimization
Optimize for efficiency.

**Optimizations**:
- Storage packing in structs
- Efficient array operations
- Minimize external calls
- Batch reading functions

**Test Files**:
- `test/GasOptimization/test_session_gas.t.sol`
- `test/GasOptimization/test_storage_efficiency.t.sol`
- `test/GasOptimization/test_batch_ops.t.sol`

---

## Phase 6: Integration & Testing

### Sub-phase 6.1: Full Flow Testing
Test complete session lifecycles.

**Test Scenarios**:
- Happy path (create → process → complete)
- Timeout path (create → expire → timeout)
- Cancellation path (create → cancel)
- Extension path (create → extend → complete)

**Test Files**:
- `test/Integration/SessionJobs/test_full_flow.t.sol`
- `test/Integration/SessionJobs/test_timeout_flow.t.sol`
- `test/Integration/SessionJobs/test_cancel_flow.t.sol`
- `test/Integration/SessionJobs/test_extend_flow.t.sol`

### Sub-phase 6.2: Load Testing
Verify scalability.

**Test Cases**:
- 100+ concurrent sessions
- Multiple hosts with sessions
- Rapid creation/completion cycles
- Maximum deposit scenarios

**Test Files**:
- `test/LoadTest/test_concurrent_sessions.t.sol`
- `test/LoadTest/test_throughput.t.sol`
- `test/LoadTest/test_limits.t.sol`

---

## Testing Strategy

### TDD Approach
1. Write failing test
2. Implement minimal solution
3. Verify test passes
4. Refactor if needed
5. Run full test suite

### Coverage Targets
- Line coverage: 100%
- Branch coverage: 100%
- Critical paths: Full integration tests
- Edge cases: Documented and tested

---

## Deployment Plan

### Local Testing
```bash
# Run all session tests
forge test --match-path test/JobMarketplace/SessionJobs/*

# Check coverage
forge coverage --match-path contracts/JobMarketplaceFABWithS5.sol
```

### Testnet Deployment
1. Deploy to Base Sepolia
2. Verify all functions
3. Run integration tests
4. Monitor gas usage

### Production Deployment
1. Complete audit
2. Deploy to Base mainnet
3. Monitor initial sessions
4. Gather metrics

---

## Success Criteria

### Functional Requirements
- [ ] Users can create session jobs with deposits
- [ ] Hosts see sessions without any transactions
- [ ] Users complete sessions with usage-based payment
- [ ] Timeouts automatically release funds
- [ ] Platform fees collected correctly

### Performance Requirements
- [ ] Session creation < 150k gas
- [ ] Completion < 100k gas
- [ ] View functions free (no gas)
- [ ] Support 1000+ concurrent sessions

### Security Requirements
- [ ] No reentrancy vulnerabilities
- [ ] Proper access control
- [ ] No integer overflows
- [ ] Resistant to DOS attacks

---

## Documentation Updates

### Contract Documentation
- Update NatSpec comments
- Document session flow
- Add integration examples

### Developer Guide
- Session job tutorial
- Host integration guide
- Testing instructions

### User Documentation
- Session vs single-prompt comparison
- Cost calculator
- Best practices

---

## Risk Analysis

### Technical Risks
**Risk**: Gas costs too high
**Mitigation**: Optimize storage, batch operations

**Risk**: Timeout disputes
**Mitigation**: Clear timeout rules, generous periods

**Risk**: Host adoption
**Mitigation**: No wallet requirement, clear benefits

### Business Risks
**Risk**: User confusion about sessions
**Mitigation**: Clear UI, documentation

**Risk**: Liquidity in escrow
**Mitigation**: Automatic timeouts, quick settlement

---

## Timeline

### Week 1: Core Implementation
- Phase 1: Session functionality
- Phase 2: Host interface

### Week 2: Integration
- Phase 3: Payment integration
- Phase 4: Advanced features

### Week 3: Hardening
- Phase 5: Security & optimization
- Phase 6.1: Integration testing

### Week 4: Production Ready
- Phase 6.2: Load testing
- Documentation
- Deployment preparation

This implementation extends the existing contracts with session support while maintaining simplicity and requiring no migration or backwards compatibility concerns.