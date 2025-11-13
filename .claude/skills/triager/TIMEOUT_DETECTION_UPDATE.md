# Timeout Detection Update - January 30, 2026

## Summary

Updated the triage skill to prevent misclassifying test timeouts as goroutine leak bugs. This addresses the critical error made in issue #161919 where a test timeout (TPCC import took 8m30s, test timed out at 15m) was incorrectly classified as a shutdown coordination bug.

## Problem

**Issue #161919 - What Went Wrong:**

The triage analysis incorrectly concluded:
- **Wrong Classification:** ACTUAL_BUG (shutdown coordination failure, goroutine leaks)
- **Wrong Root Cause:** "Server shutdown coordination failure: SQL connection executor goroutines and async background tasks are not properly signaled during shutdown"
- **Wrong Evidence:** "Goroutine 87096 stuck for 1 minute at pkg/sql/conn_io.go:557 in StmtBuf.CurCmd()"

**What Actually Happened:**
- **Correct Classification:** TEST_BUG (test timeout - configuration issue)
- **Correct Root Cause:** Test timed out after 15 minutes because TPCC import took 8 minutes 30 seconds, combined with other operations
- **Correct Evidence:** Goroutine dump was generated when test was killed (SIGQUIT), goroutines were actively working, not leaked after shutdown

## Key Distinction

### Timeout (Test Killed Mid-Execution)
- Test duration ≈ timeout limit (e.g., 14m45s vs 15m00s timeout)
- Slow operation found (e.g., "import took 8m30s")
- Goroutines in "running" or "active" states (doing actual work)
- No shutdown attempted (no "leaktest.AfterTest" in stack traces)
- Goroutines dumped when test received SIGQUIT (killed by timeout)
- **Classification:** TEST_BUG or PERFORMANCE_REGRESSION

### Goroutine Leak (Shutdown Bug)
- Test duration << timeout limit (e.g., 2m vs 15m timeout)
- Shutdown attempted (leaktest.AfterTest called)
- Goroutines in "waiting" states (sync.Cond.Wait, select, chan receive)
- Long wait times (>1 minute) in idle states
- Goroutines dumped after clean shutdown completed
- **Classification:** ACTUAL_BUG

## Changes Made

### 1. log-analyzer/SKILL.md

Added new section **5.1: Detect Test Timeouts BEFORE Analyzing Goroutine Leaks**

**Key additions:**
- Check for timeout indicators in test.log
- Calculate test duration vs timeout limits
- Analyze test activity leading to timeout
- Distinguish timeout from goroutine leak with clear decision tree
- Look for performance indicators (slow imports, slow queries)
- Add critical output section for synthesis agent

**New detection logic:**
```bash
# Phase 5.1a: Check for timeout indicators
Grep -i "test timed out|timeout exceeded|panic: test timed out" test.log

# Phase 5.1b: Calculate test duration
# Compare duration against known timeout limits (10-15 min for Go tests)

# Phase 5.1c: Analyze test activity
Grep -i "import|loading|fixture|took [0-9]+m" test.log | tail -50

# Phase 5.1d: Decision tree
IF (duration ≈ timeout AND slow_operation_found):
    classification_hint = TEST_TOO_SLOW
ELSE IF (shutdown_attempted AND goroutines_waiting):
    classification_hint = ACTUAL_BUG
```

**Updated goroutine analysis:**
- Section 6f now requires checking timeout detection first
- Warns against analyzing goroutines as "leaks" if timeout detected
- Focus shifts to WHY test was slow, not why goroutines exist

**New output template:**
- Added `timeout_analysis` section to JSON output
- Added "🚨 Timeout Analysis" section to LOG_ANALYSIS.md template
- Provides explicit classification guidance for synthesis agent

### 2. synthesis-triager/SKILL.md

Added new section **1.1: Check for Timeout Detection FIRST**

**Key additions:**
- Mandatory check of LOG_ANALYSIS timeout section before any other analysis
- Clear decision logic: if timeout detected, stop analyzing goroutines as leaks
- Example from issue #161919 showing wrong vs correct classification
- Warning against common misclassification pattern

**Updated TEST_BUG criteria:**
- Added critical distinction between TEST_TIMEOUT and GOROUTINE_LEAK
- Explains when goroutines are expected (timeout) vs unexpected (leak)
- Clear classification guidance for each scenario

**Updated Decision Matrix:**
- Added three new rows specifically for timeout scenarios:
  - "Timeout + slow op" → TEST_BUG (timeout config)
  - "Goroutines after timeout" → TEST_BUG (NOT leak)
  - "Goroutines after shutdown" → ACTUAL_BUG (leak)

**Updated Common Pitfalls:**
- Added #9: "Misclassifying timeouts as goroutine leaks"
- References issue #161919 as example
- Emphasizes checking timeout analysis FIRST

### 3. triager/patterns.md

Expanded **Test Timeout Issues** section with critical pattern documentation

**Key additions:**
- **🚨 CRITICAL PATTERN: Timeout Misclassified as Goroutine Leak**
- Clear comparison table: TIMEOUT vs GOROUTINE LEAK
- Real example from issue #161919 showing wrong vs correct analysis
- Evidence to look for (bash commands for detection)
- Standard timeout patterns and common timeout limits

## Workflow Changes

### Old Workflow (Prone to Error)
1. Read LOG_ANALYSIS.md
2. See goroutine dump
3. Jump to conclusion: "goroutines running = leak = shutdown bug"
4. Classify as ACTUAL_BUG
5. **MISTAKE:** Missed that test timed out

### New Workflow (Error-Proof)
1. Read LOG_ANALYSIS.md
2. **CHECK TIMEOUT SECTION FIRST** (new step)
3. IF timeout detected:
   - Skip goroutine leak analysis
   - Focus on performance
   - Classify as TEST_BUG or PERFORMANCE_REGRESSION
4. IF no timeout:
   - Proceed with standard goroutine analysis
   - Check for shutdown attempts
   - Classify based on evidence

## Prevention Mechanisms

### 1. Mandatory Timeout Check
- LOG_ANALYSIS.md must include timeout analysis section
- SYNTHESIS must check this section FIRST before classification
- Explicit decision tree prevents skipping this step

### 2. Clear Visual Markers
- 🚨 emoji used to mark critical sections
- "CRITICAL" keywords highlight important checks
- Warning messages about common mistakes

### 3. Real Examples
- Issue #161919 documented as cautionary tale
- Wrong vs correct analysis shown side-by-side
- Helps future agents learn from past mistakes

### 4. Decision Trees
- IF/THEN logic makes decisions unambiguous
- No room for interpretation errors
- Clear classification guidance at each step

## Testing the Update

To verify the fix works, re-analyze issue #161919:

```bash
# Expected behavior with updated skill:

1. LOG_ANALYSIS detects timeout:
   - Test duration: 14m45s (estimated)
   - Timeout limit: 15m00s
   - Margin: 15 seconds
   - Slow operation: TPCC import 8m30s
   - Classification hint: TEST_TOO_SLOW

2. SYNTHESIS reads timeout analysis:
   - Sees: "Timeout Detected: YES"
   - Skips: Goroutine leak analysis
   - Classifies: TEST_BUG (timeout configuration)
   - Confidence: 0.85+

3. Final triage:
   - Classification: TEST_BUG
   - Root cause: Test needs longer timeout OR smaller TPCC fixture
   - Recommendation: Increase timeout to 20m OR reduce fixture size
   - NOT: Shutdown coordination bug, goroutine leak, etc.
```

## Files Modified

1. `.claude/skills/log-analyzer/SKILL.md`
   - Added section 5.1 (timeout detection)
   - Updated section 6f (goroutine leak analysis)
   - Updated JSON output template
   - Updated markdown output template

2. `.claude/skills/synthesis-triager/SKILL.md`
   - Added section 1.1 (timeout check first)
   - Updated TEST_BUG criteria
   - Updated decision matrix
   - Updated common pitfalls

3. `.claude/skills/triager/patterns.md`
   - Expanded test timeout issues section
   - Added critical pattern documentation
   - Added issue #161919 example

4. `.claude/skills/triager/TIMEOUT_DETECTION_UPDATE.md` (this file)
   - Documents the update
   - Explains the problem and solution
   - Provides testing guidance

## Impact

### Before Update
- High risk of misclassifying timeouts as shutdown bugs
- Teams investigating wrong root causes
- Wasted effort on "fixing" non-existent shutdown coordination bugs
- Low confidence in triage results

### After Update
- Timeout detection is mandatory first step
- Clear distinction between timeout and leak
- Correct classification leads to correct fixes
- Higher confidence in triage accuracy

## Metrics to Monitor

After deploying this update, monitor:
1. **Classification accuracy** for timeout-related failures
2. **False positive rate** for ACTUAL_BUG classifications
3. **Time to resolution** (should decrease with correct classification)
4. **Team satisfaction** (correct classification = less wasted effort)

## Future Improvements

Potential enhancements:
1. **Automatic timeout calculation** - parse test.log timestamps to calculate exact duration
2. **Baseline integration** - compare current duration to historical average
3. **Performance regression detection** - flag if operation is slower than baseline
4. **Test configuration recommendations** - suggest optimal timeout based on workload

## Conclusion

This update addresses a critical flaw in the triage process where test timeouts were systematically misclassified as goroutine leak bugs. By adding mandatory timeout detection as the first analysis step, we prevent this category of errors and ensure more accurate triage results.

The changes are backward compatible (timeout detection doesn't break existing analysis) and forward-looking (sets up infrastructure for performance regression detection).

**Key Takeaway:** Always check if test timed out BEFORE analyzing goroutines as leaks.
