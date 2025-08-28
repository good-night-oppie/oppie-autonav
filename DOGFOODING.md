# 🐕 Dogfooding Setup for Oppie AutoNav

This document verifies that oppie-autonav is properly configured to review its own PRs.

## Configuration Status

✅ **Repository Setup**
- Git repository initialized
- GitHub repository created: `good-night-oppie/oppie-autonav`
- Main branch pushed

✅ **Local Installation**
- Oppie AutoNav installed for itself in `.claude-gemini-bridge/`
- Hooks configured in Claude settings
- PR monitoring enabled

✅ **GitHub Actions**
- Claude PR review workflow configured (`.github/workflows/claude-pr-review.yml`)
- Auto-review on PR creation
- Interactive review on @claude mention

## Required GitHub Secrets

For full automation, set these secrets in the repository:

```bash
# Required for Claude Code Max plan
gh secret set CLAUDE_CODE_OAUTH_TOKEN --body "your-token"

# Optional for OAuth flow
gh secret set CLAUDE_ACCESS_TOKEN --body "your-token"
gh secret set CLAUDE_REFRESH_TOKEN --body "your-token"
gh secret set SECRETS_ADMIN_PAT --body "your-pat"
```

## Testing the Setup

1. **Create a test PR:**
```bash
git checkout -b test/feature
echo "test" > test.txt
git add test.txt
git commit -m "test: Verify dogfooding

Complexity: 7/10"
git push origin test/feature
gh pr create
```

2. **Request Claude review:**
```bash
gh pr comment --body "@claude please review this PR"
```

3. **Monitor the review:**
```bash
# Check PR monitoring status
.claude-gemini-bridge/hooks/pr-review/pr-monitor.sh status

# View logs
tail -f .claude-gemini-bridge/logs/pr-monitor.log
```

## Local Hooks Active

The following hooks are active for this repository:

1. **Gemini Delegation** - Large file operations delegate to Gemini
2. **PR Monitoring** - Automatic monitoring on git push and PR creation
3. **CI Status Tracking** - Monitor and attempt to fix CI failures
4. **Debate Protocol** - Multi-round evidence-based discussions

## Benefits of Dogfooding

- Every PR to oppie-autonav gets thoroughly reviewed
- We test our own automation continuously
- Issues are caught before users encounter them
- The system improves itself through its own reviews

---

**Note:** This is a test file to verify dogfooding is working. Claude should review this PR with complexity 7/10 depth.