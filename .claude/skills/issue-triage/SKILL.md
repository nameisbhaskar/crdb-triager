---
name: issue-triage
description: "[DEFAULT] Primary skill for triaging CockroachDB roachtest failures - understands the test first, then analyzes failure"
version: 1.0.0
author: Bhaskar Bora
default: true
---

# Issue Triage - Test Understanding First (DEFAULT TRIAGE SKILL)

**This is the primary triage skill for CockroachDB test failures.**

When the user says "triage", "triage issue", "analyze issue", or similar commands, **this is the skill to use**.

You are a lightweight triage assistant that helps understand CockroachDB test failures by first understanding what the test does, then analyzing the failure.

## ⚠️ AUTOMATIC EXECUTION MODE

**This skill AUTOMATICALLY runs a four-step pipeline:**
1. **test-explainer** → Understand what the test does
2. **stack-trace-extractor** → Find where it failed
3. **infra-flake-detector** → Check if it's an infrastructure flake
4. **team-assigner** → Determine which team should own the issue

**Do NOT wait for user input between these steps.** Execute all four skills sequentially and then present a final summary to the user.

## Your Mission

Given a GitHub issue number or URL for a test failure, **AUTOMATICALLY execute the complete triage pipeline**:
1. Use the **test-explainer** skill to understand what the test does
2. Use the **stack-trace-extractor** skill to find the failure stack trace
3. Use the **infra-flake-detector** skill to check if this is an infrastructure flake
4. Use the **team-assigner** skill to determine which team should own the issue
5. Present a concise summary with classification and team assignment

**IMPORTANT:** All four sub-skills (test-explainer, stack-trace-extractor, infra-flake-detector, team-assigner) should be invoked automatically in sequence. Do NOT wait for user input between skills. This is an automated pipeline.

## Workflow

### Step 1: Parse the Issue Metadata

Extract basic info from the GitHub issue:

```bash
# Use gh CLI to fetch the issue (or curl if gh auth fails)
gh issue view <issue-number> --repo cockroachdb/cockroach --json title,body,number,url
# OR
curl -s "https://api.github.com/repos/cockroachdb/cockroach/issues/<issue-number>"
```

**Extract:**
- `issue_num` - Issue number
- `test_name` - Name of the failing test (from title or body)
- `sha` - Git commit SHA where test failed (40-char hex)
- `title` - Issue title
- `url` - GitHub issue URL

### Step 2: Understand the Test First (AUTOMATIC)

**AUTOMATICALLY call the test-explainer skill - do NOT wait for user confirmation:**

```
Use Skill tool to invoke:
- skill: "test-explainer"
- args: "<issue-number>"
```

The test-explainer will:
- Checkout code at the specific SHA
- Find and analyze the test code
- Generate `workspace/issues/<issue_num>/TEST_EXPLANATION.md`
- Return a concise explanation of what the test does

**Wait for test-explainer to complete before proceeding to Step 3.**

### Step 3: Extract the Stack Trace (AUTOMATIC)

**AUTOMATICALLY call the stack-trace-extractor skill immediately after test-explainer completes:**

```
Use Skill tool to invoke:
- skill: "stack-trace-extractor"
- args: "<issue-number>"
```

The stack-trace-extractor will:
- Read TEST_EXPLANATION.md for context
- Download and analyze test.log
- Find the failure point and extract relevant stack trace(s)
- Generate `workspace/issues/<issue_num>/STACK_TRACE.md`
- Return file:line references for the failure

**Wait for stack-trace-extractor to complete before proceeding to Step 4.**

### Step 4: Check for Infrastructure Flake (AUTOMATIC)

**AUTOMATICALLY call the infra-flake-detector skill immediately after stack-trace-extractor completes:**

```
Use Skill tool to invoke:
- skill: "infra-flake-detector"
- args: "<issue-number>"
```

The infra-flake-detector will:
- Read STACK_TRACE.md to extract error patterns
- Search GitHub for similar issues with X-infra-flake label
- Match based on error stack (not test name)
- Generate `workspace/issues/<issue_num>/INFRA_FLAKE_ANALYSIS.md`
- Return classification: LIKELY_INFRA_FLAKE / POSSIBLE_INFRA_FLAKE / NOT_INFRA_FLAKE

**Wait for infra-flake-detector to complete before proceeding to Step 5.**

### Step 5: Assign to Team (AUTOMATIC)

**AUTOMATICALLY call the team-assigner skill immediately after infra-flake-detector completes:**

```
Use Skill tool to invoke:
- skill: "team-assigner"
- args: "<issue-number>"
```

The team-assigner will:
- Read TEST_EXPLANATION.md to understand test owner and purpose
- Read STACK_TRACE.md to understand failure location
- Read INFRA_FLAKE_ANALYSIS.md to check classification
- Determine which team should own this issue (TestEng vs product team)
- Distinguish between test framework bugs and product bugs
- Generate `workspace/issues/<issue_num>/TEAM_ASSIGNMENT.md`
- Return team recommendation with confidence level

**Wait for team-assigner to complete before proceeding to Step 6.**

### Step 6: Present Summary

After all four skills have completed, show the user:
- Link to TEST_EXPLANATION.md
- Link to STACK_TRACE.md
- Link to INFRA_FLAKE_ANALYSIS.md
- Link to TEAM_ASSIGNMENT.md
- Brief summary: what the test does + where it failed + classification + team assignment
- Ask what to do next (only if classification is unclear)

## Output

Keep output minimal and focused:

```markdown
# Issue #<issue_num>: <test_name>

## Test Understanding
✓ Generated: `workspace/issues/<issue_num>/TEST_EXPLANATION.md`

**What this test does:**
<1-2 sentence summary from TEST_EXPLANATION.md>

## Failure Analysis
✓ Generated: `workspace/issues/<issue_num>/STACK_TRACE.md`

**Where it failed:**
- File: `<file>:<line>` (from STACK_TRACE.md)
- Error: `<error_message>`
- Type: [PANIC | ASSERTION_FAILURE | TIMEOUT | ERROR]

## Infrastructure Flake Classification
✓ Generated: `workspace/issues/<issue_num>/INFRA_FLAKE_ANALYSIS.md`

**Classification:** [LIKELY_INFRA_FLAKE | POSSIBLE_INFRA_FLAKE | NOT_INFRA_FLAKE]
**Confidence:** [HIGH | MEDIUM | LOW]

**Reasoning:** <brief summary from INFRA_FLAKE_ANALYSIS.md>

**Similar issues with X-infra-flake label:**
- #<num1>: <title> (exact match)
- #<num2>: <title> (partial match)
<or "None found" if classification is NOT_INFRA_FLAKE>

## Team Assignment
✓ Generated: `workspace/issues/<issue_num>/TEAM_ASSIGNMENT.md`

**Assigned Team:** <team_name>
**Confidence:** [HIGH | MEDIUM | LOW]
**GitHub Label:** `<T-team-label>`

**Reasoning:** <brief summary from TEAM_ASSIGNMENT.md>

## Recommendation

<1-2 sentence recommendation based on classification and team assignment>

**If LIKELY_INFRA_FLAKE:**
Recommend labeling this as `X-infra-flake` and closing as duplicate of #<num>.

**If POSSIBLE_INFRA_FLAKE:**
Recommend further investigation. Check infrastructure logs or correlate with similar issues.

**If NOT_INFRA_FLAKE:**
Recommend investigating as a product bug. Check the code at `<file>:<line>`.

## Next Steps (if needed)
<only show if classification is POSSIBLE or if user wants deeper analysis>
Would you like me to:
- Analyze infrastructure logs in detail?
- Look at the code at the failure location?
- Search for more related issues?
```

## Important Guidelines

1. **AUTOMATIC EXECUTION** - Run all four sub-skills (test-explainer, stack-trace-extractor, infra-flake-detector, team-assigner) automatically without waiting for user input between them
2. **Sequential execution** - Wait for each skill to complete before calling the next (dependencies exist)
3. **Always use test-explainer first** - Understanding the test is critical before analyzing failures
4. **Keep it lightweight** - This skill should use minimal tokens by delegating to specialized sub-skills
5. **Workspace organization** - All files go in `workspace/issues/<issue_num>/`
6. **Present final summary only** - Only show output to user after all four skills have completed

## Skill Integration

**Step 1 - Using test-explainer:**
```
Skill tool with:
- skill: "test-explainer"
- args: "<issue-number>"
```

**Step 2 - Using stack-trace-extractor:**
```
Skill tool with:
- skill: "stack-trace-extractor"
- args: "<issue-number>"
```

**Step 3 - Using infra-flake-detector:**
```
Skill tool with:
- skill: "infra-flake-detector"
- args: "<issue-number>"
```

**Note:** These skills run sequentially:
- stack-trace-extractor depends on TEST_EXPLANATION.md from test-explainer
- infra-flake-detector depends on STACK_TRACE.md from stack-trace-extractor

## Remember

This is a **lightweight** triage skill that:
- ✅ Understands the test first (via test-explainer)
- ✅ Extracts stack traces (via stack-trace-extractor)
- ✅ Detects infra flakes (via infra-flake-detector)
- ✅ Provides classification with confidence level
- ✅ Presents clear, concise output with recommendation
- ✅ Organizes work in workspace
- ❌ Does NOT do extensive infrastructure log analysis automatically
- ❌ Does NOT download all artifacts automatically
- ❌ Does NOT run heavy correlation/timeline analysis

**Workflow (ALL STEPS AUTOMATIC):**
1. Parse issue → Get test name, SHA, issue number
2. **AUTOMATICALLY** call test-explainer skill → Understand what test does
3. **AUTOMATICALLY** call stack-trace-extractor skill → Find where it failed
4. **AUTOMATICALLY** call infra-flake-detector skill → Check if it's an infra flake
5. Present summary → Show all four analyses + recommendation (ONLY output to user AFTER all skills complete)

**CRITICAL:** Do NOT wait for user input between steps 2-4. Execute the entire pipeline automatically.

**Token efficiency:**
- test-explainer: Focused on reading code, no log analysis
- stack-trace-extractor: Focused on stack traces only, no deep log diving
- infra-flake-detector: Focused on GitHub search for similar issues with X-infra-flake label
- Combined: Fast triage with classification and actionable recommendation
- Heavy analysis: Only if classification is unclear or user requests it

Your mission: Quickly triage test failures by understanding what the test does + where it failed + whether it's an infra flake, providing actionable recommendations.

## Execution Example

When user says: `triage 163345`

**Correct execution (AUTOMATIC):**
```
1. Parse issue 163345 metadata (test name, SHA, etc.)
2. Invoke Skill: test-explainer with args "163345"
   → Wait for completion
3. Invoke Skill: stack-trace-extractor with args "163345"
   → Wait for completion
4. Invoke Skill: infra-flake-detector with args "163345"
   → Wait for completion
5. Read all four output files:
   - workspace/issues/163345/TEST_EXPLANATION.md
   - workspace/issues/163345/STACK_TRACE.md
   - workspace/issues/163345/INFRA_FLAKE_ANALYSIS.md
   - workspace/issues/163345/TEAM_ASSIGNMENT.md
6. Present comprehensive summary to user with:
   - What the test does (from TEST_EXPLANATION.md)
   - Where it failed (from STACK_TRACE.md)
   - Classification (from INFRA_FLAKE_ANALYSIS.md)
   - Team assignment (from TEAM_ASSIGNMENT.md)
   - Recommendation
```

**Incorrect execution (DO NOT DO THIS):**
```
1. Invoke test-explainer
2. Show results to user and stop ❌ WRONG - continue automatically!
```

**Remember:** The user should only see ONE final output after all four skills complete, not four separate outputs.