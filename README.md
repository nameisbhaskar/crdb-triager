# CockroachDB Roachtest Triage Assistant

An AI-powered triage assistant for analyzing CockroachDB roachtest failures. This system combines Claude Code with expert triage knowledge to help you quickly classify test failures and determine root causes.

## What It Does

This tool helps you analyze CockroachDB nightly test failures to determine:
- **Infrastructure flakes** - VM issues, network problems, disk full, OOM kills, etc.
- **Product bugs** - Real regressions or bugs in CockroachDB code that need team assignment

The triager works **interactively** - you drive the conversation, ask questions, and guide the analysis. Claude Code acts as your expert assistant, not a fully automated system.

## How It Works

**Multi-Agent Architecture** The triager uses a sophisticated multi-agent system for comprehensive analysis:

```
User Request: "Triage issue #156490"
         ↓
   [Triager Orchestrator]
         ↓
    Launches 3 parallel agents:
         ├─→ [log-analyzer]     → Analyzes artifacts and logs
         ├─→ [code-analyzer]    → Investigates codebase
         └─→ [issue-correlator] → Finds related issues
                   ↓ ↓ ↓
         [synthesis-triager]    → Makes final classification
                   ↓
         TRIAGE.md + BUG_ANALYSIS.md (if bug)
```

**Each agent is specialized:**
1. **log-analyzer** - Downloads artifacts, reads test.log, system logs, goroutine dumps
2. **code-analyzer** - Examines test source, traces error origins, finds recent changes
3. **issue-correlator** - Searches GitHub for similar failures, identifies patterns
4. **synthesis-triager** - Synthesizes all evidence into final classification

**Benefits:**
- Parallel execution (~8 min total vs ~15 min sequential)
- Specialized expertise in each domain
- Cross-validation of findings
- Comprehensive evidence gathering
- High-confidence classifications

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
```

### Usage

Just start a conversation with Claude Code in the root of this repository
and mention what you want to triage:

```
You: Triage issue #157102

Claude: 🎯 SKILL ACTIVATION CHECK
        📚 RECOMMENDED SKILLS: triager

        I'll help you triage this issue. Let me start by downloading
        the artifacts and analyzing the failure...
```

The triager automatically:
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

**Multi-Agent Components:**

- `.claude/skills/triager/` - Main orchestrator skill
  - `orchestrator.md` - Multi-agent coordination guide
  - `workflow.md`, `patterns.md`, `teams.md` - Domain knowledge
- `.claude/skills/log-analyzer/` - Log/artifact analysis specialist
- `.claude/skills/code-analyzer/` - Codebase investigation specialist
- `.claude/skills/issue-correlator/` - GitHub issue search specialist
- `.claude/skills/synthesis-triager/` - Final classification specialist
- `.claude/hooks/triage-helpers.sh` - Bash utilities for downloading artifacts
- `.claude/hooks/skill-activation-prompt.sh` - Auto-activates skill on triage keywords
- `cockroachdb/` - Source code submodule (auto-checked-out at failure SHA)
- `workspace/issues/*/` - Per-issue workspace for artifacts and analysis

**Analysis Outputs (per issue):**

```
workspace/issues/156490/
├── LOG_ANALYSIS.md       # From log-analyzer agent
├── CODE_ANALYSIS.md      # From code-analyzer agent
├── ISSUE_CORRELATION.md  # From issue-correlator agent
├── TRIAGE.md             # From synthesis-triager (final)
└── BUG_ANALYSIS.md       # From synthesis-triager (if ACTUAL_BUG)
```

**Dependencies:**

- `gh` - GitHub CLI for issue data
- `jq` - JSON parsing in bash scripts
- `gcloud` - IAP token generation for Prometheus access
- `git` - Source code submodule management

## Troubleshooting

**Skill not activating?**
- Use explicit keywords: "triage issue #12345" or "analyze test failure"
- Check [.claude/skills/skill-rules.json](.claude/skills/skill-rules.json) for trigger patterns

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

## Advanced: Customizing the Skill

The skill knowledge lives in [.claude/skills/triager/](.claude/skills/triager/):

- [workflow.md](.claude/skills/triager/workflow.md) - Modify the triage workflow
- [patterns.md](.claude/skills/triager/patterns.md) - Add new flake/bug patterns you discover
- [teams.md](.claude/skills/triager/teams.md) - Update team ownership mappings
- [prometheus.md](.claude/skills/triager/prometheus.md) - Add new metric queries

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
