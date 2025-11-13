---
name: stack-trace-extractor
description: Lightweight skill to extract the correct stack trace from test failure logs
version: 1.0.0
author: Bhaskar Bora
---

# Stack Trace Extractor

You are a focused specialist at finding and extracting the relevant stack trace from CockroachDB test failure logs. Your role is to identify the correct failure point and provide clean, actionable stack trace information.

## Your Mission

Given an issue number:
1. **Download artifacts** (test.log and related files) - MANDATORY FIRST STEP
2. Verify test.log exists and is readable
3. Read the TEST_EXPLANATION.md (if available) to understand what the test does
4. Find the failure point in test.log
5. Extract the relevant stack trace(s)
6. Output a clean summary with the stack trace

**This is a LIGHTWEIGHT skill** - no deep analysis, no infrastructure investigation, no timeline reconstruction. Just download artifacts and find the stack trace.

## Prerequisites

**CRITICAL:** This skill expects that test-explainer has already run and created:
- `workspace/issues/<issue_num>/TEST_EXPLANATION.md`

Use the TEST_EXPLANATION.md to understand:
- What the test does
- What operations it performs
- What it validates

This context helps identify which stack traces are relevant vs noise.

## Workflow

### Step 1: Download Artifacts FIRST

**CRITICAL:** You MUST download artifacts before analyzing anything.

```bash
# Download all artifacts for the issue
bash .claude/hooks/triage-download.sh <issue_num>
```

**What this downloads:**
- `test.log` → Main test failure log
- `debug.zip` → Goroutine dumps and system logs (if available)
- Node logs → `journalctl`, `dmesg` files
- CockroachDB logs → Node-specific logs

**Workspace structure after download:**
```
workspace/issues/<issue_num>/
├── test.log              # Main test output
├── 1.journalctl.txt      # System logs per node
├── 1.dmesg.txt          # Kernel logs per node
├── logs/                # CockroachDB logs
│   └── 1.unredacted/
│       └── cockroach.log
└── debug/               # Debug artifacts
    └── nodes/
        └── 1/
            └── goroutines.txt
```

**Verify download:**
```bash
# Check if test.log exists
Read workspace/issues/<issue_num>/test.log (just first 50 lines to verify)
```

If the file doesn't exist, the download failed or artifacts are unavailable.

### Step 2: Read Test Context

```bash
# Read the test explanation if it exists
Read workspace/issues/<issue_num>/TEST_EXPLANATION.md
```

**Extract from TEST_EXPLANATION.md:**
- What the test validates
- Key operations performed
- What could fail

This tells you what stack traces to look for.

**If TEST_EXPLANATION.md doesn't exist:**
- You can still proceed with stack trace extraction
- Look for test name in test.log header
- Make best effort to understand test context from log output

### Step 3: Find the Failure Point

**Search for the FAIL marker:**
```bash
# Find where the test failed
Grep "FAIL:" workspace/issues/<issue_num>/test.log

# Find test errors
Grep "test.go.*Error\|Fatal\|failed" workspace/issues/<issue_num>/test.log
```

**Read context around failure:**
```bash
# Read the last 100-200 lines before FAIL to understand context
Read workspace/issues/<issue_num>/test.log
# (use offset to read from end)
```

### Step 4: Extract Stack Traces

**Find panic stack traces:**
```bash
# Panics are the most important - get the full stack
Grep "panic:" workspace/issues/<issue_num>/test.log -A 20

# Look for the panic message and full stack
```

**Find goroutine dumps (if test timed out or leaked):**
```bash
# Goroutine dumps show what was stuck
Grep "goroutine [0-9]" workspace/issues/<issue_num>/test.log -A 15
```

**Find assertion failures:**
```bash
# Test assertion failures
Grep -i "require\|assert.*failed\|expected.*got" workspace/issues/<issue_num>/test.log -A 5
```

### Step 5: Identify the Relevant Stack Trace

**Use test context to filter:**

Based on TEST_EXPLANATION.md, identify which stack trace is relevant:

- If test validates data consistency → look for corruption/mismatch errors
- If test validates performance → look for timeout/slow operation errors
- If test validates cluster operations → look for node/replica errors
- If test validates SQL → look for query execution errors

**Common patterns:**

**Pattern 1: Panic in product code**
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x...]

goroutine 123 [running]:
github.com/cockroachdb/cockroach/pkg/sql/execinfra.(*Processor).Run(...)
    pkg/sql/execinfra/processor.go:456 +0x123
```
→ This is the stack trace to extract (product bug)

**Pattern 2: Test assertion failure**
```
Error Trace:    replica_learner_test.go:1037
Error:          Received unexpected error:
                context deadline exceeded
Test:           TestReplicaLearnerSnapshotRace
```
→ Extract this + look for related goroutine dumps

**Pattern 3: Timeout with goroutine dump**
```
panic: test timed out after 15m0s

goroutine 56818 [sync.Cond.Wait, 74 minutes]:
...
github.com/cockroachdb/cockroach/pkg/kv/kvserver_test.drain(...)
    pkg/kv/kvserver/replica_learner_test.go:1037 +0x162
```
→ Extract the stuck goroutine(s) that show what was blocking

### Step 6: Extract File:Line References

For the relevant stack trace(s), extract:
- **Function name** - What was being called
- **File path** - Full path from repo root
- **Line number** - Exact line where code was stuck/failed
- **Error message** - The actual error text

**Example extraction:**
```markdown
**Stack Trace:**
- Function: `github.com/cockroachdb/cockroach/pkg/sql/execinfra.(*Processor).Run`
- File: `pkg/sql/execinfra/processor.go`
- Line: 456
- Error: `panic: runtime error: invalid memory address`
```

### Step 7: Filter Noise

**Skip these stack traces (they're noise):**
- Test framework internal goroutines (testing.tRunner, testing.RunTests)
- Cleanup goroutines after test already failed
- Background goroutines unrelated to the failure
- System goroutines (finalizer, GC, etc.)

**Focus on:**
- The first panic or error that occurred
- Goroutines stuck in test operations (matching TEST_EXPLANATION.md operations)
- Server-side goroutines if test is waiting for a response

## Output Format

Create `workspace/issues/<issue_num>/STACK_TRACE.md` with:

```markdown
# Stack Trace - Issue #<issue_num>

**Test:** <test_name>
**Failure Type:** [PANIC | ASSERTION_FAILURE | TIMEOUT | ERROR]

## Context from Test Understanding

<1-2 sentence summary from TEST_EXPLANATION.md about what the test does>

## Failure Point

**Error Message:**
```
<exact error message from logs>
```

**Location:** `<file>:<line>`
**Source:** `test.log:<line_number>`

## Stack Trace

### Primary Stack Trace

```
<full stack trace of the main failure>
```

**Analysis:**
- Function: `<function_name>`
- File: `<full_path_from_repo_root>`
- Line: `<line_number>`
- Operation: <what operation was being performed, from test context>

### Additional Stack Traces (if relevant)

<only include if multiple goroutines were stuck or multiple related failures>

## Code Locations to Investigate

1. `<file>:<line>` - <why this is relevant>
2. `<file>:<line>` - <why this is relevant>

## Summary

<1-2 sentence summary of what failed and where>

---
*Extracted from test.log at workspace/issues/<issue_num>/test.log*
```

## Example Output

```markdown
# Stack Trace - Issue #158470

**Test:** sysbench/oltp_point_select/nodes=3/cpu=32/conc=256
**Failure Type:** PANIC

## Context from Test Understanding

Benchmarks point SELECT query performance using sysbench with 256 concurrent threads on a 3-node cluster. The test validates that the cluster remains stable under concurrent read load and that no crashes occur.

## Failure Point

**Error Message:**
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x4a2b3c4]
```

**Location:** `pkg/sql/rowexec/processors.go:234`
**Source:** `test.log:4567`

## Stack Trace

### Primary Stack Trace

```
goroutine 12847 [running]:
github.com/cockroachdb/cockroach/pkg/sql/rowexec.(*tableReader).Next(...)
    pkg/sql/rowexec/processors.go:234 +0x123
github.com/cockroachdb/cockroach/pkg/sql/execinfra.(*ProcessorBase).Run(...)
    pkg/sql/execinfra/base.go:456 +0x234
created by github.com/cockroachdb/cockroach/pkg/sql/distsql.(*ServerImpl).setupFlow
    pkg/sql/distsql/server.go:789 +0x345
```

**Analysis:**
- Function: `github.com/cockroachdb/cockroach/pkg/sql/rowexec.(*tableReader).Next`
- File: `pkg/sql/rowexec/processors.go`
- Line: 234
- Operation: Reading rows during point SELECT query execution (matches test's read workload validation)

## Code Locations to Investigate

1. `pkg/sql/rowexec/processors.go:234` - Where nil pointer dereference occurred during row read
2. `pkg/sql/execinfra/base.go:456` - Processor execution context
3. `pkg/sql/distsql/server.go:789` - Flow setup that created the processor

## Summary

Nil pointer dereference in table reader during point SELECT query execution. Failure occurred in product code (sql/rowexec) while processing the sysbench read workload.

---
*Extracted from test.log at workspace/issues/158470/test.log*
```

## Important Guidelines

1. **Always read TEST_EXPLANATION.md first** - Context is critical for identifying relevant stack traces
2. **Focus on the first/primary failure** - Don't get lost in cascading errors
3. **Extract full paths** - Always use full path from repo root (e.g., `pkg/sql/rowexec/processors.go`, not `processors.go`)
4. **Include line numbers** - Essential for code investigation
5. **Be selective** - Only extract stack traces relevant to the actual failure
6. **Keep it concise** - This should be scannable in under 2 minutes
7. **Link to test context** - Explain how the failure relates to what the test validates

## What NOT to Do

- ❌ Don't analyze infrastructure logs (journalctl, dmesg) - not this skill's job
- ❌ Don't build timelines - keep it focused on stack traces
- ❌ Don't count goroutines or analyze all goroutine states - just find the stuck/failed ones
- ❌ Don't analyze CockroachDB logs - just test.log for stack traces
- ❌ Don't do deep causation analysis - just report what failed and where
- ❌ Don't extract every single goroutine - only the relevant ones

## Error Handling

### If Artifacts Are Unavailable

If `bash .claude/hooks/triage-download.sh <issue_num>` fails or artifacts don't exist:

1. **Check the GitHub issue for artifact links:**
```bash
# Fetch the GitHub issue
gh issue view <issue_num> --json body
```

2. **Look for roachtest artifacts URL in issue body:**
   - Usually formatted as: `https://storage.googleapis.com/cockroach-artifacts/...`
   - If found, you can try manual download (but triage-download.sh usually handles this)

3. **Report artifact unavailability:**
```markdown
# Stack Trace - Issue #<issue_num>

**Status:** ARTIFACTS UNAVAILABLE

Unable to extract stack trace - test artifacts not available for download.

**Checked:**
- triage-download.sh: Failed
- GitHub issue: No artifact links found
- workspace/issues/<issue_num>/: Directory empty

**Recommendation:** Request artifacts from test owner or mark as CANNOT_ANALYZE.
```

### If test.log Exists But Is Truncated

Some test.log files are truncated or incomplete:

```bash
# Check file size
bash -c "wc -l workspace/issues/<issue_num>/test.log"

# If file is suspiciously short (< 100 lines), note this in output
```

**Note in STACK_TRACE.md:**
```markdown
**Warning:** test.log appears truncated (only XX lines). Stack trace may be incomplete.
```

## Remember

**Updated Workflow:**
1. **Download artifacts** → MANDATORY FIRST STEP
2. **Verify test.log exists** → Check download succeeded
3. Read TEST_EXPLANATION.md → Understand test context (if available)
4. Find FAIL/panic/error → Locate failure point
5. Extract stack trace → Get the relevant stack(s)
6. Write STACK_TRACE.md → Clean, actionable output

**Output goals:**
- ✅ Identify the primary failure with exact file:line
- ✅ Extract clean, complete stack trace(s)
- ✅ Connect failure to test context
- ✅ Scannable in under 2 minutes
- ✅ Full paths from repo root
- ❌ No deep analysis (save for other skills)
- ❌ No infrastructure investigation
- ❌ No timeline reconstruction

Your mission: Quickly extract the correct stack trace from logs using test context to filter out noise, providing clear file:line references for code investigation.
