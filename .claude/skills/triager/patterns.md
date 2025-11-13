# Failure Patterns

This document describes common patterns that help identify whether a failure is an infrastructure flake, test bug, or actual bug in CockroachDB.

## Infrastructure Flake Indicators

### VM Restarts or Reboots
```
# Look for in journalctl:
- "Stopped target" messages
- "Starting" after unexpected shutdown
- Boot sequences
```

**Example evidence:**
- systemd messages about stopping services
- kernel: Power button pressed
- Reboot messages in system logs

**Why it's a flake:** The test didn't cause the VM to restart - the cloud provider or infrastructure did.

### Disk Full
```
# Look for:
- "no space left on device"
- df output showing 100% usage
- Write failures
```

**Example evidence:**
- Failed to write file: no space left on device
- Disk usage at 100% in logs
- Unable to create log files

**Why it's a flake:** Test infrastructure should provision enough disk space. If the disk fills up, it's an infrastructure issue.

### Network Issues
```
# Look for:
- "connection refused"
- "no route to host"
- "i/o timeout"
- During infrastructure setup, not test execution
```

**Example evidence:**
- Failed to connect to node: connection refused
- Network unreachable errors
- DNS resolution failures

**Why it's a flake:** If network issues occur during setup or between infrastructure components, it's not a CockroachDB bug.

### OOM (Out of Memory)
```
# Look for in dmesg:
- "Out of memory"
- "Killed process"
- OOM killer messages
```

**Example evidence:**
- kernel: Out of memory: Killed process
- oom_reaper: reaped process
- Process killed by OOM killer

**Why it's a flake:** If the OOM killer targets test infrastructure (not CockroachDB), or if the VM simply ran out of memory, it's an infrastructure issue.

### TeamCity Agent Issues
```
# Look for:
- Agent disconnected messages
- Build canceled by agent
- Agent heartbeat failures
```

**Example evidence:**
- TeamCity agent lost connection
- Build was canceled
- Agent became unresponsive

**Why it's a flake:** TeamCity infrastructure problems are not test or CockroachDB bugs.

## Test Bug Indicators

### Test Timeout Issues

**🚨 CRITICAL PATTERN: Timeout Misclassified as Goroutine Leak**

This is one of the most common misclassification errors. When a test times out, it gets killed mid-execution, leaving goroutines running. This looks like a goroutine leak but is actually a timeout issue.

**How to distinguish:**

```
TIMEOUT (test killed mid-execution):
- Test duration ≈ timeout limit (within 1 minute)
- Slow operation found (e.g., "import took 8m30s")
- Goroutines in "running" or "active" states (doing work)
- No shutdown attempted (no "leaktest.AfterTest" in stack)
- Stack traces show goroutines doing actual work
- Classification: TEST_BUG (timeout too short) or PERFORMANCE_REGRESSION

GOROUTINE LEAK (shutdown bug):
- Test duration << timeout limit (e.g., 2m vs 15m)
- Shutdown attempted (leaktest.AfterTest called)
- Goroutines in "waiting" states (sync.Cond.Wait, select)
- Long wait times (>1 minute) in idle states
- Stack traces show goroutines waiting/blocked
- Classification: ACTUAL_BUG (shutdown coordination failure)
```

**Real example - Issue #161919:**
```
WRONG analysis (original triage):
- "Goroutines leaked after shutdown"
- "Shutdown coordination failure"
- Classification: ACTUAL_BUG
- Confidence: 0.85

CORRECT analysis:
- Test timeout: 15 minutes
- TPCC import took: 8 minutes 30 seconds
- Other operations: ~6 minutes
- Total duration: ~14m45s → exceeded 15-minute timeout
- Goroutines dumped when test was killed (SIGQUIT)
- Classification: TEST_BUG (timeout configuration)
- Root cause: Test needs longer timeout OR smaller fixture
```

**Evidence to look for:**
```
# Check test duration vs timeout limit
grep -i "test timed out\|timeout exceeded\|panic: test timed out" test.log

# Check for slow operations
grep -i "import.*took\|duration:.*m\|elapsed.*m" test.log

# Calculate: start_time to end_time ≈ timeout_limit?
# If YES → likely timeout
# If NO → likely actual bug

# Check goroutine dump context
# After timeout: goroutines actively working
# After shutdown: goroutines waiting/blocked
```

**Why timeout is a test bug:**
- Test configuration (timeout limit) is incorrect
- OR test is too slow (performance regression)
- NOT a product bug in shutdown coordination
- NOT a goroutine leak

**Standard timeout patterns:**
```
# Look for:
- Test exceeded maximum duration
- Test timeout before actual failure
- Aggressive timeout settings in test code
- Slow workload/import operations near timeout limit
```

**Example evidence:**
- Test timeout after 15m (but TPCC import took 8m30s + other ops)
- Hard-coded timeout too short for workload size
- Test didn't allocate enough time for fixture import
- Workload size increased but timeout didn't

**Why it's a test bug:** The test logic or configuration is incorrect, not CockroachDB.

### Unable to Run Workload
```
# Look for:
- Failed to install third-party tool (sysbench, pgbench, etc.)
- Download failures for test dependencies
- Incompatible tool versions
```

**Example evidence:**
- apt-get failed to install sysbench
- Could not download workload binary
- Version mismatch between tool and test

**Why it's a test bug:** Test infrastructure or test setup is broken.

### Test Logic Errors
```
# Look for:
- Test expects incorrect behavior
- Test assertions don't match reality
- Test cleanup failures
```

**Example evidence:**
- Test expects immediate replication but doesn't wait
- Assertion fails because test doesn't account for timing
- Test tries to clean up resources that don't exist

**Why it's a test bug:** The test code itself has bugs.

## Actual Bug Indicators

### SQL Panics
```
# Stack trace in CRDB code:
- pkg/sql/*
- Assertion failures
- Unexpected nil pointers
```

**Example evidence:**
- panic: runtime error: invalid memory address or nil pointer dereference
- Stack trace shows sql package panic
- Assertion failed in SQL execution

**Why it's a bug:** CockroachDB code panicked during SQL execution - this is a real bug.

### Data Corruption
```
# Look for:
- Checksum mismatches
- Inconsistent replicas
- Unexpected data values
```

**Example evidence:**
- Checksum mismatch detected
- Replica divergence
- Query returns wrong results

**Why it's a bug:** Data integrity is compromised - this is a critical bug.

### Concurrency Issues
```
# Look for:
- Deadlock messages
- "fatal error: concurrent map writes"
- Race detector output
```

**Example evidence:**
- Detected race condition
- Deadlock detected in transaction
- Concurrent map access panic

**Why it's a bug:** Race conditions and deadlocks in CockroachDB code are bugs.

### Memory Leaks in CRDB Process
```
# Look for:
- Continuously growing memory usage
- goroutine leaks
- Heap growth without corresponding workload
```

**Example evidence:**
- Memory usage grows from 1GB to 20GB during test
- Goroutine count increases from 100 to 10,000
- No corresponding increase in workload

**Why it's a bug:** If CockroachDB is leaking memory during normal operation, it's a bug.

### Assertion Failures
```
# Look for:
- Assertion failed messages
- Invariant violations
- Consistency check failures
```

**Example evidence:**
- Assertion failed: expected x but got y
- Invariant violated: range count mismatch
- Consistency checker found error

**Why it's a bug:** Assertions and invariants should never fail - these indicate bugs.

## Gray Areas (Require Careful Analysis)

### Timeouts During Operation
Could be either:
- **Infrastructure flake** if network/VM issues caused the timeout
- **Test bug** if timeout is set too aggressively
- **Actual bug** if CRDB hung or became unresponsive

**How to distinguish:**
- Check system logs for infrastructure issues
- Check test code for timeout values
- Check CRDB logs for hangs or performance issues
- Look at Prometheus metrics for resource usage

### Connection Refused Errors
Could be either:
- **Infrastructure flake** if VM restarted or network failed
- **Actual bug** if CRDB crashed or became unresponsive

**How to distinguish:**
- Check journalctl for VM restart
- Check CRDB logs for crash or panic
- Check timing - did it happen during setup or during test?

### Performance Degradation
Could be either:
- **Infrastructure flake** if VM had resource contention
- **Test bug** if test expectations are unrealistic
- **Actual bug** if CRDB regressed in performance

**How to distinguish:**
- Check Prometheus metrics for resource usage
- Compare with historical test runs
- Check for recent CRDB changes
- Verify test expectations are reasonable

## Decision Framework

Use this framework to classify failures:

1. **Check system logs first** (journalctl, dmesg)
   - VM restart? → INFRASTRUCTURE_FLAKE
   - Disk full? → INFRASTRUCTURE_FLAKE
   - OOM killer? → Check what was killed

2. **Check test.log for failure location**
   - During setup? → Likely INFRASTRUCTURE_FLAKE or TEST_BUG
   - During test execution? → Could be any type

3. **Check CRDB logs for panics/crashes**
   - Panic in CRDB code? → ACTUAL_BUG
   - No panic but assertion failure? → ACTUAL_BUG

4. **Check test code**
   - Unrealistic timeout? → TEST_BUG
   - Failed to install dependency? → TEST_BUG

5. **Check for patterns in similar issues**
   - Same failure repeatedly? → Likely ACTUAL_BUG
   - Different failures on same test? → Likely TEST_BUG or INFRASTRUCTURE_FLAKE

6. **When in doubt, mark as uncertain**
   - Provide evidence for multiple possibilities
   - Explain what additional information would help
   - Recommend further investigation
