# Claude Self-Hosted Runner Setup Guide

This guide explains how to set up and use the Claude Code self-hosted runner for automated PR reviews.

## Overview

The `claude-self-hosted.yml` workflow enables automated code reviews using Claude on self-hosted runners with pre-configured credentials.

## Prerequisites

### 1. Self-Hosted Runner Setup

Your self-hosted runner must:
- Be registered with the GitHub organization/repository
- Have the following labels: `self-hosted`, `linux`, `claude-runner`
- Have Claude credentials configured at `/root/.claude/.credentials.json` or `~/.claude/credentials.json`

### 2. Organization Secrets

The following secrets must be configured at the organization or repository level:

| Secret Name | Description | Source |
|------------|-------------|--------|
| `CLAUDE_ACCESS_TOKEN` | OAuth access token | From `.credentials.json` → `claudeAiOauth.accessToken` |
| `CLAUDE_REFRESH_TOKEN` | OAuth refresh token | From `.credentials.json` → `claudeAiOauth.refreshToken` |
| `CLAUDE_TOKEN_EXPIRY` | Token expiration timestamp | From `.credentials.json` → `claudeAiOauth.expiresAt` |
| `CLAUDE_CODE_OAUTH_TOKEN` | Alias for access token | Same as `CLAUDE_ACCESS_TOKEN` |

## Credentials Format

The `.credentials.json` file should have this structure:

```json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-...",
    "refreshToken": "sk-ant-ort01-...",
    "expiresAt": 1787465280011,
    "scopes": [
      "user:inference",
      "user:profile"
    ]
  }
}
```

## Workflow Features

### 1. Interactive Reviews
Triggered when someone mentions `@claude` in:
- PR comments
- PR review comments
- PR review submissions

### 2. Automatic Reviews
Triggered automatically when:
- A new PR is opened
- A PR is synchronized (new commits pushed)

### 3. Manual Triggering
Can be manually triggered via GitHub Actions UI with:
- `pr_number`: Specific PR to review (optional)
- `review_type`: `quick`, `standard`, or `thorough`

## Review Types

### Quick Review (Complexity 1-3)
- Basic bug checking
- Critical path review
- Major issues only

### Standard Review (Complexity 4-7)
- Code correctness and quality
- Error handling validation
- Test coverage review
- Documentation check
- Security issue identification

### Thorough Review (Complexity 8-10)
- Deep architectural analysis
- Security implications
- Performance validation
- Comprehensive test coverage
- Alternative implementations
- Technical debt assessment

## Usage Examples

### 1. Request Interactive Review
Comment on any PR:
```
@claude please review this PR focusing on security
```

### 2. Trigger Manual Review
Go to Actions → claude-self-hosted.yml → Run workflow:
- Enter PR number (optional)
- Select review type
- Click "Run workflow"

### 3. Automatic Review
Simply open or update a PR - Claude will automatically review based on complexity.

## Verification

### Check Secrets Configuration
```bash
./scripts/verify-claude-secrets.sh
```

### Check Runner Status
```bash
# List self-hosted runners
gh api /repos/OWNER/REPO/actions/runners

# Check runner labels
gh api /repos/OWNER/REPO/actions/runners | jq '.runners[] | select(.labels[].name | contains("claude-runner"))'
```

### Test Workflow
```bash
# Create a test PR
git checkout -b test/claude-review
echo "test" > test.txt
git add test.txt
git commit -m "test: Claude review"
git push origin test/claude-review

# Open PR and comment
gh pr create --title "Test Claude Review" --body "Testing @claude review"
```

## Troubleshooting

### Issue: Workflow not triggering
- Verify runner is online and has correct labels
- Check workflow permissions in repository settings
- Ensure secrets are properly configured

### Issue: Authentication fails
- Verify credentials are not expired
- Check secret values match credentials file
- Ensure runner has access to credentials file

### Issue: Review not posting
- Check PR permissions for GitHub App/Action
- Verify `pull-requests: write` permission in workflow
- Check Action logs for errors

## Security Considerations

1. **Credentials Storage**: Store credentials securely with proper file permissions (600)
2. **Secret Rotation**: Regularly update OAuth tokens before expiration
3. **Access Control**: Limit self-hosted runner access to authorized personnel
4. **Audit Logging**: Monitor workflow runs and review activities

## Maintenance

### Update Credentials
```bash
# On self-hosted runner
claude auth  # Re-authenticate
./scripts/setup-claude-secrets.sh  # Update GitHub secrets
```

### Monitor Token Expiry
```bash
# Check token expiry
jq '.claudeAiOauth.expiresAt' ~/.claude/credentials.json

# Convert to human-readable date
date -d @$(jq '.claudeAiOauth.expiresAt' ~/.claude/credentials.json | cut -c1-10)
```

### Update Workflow
The workflow file is located at `.github/workflows/claude-self-hosted.yml`. 
Modify and commit changes to update the review behavior.