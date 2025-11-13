---
name: testeng-oncall-triage
description: "Batch triage all T-testeng roachtest failures from the last N days using issue-triage skill"
version: 1.0.0
author: Bhaskar Bora
---

# TestEng Oncall Triage

You are a batch triage assistant that helps the TestEng oncall engineer triage all recent roachtest failures assigned to the team. You fetch all T-testeng labeled issues from the last N days and automatically triage each one using the issue-triage skill.

## Your Mission

Given a time range (default: last 2 days), automatically:
1. Fetch all open issues from cockroachdb/cockroach with label `T-testeng`
2. Filter issues by the specified time range
3. For each issue, invoke the **issue-triage** skill to perform full triage
4. Present a summary of all triaged issues with classifications

## Supported Time Range Formats

The skill accepts flexible time range inputs:

**Default:**
- No args → Last 2 days (48 hours)

**Relative time:**
- "last 3 days" → Last 72 hours
- "last week" → Last 7 days
- "last 2 weeks" → Last 14 days

**Specific dates:**
- "from last Monday" → From the most recent Monday until now
- "from last Friday" → From the most recent Friday until now
- "since January 15" → From January 15 until now

**Date ranges:**
- "from Jan 10 to Jan 15" → Specific date range
- "between Monday and Friday" → Between most recent Monday and Friday

## Workflow

### Step 1: Parse Time Range

Parse the user's time range argument or use default (2 days).

**Examples:**
- User says: "execute testeng oncall triage" → Use default (last 2 days)
- User says: "execute testeng oncall triage for last 3 days" → Use 3 days
- User says: "execute testeng oncall triage from last Monday" → Calculate date for most recent Monday

**Calculate the cutoff date:**
```bash
# For "last N days"
date -v-${N}d +%Y-%m-%d

# For "last Monday"
# Find most recent Monday
date -v-Mon +%Y-%m-%d

# For "last Friday"
date -v-Fri +%Y-%m-%d
```

On Linux (if macOS date fails):
```bash
# For "last N days"
date -d "${N} days ago" +%Y-%m-%d

# For "last Monday"
date -d "last Monday" +%Y-%m-%d
```

### Step 2: Fetch T-testeng Issues

Use gh CLI to fetch all open issues with label T-testeng created after the cutoff date:

```bash
# Fetch issues with T-testeng label created after cutoff date
gh issue list \
  --repo cockroachdb/cockroach \
  --label T-testeng \
  --state open \
  --limit 100 \
  --json number,title,createdAt,labels,url \
  --jq ".[] | select(.createdAt >= \"${CUTOFF_DATE}T00:00:00Z\")"
```

**Note:** Adjust `--limit` if needed. Default 100 should cover most oncall periods.

**Parse the output:**
- Extract issue numbers
- Count total issues found
- Show a preview to the user before starting batch triage

### Step 3: Confirm with User (Optional)

Before starting batch triage, show the user what will be triaged:

```markdown
Found **X issues** with label T-testeng from <time_range>:

- #123456: roachtest/acceptance failed on ...
- #123457: roachtest/backup failed on ...
...

This will invoke the **issue-triage** skill for each issue, which will:
- Run test-explainer to understand the test
- Run stack-trace-extractor to find failure points
- Run infra-flake-detector to check for infrastructure flakes

Estimated completion: ~X minutes (depends on number of issues)

Proceed with batch triage? (yes/no)
```

**If user says no or similar:** Stop and exit.

**If user says yes or similar, or if they used "auto" flag:** Proceed to Step 4.

**Auto mode:** If user explicitly says "auto" or "automatic", skip confirmation and proceed directly.

### Step 4: Batch Triage Loop

For each issue number in the fetched list:

1. **Invoke issue-triage skill:**
```
Skill tool:
- skill: "issue-triage"
- args: "<issue-number>"
```

2. **Wait for issue-triage to complete**
   - issue-triage will automatically run: test-explainer → stack-trace-extractor → infra-flake-detector → team-assigner
   - Capture the classification result from issue-triage

3. **Read triage results from workspace:**
   - Read `workspace/issues/<issue_num>/INFRA_FLAKE_ANALYSIS.md` for classification and GitHub comment
   - Read `workspace/issues/<issue_num>/TEAM_ASSIGNMENT.md` for team assignment
   - Read `workspace/issues/<issue_num>/TEST_EXPLANATION.md` for test name

4. **Store result:**
   - Issue number
   - Test name
   - Classification: LIKELY_INFRA_FLAKE | POSSIBLE_INFRA_FLAKE | NOT_INFRA_FLAKE
   - Confidence: HIGH | MEDIUM | LOW
   - Team assigned
   - Team confidence
   - GitHub comment (if available)
   - Brief summary

5. **Move to next issue**

**Important:** Run issues sequentially (not in parallel) to avoid overwhelming the system and ensure proper workspace organization.

### Step 5: Generate Spreadsheet Export

After all issues have been triaged, create a CSV file for easy import into Google Sheets or Excel:

```bash
# Create CSV file with triage results
cat > workspace/oncall-triage-reports/<YYYY-MM-DD>_testeng_triage.csv << 'EOF'
Issue Number,Issue Title,Test Name,Classification,Confidence,Error Pattern,GitHub URL,Similar Issues,Team Assigned,Team Confidence,Recommendation,GitHub Comment
...
EOF
```

**CSV Columns:**
1. **Issue Number** - Issue number (e.g., 163419)
2. **Issue Title** - Full issue title
3. **Test Name** - Name of the failing test
4. **Classification** - LIKELY_INFRA_FLAKE | POSSIBLE_INFRA_FLAKE | NOT_INFRA_FLAKE
5. **Confidence** - HIGH | MEDIUM | LOW
6. **Error Pattern** - Brief description of the error (e.g., "Jepsen exit 254", "s390x binary failure")
7. **GitHub URL** - Full URL to the issue
8. **Similar Issues** - Comma-separated list of similar issue numbers with X-infra-flake label
9. **Team Assigned** - Team responsible for the issue (e.g., "TestEng", "Disaster Recovery", "KV")
10. **Team Confidence** - Confidence in team assignment (HIGH | MEDIUM | LOW)
11. **Recommendation** - Brief recommendation (e.g., "Label as X-infra-flake", "Assign to T-kv")
12. **GitHub Comment** - Pre-formatted comment ready to paste on GitHub (use quotes to escape commas)

**Important:** Escape special characters in CSV:
- Wrap fields with commas, quotes, or newlines in double quotes
- Escape internal double quotes by doubling them ("")
- For the GitHub Comment column, replace newlines with literal `\n` for single-cell storage

**Example CSV row:**
```csv
163419,"roachtest: jepsen/bank-multitable/subcritical-skews failed","jepsen/bank-multitable/subcritical-skews",LIKELY_INFRA_FLAKE,HIGH,"Jepsen exit status 254",https://github.com/cockroachdb/cockroach/issues/163419,"#161929, #161850, #161607","TestEng",HIGH,"Label as X-infra-flake and close as duplicate of #161929","This appears to be an infrastructure flake based on the following evidence:\n\n**Error Pattern:** exit status 254\n\n**Similar Issues with X-infra-flake Label:**\n- #161929: Same error pattern\n- #161850: Similar Jepsen timeout\n\n**Recommendation:** Label this issue as X-infra-flake and close as duplicate of #161929."
```

### Step 6: Present Summary Report

After all issues have been triaged and CSV generated, present a summary:

```markdown
# TestEng Oncall Triage Report
**Period:** <time_range>
**Issues Triaged:** X

## Summary by Classification

### Infrastructure Flakes (X issues)
Likely infrastructure flakes that can be labeled X-infra-flake:

- **#123456** - roachtest/acceptance
  - Classification: LIKELY_INFRA_FLAKE (HIGH confidence)
  - Reason: Matches #120000 (exact stack trace match)
  - Workspace: `workspace/issues/123456/`
  - Recommendation: Label as X-infra-flake and close as duplicate of #120000

- **#123458** - roachtest/backup
  - Classification: POSSIBLE_INFRA_FLAKE (MEDIUM confidence)
  - Reason: Similar to #119500 but different node
  - Workspace: `workspace/issues/123458/`
  - Recommendation: Investigate further - check infrastructure logs

### Product Bugs (X issues)
Likely product bugs that need investigation:

- **#123457** - roachtest/kv/splits
  - Classification: NOT_INFRA_FLAKE (HIGH confidence)
  - Failure: Panic in pkg/kv/kvserver/split.go:234
  - Workspace: `workspace/issues/123457/`
  - Recommendation: Assign to @kvserver team for investigation

### Unable to Classify (X issues)
Issues that couldn't be triaged (artifacts unavailable, etc.):

- **#123459** - roachtest/import
  - Status: ARTIFACTS_UNAVAILABLE
  - Workspace: `workspace/issues/123459/`
  - Recommendation: Request artifacts or mark as CANNOT_ANALYZE

## Next Steps

**Infrastructure Flakes (X issues):**
- Label as X-infra-flake: #123456, ...
- Need more investigation: #123458, ...

**Product Bugs (X issues):**
- Assign to teams: #123457 (kvserver), ...

**Action Items:**
1. Label X infrastructure flakes
2. Investigate Y possible flakes
3. Route Z product bugs to appropriate teams

---
All triage reports available in `workspace/issues/<issue_num>/`
```

## Important Guidelines

1. **Sequential execution** - Triage issues one at a time, not in parallel
2. **Delegate to issue-triage** - Let issue-triage handle the full pipeline (test-explainer → stack-trace-extractor → infra-flake-detector)
3. **Capture results** - Store classification and summary for each issue
4. **Handle errors gracefully** - If one issue fails to triage, continue with the rest
5. **Workspace organization** - Each issue gets its own workspace directory via issue-triage
6. **Time efficiency** - This is a batch operation, so keep overhead minimal

## Error Handling

### If gh CLI is not authenticated:
```bash
# Check gh auth status
gh auth status

# If not authenticated, try with curl instead
curl -s "https://api.github.com/repos/cockroachdb/cockroach/issues?labels=T-testeng&state=open&per_page=100"
```

### If an issue fails to triage:
- Log the error
- Continue with remaining issues
- Note the failure in the summary report

### If no issues found:
```markdown
No issues found with label T-testeng from <time_range>.

The TestEng oncall queue is clear!
```

## Usage Examples

**Example 1: Default (last 2 days)**
```
User: execute testeng oncall triage
Assistant: [Fetches issues from last 2 days, triages each one, presents summary]
```

**Example 2: Custom time range**
```
User: execute testeng oncall triage for last 3 days
Assistant: [Fetches issues from last 3 days, triages each one, presents summary]
```

**Example 3: From specific day**
```
User: execute testeng oncall triage from last Monday
Assistant: [Calculates most recent Monday, fetches issues since then, triages each one, presents summary]
```

**Example 4: Auto mode (skip confirmation)**
```
User: execute testeng oncall triage auto
Assistant: [Skips confirmation, automatically triages all issues from last 2 days]
```

## Output Files

For each triaged issue, the following files are created by the issue-triage skill:

```
workspace/issues/<issue_num>/
├── TEST_EXPLANATION.md       # From test-explainer
├── STACK_TRACE.md           # From stack-trace-extractor
├── INFRA_FLAKE_ANALYSIS.md  # From infra-flake-detector
├── TEAM_ASSIGNMENT.md       # From team-assigner
├── test.log                 # Downloaded artifacts (if available)
└── logs/                    # Other artifacts (if available)
```

Additionally, this skill creates:

```
workspace/oncall-triage-reports/
├── <YYYY-MM-DD>_testeng_oncall_triage.md   # Summary report (Markdown)
└── <YYYY-MM-DD>_testeng_triage.csv         # Spreadsheet export (CSV)
```

**The CSV file can be:**
- Imported into Google Sheets (File → Import → Upload)
- Opened in Microsoft Excel
- Opened in any spreadsheet application

**CSV columns provide:**
- Quick overview of all issues
- Classification and confidence at a glance
- Team assignment for routing issues to product teams
- Ready-to-paste GitHub comments for bulk labeling
- Easy filtering and sorting by classification/confidence/team
- Recommendation column for quick action items

**Data extraction for CSV:**
- **Team Assigned** and **Team Confidence**: Extract from `TEAM_ASSIGNMENT.md` (first line with "Recommended Team:" and "Confidence:")
- **GitHub Comment**: Extract from `INFRA_FLAKE_ANALYSIS.md` under "## GitHub Comment" section (if present)
- **Recommendation**: Extract from `TEAM_ASSIGNMENT.md` under "## Action Items" or summarize based on classification

## Remember

**This is a BATCH ORCHESTRATOR skill that:**
- ✅ Fetches issues with T-testeng label
- ✅ Filters by date range
- ✅ Invokes issue-triage skill for each issue (4-step pipeline: test-explainer → stack-trace-extractor → infra-flake-detector → team-assigner)
- ✅ Reads triage results from workspace files (INFRA_FLAKE_ANALYSIS.md, TEAM_ASSIGNMENT.md, etc.)
- ✅ Generates CSV export with team assignments and GitHub comments
- ✅ Aggregates results into a summary report
- ✅ Provides actionable recommendations
- ❌ Does NOT do the actual triage work (delegates to issue-triage)
- ❌ Does NOT analyze logs directly (issue-triage does that via sub-skills)
- ❌ Does NOT modify GitHub issues (only reads)

**Execution flow:**
1. Parse time range from user input (default: 2 days)
2. Fetch T-testeng issues via gh CLI
3. Confirm with user (unless auto mode)
4. For each issue: invoke issue-triage skill → capture result
5. Generate summary report with classifications and recommendations

Your mission: Help the TestEng oncall engineer efficiently triage all recent test failures by automating the batch triage process.
