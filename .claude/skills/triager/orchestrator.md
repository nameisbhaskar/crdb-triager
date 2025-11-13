# Triager Orchestration Guide

This document describes how the triager works as an orchestrator of specialized analysis agents.

## Architecture Overview

The triager uses a **multi-agent architecture** with specialized skills:

```
User: "Triage issue #156490"
         ↓
   [Triager Skill]
         ↓
    Orchestrates:
         ├─→ [log-analyzer agent] → LOG_ANALYSIS.md
         ├─→ [code-analyzer agent] → CODE_ANALYSIS.md
         ├─→ [issue-correlator agent] → ISSUE_CORRELATION.md
         └─→ [synthesis-triager agent] → TRIAGE.md + BUG_ANALYSIS.md
                                                ↓
                                         Final Decision
```

## Why Multi-Agent?

**Benefits:**
- **Parallel execution** - Log, code, and issue analysis can run concurrently
- **Specialized expertise** - Each agent focuses on one domain
- **Modularity** - Agents can be improved independently
- **Reusability** - Agents can be invoked standalone
- **Quality control** - Synthesis agent validates all inputs
- **Scalability** - Easy to add new analysis types

## Orchestration Workflow

### Phase 1: Parallel Analysis (Concurrent)

Launch three agents simultaneously using the Task tool with **general-purpose** subagent type:

**Agent 1: Log Analyzer**
```
Use Task tool with:
- subagent_type: "general-purpose"
- description: "Analyze logs and artifacts for issue"
- prompt: "You are a log analysis expert for CockroachDB test failures.

Read the log-analyzer skill documentation at .claude/skills/log-analyzer/SKILL.md
for detailed guidance on analyzing logs.

Your task:
1. Download artifacts for issue #<NUM> using: bash .claude/hooks/triage-download.sh <NUM>
2. Analyze test.log, system logs (journalctl, dmesg), and goroutine dumps
3. Extract: primary error, stack traces, timing, infrastructure issues
4. Create workspace/issues/<NUM>/LOG_ANALYSIS.md following the template in the skill doc

Be thorough but focused. Quote specific line numbers from logs."
```

**Agent 2: Code Analyzer**
```
Use Task tool with:
- subagent_type: "general-purpose"
- description: "Analyze codebase for test failure"
- prompt: "You are a code analysis expert for CockroachDB.

Read the code-analyzer skill documentation at .claude/skills/code-analyzer/SKILL.md
for detailed guidance on code analysis.

Your task:
1. Read the test source code to understand what it does
2. Trace error messages to their origin in the codebase
3. Find recent commits affecting relevant files
4. Classify: ACTUAL_BUG vs TEST_BUG vs expected behavior
5. Create workspace/issues/<NUM>/CODE_ANALYSIS.md following the template

Issue: #<NUM>
Use repository-relative paths like pkg/cli/demo_locality_test.go:21"
```

**Agent 3: Issue Correlator**
```
Use Task tool with:
- subagent_type: "general-purpose"
- description: "Find related GitHub issues"
- prompt: "You are an expert at finding related GitHub issues and failure patterns.

Read the issue-correlator skill documentation at .claude/skills/issue-correlator/SKILL.md
for detailed guidance on searching issues.

Your task:
1. Search for similar test failures using gh CLI
2. Find issues with same error messages
3. Identify failure patterns (platform, frequency)
4. Find related PRs and recent changes
5. Create workspace/issues/<NUM>/ISSUE_CORRELATION.md following the template

Issue: #<NUM>
Test: <test-name from issue>
Error: <primary error from issue>"
```

**Implementation:**
```
Send a SINGLE message with THREE Task tool calls to run agents in parallel.
This is critical for performance - all three agents run concurrently.
Wait for all three to complete before proceeding to synthesis.
```

### Phase 2: Synthesis (Sequential)

After all three analyses complete:

**Agent 4: Synthesis Triager**
```
Use Task tool with:
- subagent_type: "general-purpose"
- description: "Synthesize analysis and classify"
- prompt: "You are the final decision-maker for CockroachDB test failure triage.

Read the synthesis-triager skill documentation at .claude/skills/synthesis-triager/SKILL.md
for detailed guidance on making classifications.

Your task:
1. Read all three analysis documents:
   - workspace/issues/<NUM>/LOG_ANALYSIS.md
   - workspace/issues/<NUM>/CODE_ANALYSIS.md
   - workspace/issues/<NUM>/ISSUE_CORRELATION.md

2. Cross-validate evidence across all analyses
3. Apply classification logic:
   - INFRASTRUCTURE_FLAKE (infra caused it)
   - TEST_BUG (test code is wrong)
   - ACTUAL_BUG (product code has bug)

4. Determine confidence level (0.0-1.0)
5. Assign team based on component
6. Assess release-blocker status

7. Create workspace/issues/<NUM>/TRIAGE.md with final classification
8. If ACTUAL_BUG, also create workspace/issues/<NUM>/BUG_ANALYSIS.md

Issue: #<NUM>
Be thorough and evidence-based. Your classification is what teams act on."
```

## Orchestration Script

Here's how to orchestrate the triaging process:

```markdown
## Step 1: Validate Input

- Confirm issue number is provided
- Create workspace directory: workspace/issues/<NUM>/

## Step 2: Launch Parallel Analysis

Use the Task tool to launch all three agents concurrently:

**Important:** Send a SINGLE message with THREE Task tool uses for parallel execution.

```
I need to triage issue #156490. I'll launch three analysis agents in parallel:

1. Log analyzer to examine artifacts
2. Code analyzer to investigate the codebase
3. Issue correlator to find related problems

[Use Task tool three times in one message]
```

## Step 3: Wait for Completion

All three agents will work independently and produce their outputs.

Expected outputs:
- workspace/issues/156490/LOG_ANALYSIS.md
- workspace/issues/156490/CODE_ANALYSIS.md
- workspace/issues/156490/ISSUE_CORRELATION.md

## Step 4: Launch Synthesis

Once all three analyses are complete:

```
Now I'll launch the synthesis agent to make the final classification:

[Use Task tool with synthesis-triager]
```

## Step 5: Present Results

Read the final TRIAGE.md and present to user:
- Classification
- Confidence level
- Key evidence
- Recommendations
- Team assignment

For ACTUAL_BUG, also present BUG_ANALYSIS.md as fix guidance.
```

## Handling Errors

### If an agent fails:

**Partial failure (1-2 agents fail):**
- Proceed with available analyses
- Note missing information in synthesis
- Lower confidence level accordingly

**Complete failure (all agents fail):**
- Fall back to simple workflow
- Do manual analysis without agents
- Note in output that full analysis unavailable

### If synthesis produces low confidence:

**Confidence < 0.5:**
- Recommend additional investigation
- Suggest specific questions to answer
- May need manual triage

## Agent Communication

Agents communicate through files in workspace:

```
workspace/issues/156490/
├── LOG_ANALYSIS.md       ← log-analyzer output
├── CODE_ANALYSIS.md      ← code-analyzer output
├── ISSUE_CORRELATION.md  ← issue-correlator output
├── TRIAGE.md             ← synthesis-triager output (final)
└── BUG_ANALYSIS.md       ← synthesis-triager output (if bug)
```

## Customization

### Adjust parallelism:

**Sequential execution (if needed):**
```
1. Run log-analyzer first
2. Use its findings to inform code-analyzer
3. Run issue-correlator
4. Run synthesis
```

**Partial parallel:**
```
1. Run log-analyzer first (need error messages)
2. Run code-analyzer + issue-correlator in parallel
3. Run synthesis
```

### Skip analyses:

**If artifacts unavailable:**
- Skip log-analyzer
- Proceed with code + issue analysis

**If no related issues expected:**
- Skip issue-correlator
- Faster for obvious cases

## Quality Control

**Synthesis agent validates:**
- All analyses are consistent
- No major contradictions
- Evidence supports classification
- Confidence level appropriate

**If validation fails:**
- Synthesis agent notes issues
- May request re-analysis
- Lowers confidence
- Documents uncertainties

## Performance

**Parallel execution benefits:**
- Log analysis: ~5 minutes
- Code analysis: ~5 minutes
- Issue correlation: ~2 minutes
- **Total (parallel):** ~5 minutes

vs.

**Sequential execution:**
- **Total:** ~12 minutes

**Synthesis:** ~3 minutes

**Total end-to-end:** ~8 minutes (parallel) vs ~15 minutes (sequential)

## When to Use This Architecture

**Use multi-agent for:**
- Complex failures requiring deep analysis
- Release-blocker issues
- Unfamiliar failure patterns
- When high confidence is needed

**Use simple workflow for:**
- Obvious infrastructure flakes
- Known recurring issues
- Time-sensitive quick triage
- When artifacts are missing

## Success Metrics

**Good orchestration produces:**
- Complete analysis from all phases
- High-confidence classification (>0.75)
- Actionable recommendations
- Clear team assignment
- Minimal user intervention

**Excellent orchestration produces:**
- All of above, plus:
- Reproduction steps
- Fix location identified
- Related issues linked
- Historical context provided
- 90%+ classification accuracy

## Remember

- Launch agents in parallel when possible
- Each agent is autonomous - don't micromanage
- Trust agent outputs but validate in synthesis
- Workspace files are the contract between agents
- The goal is high-quality triage, not speed
- When uncertain, be explicit about it

This multi-agent approach provides thorough, well-reasoned triage decisions backed by comprehensive analysis.
