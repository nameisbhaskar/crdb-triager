# CockroachDB Roachtest Triage Assistant

An AI-powered triage assistant for analyzing CockroachDB roachtest failures. This system combines Claude Code with expert triage knowledge to help you quickly classify test failures and determine root causes.

## What It Does

This tool helps you analyze CockroachDB nightly test failures to determine:
- **Infrastructure flakes** - VM issues, network problems, disk full, OOM kills, etc.
- **Product bugs** - Real regressions or bugs in CockroachDB code that need team assignment

The triager works **interactively** - you drive the conversation, ask questions, and guide the analysis. Claude Code acts as your expert assistant, not a fully automated system.

## How It Works

**Lightweight Multi-Skill Architecture** The triage system uses focused, specialized skills that work together:

```
User Request: "Triage issue #156490"
         ↓
   [issue-triage] (DEFAULT SKILL)
         ↓
    Calls specialized sub-skills sequentially:
         ├─→ [test-explainer]         → Understand what the test does
         ├─→ [stack-trace-extractor]  → Find failure stack traces
         ├─→ [infra-flake-detector]   → Check for infrastructure flakes
         └─→ [team-assigner]          → Determine which team owns the issue
                   ↓
         Quick triage summary + team assignment + next steps
```

**Each skill is specialized:**
1. **issue-triage** (DEFAULT) - Orchestrates the triage workflow, understands test first
2. **test-explainer** - Reads test code to understand what the test validates
3. **stack-trace-extractor** - Finds and extracts relevant stack traces from logs
4. **infra-flake-detector** - Searches for similar issues with X-infra-flake label
5. **team-assigner** - Determines which team should own the issue (TestEng vs product teams)

**Benefits:**
- Fast, focused triage workflow
- Understand the test first (context matters!)
- Specialized skills for each analysis phase
- Progressive complexity (simple cases stay simple)
- Easy to follow and verify

**You're still in control:**
- Guide the analysis with specific questions
- Override classifications if needed
- Request deeper investigation
- Approve or reject recommendations

## Quick Start

### Prerequisites

You'll need these tools installed:

```bash
# GitHub CLI (for fetching issue data)
brew install gh
gh auth login

# jq (for JSON parsing)
brew install jq

# gcloud (for Prometheus metrics access via IAP)
gcloud auth login

# Git (for source code submodule)
git submodule update --init --recursive
```

**Environment variables:**

```bash
# Required - get this from TeamCity
export TEAMCITY_TOKEN="your_teamcity_token_here"

# Optional - gh CLI handles this automatically
export GITHUB_TOKEN="your_github_token"

# Optional - for Snowflake test history and bisect features
export SNOWFLAKE_ACCOUNT="your_account"
export SNOWFLAKE_USER="your_username"
# Use PAT (Personal Access Token) for authentication
export SNOWFLAKE_PASSWORD="your_personal_access_token"
```

### Usage

Just start a conversation with Claude Code in the root of this repository
and mention what you want to triage:

```
You: Triage issue #157102

Claude: 🎯 SKILL ACTIVATION
        📚 Using skill: issue-triage (default triage skill)

        I'll help you triage this issue. Let me start by understanding
        what the test does, then extract the failure stack trace...
```

The issue-triage skill automatically:
- Parses the GitHub issue
- Downloads TeamCity artifacts to `workspace/issues/157102/`
- Checks out CockroachDB source at the failing SHA
- Reads logs and provides initial analysis

**Then you drive the conversation:**

```
You: Check the journalctl logs for OOM

You: Grep the CRDB source for that error message

You: What does the test code actually do?

You: Search for similar failures in the past month

You: Is this a release blocker?
```

The assistant responds to your requests and helps you build up context until you're confident in the classification.

## New Features

### 🔍 Automatic Metrics Extraction

The triage download script now automatically extracts key metrics from Prometheus:
- **Memory usage (RSS)** - Detects OOM conditions
- **Disk space available** - Detects disk full scenarios
- **CPU usage** - Identifies CPU starvation
- **Goroutine count** - Spots goroutine leaks
- **Node liveness** - Tracks node crashes

Metrics are saved to `workspace/issues/<issue-num>/extracted-metrics.json` with automatic analysis hints.

### 📊 Snowflake Integration (Optional)

When configured, the system automatically queries Snowflake to:
- Find the last successful run of the failing test
- Identify the commit range for bisecting
- Search test history to find the first failing commit
- Calculate how many commits need to be bisected

Results are saved to `workspace/issues/<issue-num>/bisect-info.json`.

**Setup Snowflake:**
```bash
export SNOWFLAKE_ACCOUNT="your_account"
export SNOWFLAKE_USER="your_username"
export SNOWFLAKE_PASSWORD="your_pat_token"  # Personal Access Token
```

Install Snowflake CLI:
```bash
# macOS
brew install snowflake-snowsql

# Or download from: https://docs.snowflake.com/en/user-guide/snowsql-install-config.html
```

### 🔁 Bisect Helper

New helper script to assist with bisecting failures:

```bash
# Show bisect information and instructions
bash .claude/hooks/bisect-helper.sh info <issue-number>

# View the diff between last success and failure
bash .claude/hooks/bisect-helper.sh diff <issue-number>
```

The bisect helper will:
- Show the SHA range to bisect
- Tell you if the first failure was already found in test history
- Provide git commands to run manual bisect if needed
- Show all commits in the range

### ✅ Environment Validation

The download script now validates your environment before starting:
- Checks for required tools (gh, jq, curl, unzip)
- Verifies TEAMCITY_TOKEN is set
- Confirms GitHub CLI authentication
- Warns if CockroachDB submodule isn't initialized

This prevents failures mid-download and gives clear setup instructions.

## What Gets Analyzed

When you triage an issue, the assistant has access to:

**Artifacts downloaded automatically:**
- `test.log` - Main test output (usually the smoking gun)
- `test.xml` - Structured test results
- `debug.zip` - System logs from all nodes (journalctl, dmesg, CockroachDB logs)
- Node-specific logs: `{NODE_ID}.dmesg.txt`, `{NODE_ID}.journalctl.txt`
- CockroachDB logs: `logs/{NODE_ID}.unredacted/*.log`

**Source code at exact SHA:**
- Test source: `cockroachdb/pkg/cmd/roachtest/tests/`
- Full CockroachDB source for grepping error messages

**External context:**
- Similar issues via GitHub search
- Team ownership mappings
- Prometheus metrics (OOM, CPU, disk space) via IAP-authenticated queries

**Expert knowledge:**
- Infrastructure flake patterns (OOM kills, disk full, network issues)
- Release-blocker criteria
- Team assignment logic

## Example: Interactive Triage Session

Here's what a typical triage session looks like:

```
You: Triage issue #157102

Claude: [Downloads artifacts, reads test.log]

        Initial analysis: Test failed with "context deadline exceeded"
        Let me check if this is an infrastructure issue...

You: Check the system logs for OOM

Claude: [Reads journalctl logs]

        Found evidence of OOM kill at 10:45:23 UTC
        Node n3 was killed by the kernel with exit code 137

You: Is this a release blocker?

Claude: No, this is an infrastructure flake (OOM kill).
        Confidence: 0.95

        Evidence:
        - Kernel OOM killer invoked
        - No product code changes could prevent this
        - Test passed on retry

        Classification: INFRASTRUCTURE_FLAKE
        Team: Test Platform (for investigation of resource limits)
```

**You drive the depth of analysis.** Ask follow-up questions, request specific log files, or ask Claude to grep the source code for error messages.

## Tips for Effective Triage

1. **Let the skill activate** - When you mention "triage" or an issue number, let Claude load the skill
2. **Guide the analysis** - You know what to look for; ask specific questions
3. **Check system logs** - OOM kills, disk full, and network issues hide in journalctl/dmesg
4. **Read test source** - Understanding test intent helps classify failures
5. **Search for patterns** - Ask Claude to find similar historical issues
6. **Be pragmatic** - Don't spend 30 minutes on an obvious flake
7. **Use Prometheus** - Memory/CPU metrics can confirm OOM or resource starvation
8. **Trust your judgment** - The assistant provides evidence; you make the final call

## Why This Works Better Than Automation

**The old approach (Go tool with fixed prompts):**
- Rigid workflow couldn't adapt to different failure types
- Token limits forced chunking and information loss
- No ability to ask follow-up questions
- Generic analysis that missed nuance

**The triager skill approach:**
- You steer based on your expertise
- Full context window (200K tokens) - read entire logs
- Interactive: "check this", "grep for that", "what does the test do?"
- Learns from your guidance during the session
- Handles edge cases through conversation

Think of it as **pair programming for triage** - you're the expert, Claude is your assistant with perfect memory and the ability to instantly search thousands of lines of logs.

## Under the Hood

**Skill Components:**

- `.claude/skills/issue-triage/` - **DEFAULT skill** for triage (orchestrator)
- `.claude/skills/testeng-oncall-triage/` - **Batch triage** for TestEng oncall
- `.claude/skills/test-explainer/` - Understands what tests do
- `.claude/skills/stack-trace-extractor/` - Extracts failure stack traces
- `.claude/skills/infra-flake-detector/` - Detects infrastructure flakes
- `.claude/skills/team-assigner/` - Determines team ownership (TestEng vs product teams)
- `.claude/skills/log-analyzer/` - Deep log/artifact analysis (for complex cases)
- `.claude/skills/code-analyzer/` - Codebase investigation (for complex cases)
- `.claude/skills/synthesis-triager/` - Final classification (for complex cases)
- `.claude/skills/triager/` - **DEPRECATED** (use issue-triage instead)
- `.claude/hooks/triage-download.sh` - Downloads artifacts from TeamCity
- `cockroachdb/` - Source code submodule (auto-checked-out at failure SHA)
- `workspace/issues/*/` - Per-issue workspace for artifacts and analysis

**Analysis Outputs (per issue):**

```
workspace/issues/156490/
├── TEST_EXPLANATION.md      # From test-explainer - what the test does
├── STACK_TRACE.md           # From stack-trace-extractor - where it failed
├── INFRA_FLAKE_ANALYSIS.md  # From infra-flake-detector - flake classification
├── TEAM_ASSIGNMENT.md       # From team-assigner - which team owns the issue
├── LOG_ANALYSIS.md          # From log-analyzer (if deep dive needed)
├── CODE_ANALYSIS.md         # From code-analyzer (if deep dive needed)
└── TRIAGE.md                # Final classification (legacy)
```

**Dependencies:**

- `gh` - GitHub CLI for issue data
- `jq` - JSON parsing in bash scripts
- `gcloud` - IAP token generation for Prometheus access
- `git` - Source code submodule management

## Troubleshooting

**Skill not activating?**
- Use explicit keywords: "triage issue #12345" or "analyze test failure"
- The default skill is now `issue-triage` (not the old `triager` skill)
- If you see `triager` being invoked, it's deprecated - stop and use `/issue-triage` instead

**Artifacts download failing?**
- Verify `TEAMCITY_TOKEN` environment variable is set
- Check the TeamCity artifact URL is accessible
- Ensure sufficient disk space in `workspace/`

**Prometheus metrics access failing?**
- Run `gcloud auth login` to authenticate
- Verify your account has IAP permissions for test infrastructure
- Test with: `bash .claude/hooks/test-metrics.sh <issue-number>`

**Source code checkout issues?**
- Ensure git submodule is initialized: `git submodule update --init`
- Check network access to github.com/cockroachdb/cockroach

## Advanced: Customizing the Skills

The skill knowledge lives in `.claude/skills/`:

**Primary triage skill:**
- [.claude/skills/issue-triage/SKILL.md](.claude/skills/issue-triage/SKILL.md) - Main triage workflow

**Batch triage skill:**
- [.claude/skills/testeng-oncall-triage/SKILL.md](.claude/skills/testeng-oncall-triage/SKILL.md) - Batch triage for TestEng oncall

**Specialized sub-skills:**
- [.claude/skills/test-explainer/SKILL.md](.claude/skills/test-explainer/SKILL.md) - Test understanding logic
- [.claude/skills/stack-trace-extractor/SKILL.md](.claude/skills/stack-trace-extractor/SKILL.md) - Stack trace extraction
- [.claude/skills/infra-flake-detector/SKILL.md](.claude/skills/infra-flake-detector/SKILL.md) - Flake detection patterns
- [.claude/skills/team-assigner/SKILL.md](.claude/skills/team-assigner/SKILL.md) - Team ownership routing

**Deep-dive skills (for complex cases):**
- [.claude/skills/log-analyzer/SKILL.md](.claude/skills/log-analyzer/SKILL.md) - Deep log analysis
- [.claude/skills/code-analyzer/SKILL.md](.claude/skills/code-analyzer/SKILL.md) - Code investigation
- [.claude/skills/synthesis-triager/SKILL.md](.claude/skills/synthesis-triager/SKILL.md) - Final classification

**The best part:** You can edit these files during a triage session and the skill will use the updated knowledge immediately in the next conversation.

## Why a Skill Instead of an Agent?

This system is intentionally built as a **skill** (expert knowledge base) rather than an **agent** (autonomous workflow):

**Skills are better for triage because:**
- You're the domain expert - the skill augments your knowledge
- Every failure is different - rigid workflows can't handle edge cases
- Human judgment is critical for release-blocker decisions
- Interactive guidance beats automation for complex analysis

**You maintain control:**
- "Check this specific log file"
- "Grep the source for this error"
- "Is this similar to issue #123456?"
- Make the final call on classification and confidence

Think of it as an expert assistant, not autopilot.

## Batch Triage for TestEng Oncall

The **testeng-oncall-triage skill** automates batch triage of all T-testeng labeled issues from recent days. This is designed for the TestEng oncall engineer's daily or weekly triage routine.

### What It Does

This skill:
1. **Fetches all T-testeng issues** from a specified time range (default: last 2 days)
2. **Triages each issue automatically** by invoking the `issue-triage` skill (4-step pipeline)
3. **Extracts team assignments** from TEAM_ASSIGNMENT.md for each issue
4. **Generates CSV export** with team assignments and ready-to-paste GitHub comments
5. **Aggregates results** into a summary report organized by classification

### Usage Examples

**Daily oncall triage:**
```
execute testeng oncall triage
```

**Custom time ranges:**
```
execute testeng oncall triage for last 3 days
execute testeng oncall triage for last week
execute testeng oncall triage from last Monday
```

**Auto mode (skip confirmation):**
```
execute testeng oncall triage auto
```

### What You Get

A comprehensive summary report organized by classification:

```markdown
# TestEng Oncall Triage Report
**Period:** Last 2 days
**Issues Triaged:** 8

## Infrastructure Flakes (5 issues)
- #123456 - roachtest/acceptance (LIKELY_INFRA_FLAKE)
  → Matches #120000, recommend labeling X-infra-flake
- #123458 - roachtest/backup (POSSIBLE_INFRA_FLAKE)
  → Similar pattern, needs investigation

## Product Bugs (2 issues)
- #123457 - roachtest/kv/splits (NOT_INFRA_FLAKE)
  → Panic in pkg/kv/kvserver/split.go:234
  → Assign to @kvserver team

## Unable to Classify (1 issue)
- #123459 - Artifacts unavailable
```

Plus detailed analysis for each issue in `workspace/issues/<issue_num>/`:
- `TEST_EXPLANATION.md` - What the test does
- `STACK_TRACE.md` - Where it failed
- `INFRA_FLAKE_ANALYSIS.md` - Classification with GitHub comment
- `TEAM_ASSIGNMENT.md` - Team ownership and routing

**CSV Export for Spreadsheet:**
- `workspace/oncall-triage-reports/<DATE>_testeng_triage.csv`
- Includes: classification, team assignment, confidence, GitHub comments
- Ready for import into Google Sheets or Excel
- Columns: Issue Number, Title, Test Name, Classification, Confidence, Error Pattern, URL, Similar Issues, Team Assigned, Team Confidence, Recommendation, GitHub Comment

### When to Use

Use batch triage for:
- **Daily oncall routine** - Triage all new failures overnight
- **Weekly handoff** - Generate summary of the week's issues
- **Catch-up after being offline** - Process multiple days of issues
- **Team triage meetings** - Pre-triage issues before discussion

### How It Works

The skill processes issues sequentially:
1. Fetches T-testeng issues via GitHub CLI
2. For each issue, invokes `issue-triage` skill which:
   - Runs `test-explainer` to understand the test
   - Runs `stack-trace-extractor` to find failures
   - Runs `infra-flake-detector` to check for flakes
   - Runs `team-assigner` to determine team ownership
3. Reads triage results from workspace files (INFRA_FLAKE_ANALYSIS.md, TEAM_ASSIGNMENT.md)
4. Generates CSV export with team assignments and GitHub comments
5. Generates summary report with actionable recommendations

**Time estimate:** ~2-3 minutes per issue
- 5 issues: ~10-15 minutes
- 10 issues: ~20-30 minutes

**See [.claude/skills/testeng-oncall-triage/](./.claude/skills/testeng-oncall-triage/) for detailed documentation.**

### Integration with Daily Workflow

**Morning routine:**
```bash
# 1. Check what needs triage
execute testeng oncall triage

# 2. Review summary report
# 3. Label infrastructure flakes
# 4. Route product bugs to teams
# 5. Follow up on unclear cases
```

**Weekly handoff:**
```bash
# Generate full week summary
execute testeng oncall triage for last week

# Share summary with next oncall
```

### Benefits

- **Save time** - Automatically triage multiple issues instead of one-by-one
- **Consistency** - Same triage process for every issue
- **Comprehensive** - Never miss an issue in the oncall queue
- **Actionable** - Get clear recommendations for each classification
- **Auditable** - All analyses saved in workspace for review

## Validator Skill - Quality Assurance for Triage

The **validator skill** provides a second layer of quality assurance for triage analyses. It independently reviews completed triages to ensure accuracy and completeness.

### What It Does

The validator skill:
- **Reviews triage analyses** - Checks TRIAGE.md files for quality and accuracy
- **Validates classifications** - Ensures the conclusion matches the evidence
- **Verifies evidence** - Cross-checks citations against actual log files
- **Assesses confidence levels** - Confirms confidence scores are appropriate
- **Checks completeness** - Identifies gaps in analysis or overlooked evidence
- **Triggers re-triage** - Invokes the triager skill for fresh analysis when validation fails

### When to Use

Use the validator skill when:
- A triage has been completed and you want quality review
- You're uncertain about a triage decision and want a second opinion
- You want to validate a release-blocker triage (extra scrutiny)
- Someone explicitly requests validation

**Usage examples:**
```
You: Validate the triage for issue #157108

You: Review the TRIAGE.md for issue #157102 - is it accurate?

You: I'm not confident about this triage. Can you validate it?

You: This is a release-blocker. Please validate the triage analysis.
```

### How It Works

1. **Independent review** - Validator reads the TRIAGE.md and forms its own opinion
2. **Evidence verification** - Cross-checks claims against actual log files
3. **Quality assessment** - Checks for common errors and missing analysis
4. **Validation decision** - APPROVED, NEEDS_REVIEW, or REJECTED
5. **Re-triage if needed** - Automatically invokes triager skill for fresh analysis if validation fails
6. **Documentation** - Saves validation report to VALIDATION.md

### Validation Criteria

The validator checks:
- ✓ Classification matches the evidence
- ✓ System logs examined (for infrastructure claims)
- ✓ Source code analyzed (for bug claims)
- ✓ Test code reviewed (for test bug claims)
- ✓ Evidence properly cited with file paths and line numbers
- ✓ Confidence level appropriate for evidence strength
- ✓ Team assignment matches the failure type
- ✓ Reasoning is sound and logical
- ✓ No critical gaps in analysis

**See [.claude/skills/validator/](./. claude/skills/validator/) for detailed validation criteria and workflow.**

### Example Validation Session

```
You: Validate the triage for issue #157108

Claude: [validator skill activates]

        I'll validate the triage analysis. Let me review the TRIAGE.md
        and cross-check against the actual evidence...

        [Reads TRIAGE.md, examines logs, verifies citations]

        Validation Result: APPROVED

        The triage is accurate and thorough:
        ✓ Classification (INFRASTRUCTURE_FLAKE) matches evidence
        ✓ OOM kill clearly documented with timestamps
        ✓ System logs properly examined
        ✓ Confidence level (0.95) appropriate
        ✓ Team assignment correct

        Minor observation: Could have checked Prometheus metrics,
        but not material to conclusion.

        Recommendation: Approve this triage and close issue as flake.
```

### Re-Triage on Validation Failure

If validation finds critical issues, the validator automatically triggers a fresh analysis:

```
You: Validate the triage for issue #157102

Claude: [validator skill activates]

        Validation Result: REJECTED

        Critical issues found:
        ✗ Claimed INFRASTRUCTURE_FLAKE but system logs not checked
        ✗ No evidence of OOM or infrastructure issues
        ✗ CRDB logs show replica inconsistency errors (suggests real bug)
        ✗ Confidence (0.95) too high for the evidence

        Triggering re-triage with fresh analysis...

        [Invokes triager skill]

        Re-Triage Result: ACTUAL_BUG
        Confidence: 0.80

        The fresh analysis found evidence of a replication bug that
        was missed in the original triage. This appears to be a real
        issue requiring investigation by the Replication team.
```

### Benefits

- **Catches errors** - Prevents misclassified bugs or incorrect release-blocker decisions
- **Quality assurance** - Ensures triage analyses meet standards
- **Second opinion** - Provides independent verification for complex cases
- **Training feedback** - Identifies common triage mistakes for improvement
- **Automated re-triage** - Automatically triggers fresh analysis when needed

## License

Built for CockroachDB test infrastructure. Adapt freely for your own use cases.
