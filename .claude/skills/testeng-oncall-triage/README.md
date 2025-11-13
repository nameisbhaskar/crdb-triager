# TestEng Oncall Triage Skill

## Overview

The `testeng-oncall-triage` skill automates the batch triage of all T-testeng labeled issues from the cockroachdb/cockroach repository. It's designed to help the TestEng oncall engineer quickly process multiple test failures by automatically running the full triage pipeline for each issue.

## How It Works

This skill:
1. Fetches all open issues with label `T-testeng` from a specified time range
2. For each issue, invokes the `issue-triage` skill which automatically runs:
   - `test-explainer` - Understand what the test does
   - `stack-trace-extractor` - Find where the test failed
   - `infra-flake-detector` - Check if it's an infrastructure flake
3. Aggregates all results into a summary report with classifications

## Usage Examples

### Default (last 2 days)
```
execute testeng oncall triage
```
or
```
triage all testeng issues
```

### Custom time ranges
```
execute testeng oncall triage for last 3 days
```
```
execute testeng oncall triage for last week
```
```
execute testeng oncall triage from last Monday
```
```
execute testeng oncall triage from last Friday
```

### Auto mode (skip confirmation)
```
execute testeng oncall triage auto
```

## What You Get

For each issue triaged, you'll find:
- `workspace/issues/<issue_num>/TEST_EXPLANATION.md` - What the test does
- `workspace/issues/<issue_num>/STACK_TRACE.md` - Where it failed
- `workspace/issues/<issue_num>/INFRA_FLAKE_ANALYSIS.md` - Classification

Plus summary reports at:
- `workspace/oncall-triage-reports/<date>_testeng_oncall_triage.md` - Markdown summary
- `workspace/oncall-triage-reports/<date>_testeng_triage.csv` - **Spreadsheet export (NEW!)**

### Spreadsheet Export (CSV)

The CSV file contains all triage results in a spreadsheet format with columns:

| Column | Description |
|--------|-------------|
| Issue Number | GitHub issue number |
| Issue Title | Full issue title |
| Test Name | Name of the failing test |
| Classification | LIKELY_INFRA_FLAKE / POSSIBLE_INFRA_FLAKE / NOT_INFRA_FLAKE |
| Confidence | HIGH / MEDIUM / LOW |
| Error Pattern | Brief description of the error |
| GitHub URL | Direct link to the issue |
| Similar Issues | List of similar issues with X-infra-flake label |
| GitHub Comment | **Ready-to-paste comment for GitHub** |

**The GitHub Comment column contains the full pre-formatted comment that you can copy and paste directly onto the GitHub issue!**

**To use the CSV:**
1. Open in Google Sheets: File → Import → Upload the CSV file
2. Open in Excel: Double-click the CSV file
3. Filter by Classification to see all infra flakes at once
4. Copy GitHub Comment column cells and paste directly on GitHub issues

## Summary Report Format

The skill generates a comprehensive summary organized by classification:

### Infrastructure Flakes
Issues classified as `LIKELY_INFRA_FLAKE` or `POSSIBLE_INFRA_FLAKE`
- Shows matching issues with X-infra-flake label
- Provides confidence levels
- Recommends labeling or further investigation

### Product Bugs
Issues classified as `NOT_INFRA_FLAKE`
- Shows failure location (file:line)
- Identifies potential owning team
- Recommends assignment

### Unable to Classify
Issues that couldn't be triaged (missing artifacts, etc.)
- Explains why triage failed
- Suggests next steps

## Time Estimates

The skill processes issues sequentially to maintain system stability:
- ~2-3 minutes per issue (including all three sub-skills)
- For 10 issues: ~20-30 minutes
- For 5 issues: ~10-15 minutes

The skill will show you a count before starting and optionally ask for confirmation.

## Requirements

- GitHub CLI (`gh`) authenticated, or the skill will fall back to curl
- Internet connection to fetch issues and download artifacts
- Sufficient disk space for artifacts (each issue ~10-100MB depending on test)

## Tips

1. **Run during low-activity hours** - Batch triage can take time for many issues
2. **Use auto mode for scheduled runs** - Skip confirmation with "auto" flag
3. **Check workspace after** - All detailed analyses are saved for review
4. **Filter by time** - Use specific time ranges to focus on new issues only

## Troubleshooting

### "No issues found"
- Check if T-testeng label is correct in the repo
- Verify the time range covers when issues were created
- Try widening the time range

### "gh auth failed"
- The skill will automatically fall back to curl (unauthenticated)
- Rate limits may apply with curl

### "Artifacts unavailable"
- Some issues may not have artifacts available yet
- These will be noted in the summary report

## Related Skills

- `issue-triage` - Triage a single issue
- `test-explainer` - Understand what a test does
- `stack-trace-extractor` - Extract stack traces from logs
- `infra-flake-detector` - Check for infrastructure flakes

## Integration

This skill is meant to be run by the TestEng oncall engineer as part of their daily/weekly routine:

**Daily oncall workflow:**
```bash
# Morning: Check yesterday's failures
execute testeng oncall triage

# Review summary report
# Label infra flakes
# Route product bugs to teams
```

**Weekly oncall handoff:**
```bash
# Check all issues from the past week
execute testeng oncall triage for last week

# Generate handoff report for next oncall
```

## Customization

To modify default behavior:
- Edit `.claude/skills/testeng-oncall-triage/SKILL.md`
- Change default time range (currently 2 days)
- Adjust batch size limit (currently 100 issues)
- Customize summary report format

## Version

Current version: 1.0.0

## Author

Bhaskar Bora
