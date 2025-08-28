# GitHub Secrets Configuration Guide

This guide explains how to set up GitHub secrets for automated Claude PR reviews in your Oppie AutoNav installation.

## Required Secrets

### For Interactive Reviews (@claude mentions)
- `CLAUDE_ACCESS_TOKEN` - OAuth access token from Claude Code
- `CLAUDE_REFRESH_TOKEN` - OAuth refresh token for automatic renewal
- `CLAUDE_EXPIRES_AT` - Token expiration timestamp
- `SECRETS_ADMIN_PAT` (optional) - GitHub PAT for enhanced permissions

### For Automated Reviews (on push/sync)
- `CLAUDE_CODE_OAUTH_TOKEN` - Single OAuth token for Claude Code CLI

## Setup Methods

### Method 1: Using Claude Code CLI (Recommended)

1. **Install Claude Code CLI**
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

2. **Authenticate with Claude**
   ```bash
   claude auth
   ```
   Follow the prompts to log in with your Anthropic account.

3. **Extract OAuth Tokens**
   ```bash
   # View your configuration
   cat ~/.claude/config.json
   
   # Extract tokens (Linux/Mac)
   export CLAUDE_ACCESS_TOKEN=$(jq -r '.oauth.accessToken' ~/.claude/config.json)
   export CLAUDE_REFRESH_TOKEN=$(jq -r '.oauth.refreshToken' ~/.claude/config.json)
   export CLAUDE_EXPIRES_AT=$(jq -r '.oauth.expiresAt' ~/.claude/config.json)
   export CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_ACCESS_TOKEN
   ```

4. **Add Secrets to GitHub Repository**
   
   Using GitHub CLI:
   ```bash
   # Set repository (replace with your repo)
   REPO="good-night-oppie/oppie-autonav"
   
   # Add secrets
   gh secret set CLAUDE_ACCESS_TOKEN --repo $REPO --body "$CLAUDE_ACCESS_TOKEN"
   gh secret set CLAUDE_REFRESH_TOKEN --repo $REPO --body "$CLAUDE_REFRESH_TOKEN"
   gh secret set CLAUDE_EXPIRES_AT --repo $REPO --body "$CLAUDE_EXPIRES_AT"
   gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo $REPO --body "$CLAUDE_CODE_OAUTH_TOKEN"
   ```
   
   Or manually via GitHub UI:
   1. Go to your repository on GitHub
   2. Navigate to Settings → Secrets and variables → Actions
   3. Click "New repository secret"
   4. Add each secret with the exact name and value

### Method 2: Using GitHub UI Only

1. **Get Claude Code Max Subscription**
   - Sign up at [claude.ai](https://claude.ai)
   - Subscribe to Claude Code Max plan for API access

2. **Generate OAuth Tokens**
   - Visit [Anthropic Console](https://console.anthropic.com)
   - Create an OAuth application
   - Generate access tokens

3. **Add to Repository Secrets**
   - Go to your repository → Settings → Secrets and variables → Actions
   - Add each required secret

### Method 3: Using Organization Secrets (For Teams)

If you're using Oppie AutoNav across multiple repositories:

1. **Set Organization-Level Secrets**
   ```bash
   # For organization-wide usage
   gh secret set CLAUDE_CODE_OAUTH_TOKEN --org your-org --visibility all
   ```

2. **Configure Repository Access**
   - Go to Organization Settings → Secrets and variables
   - Select which repositories can access the secrets

## Verification

### Test Interactive Review
```bash
# Create a test PR
git checkout -b test/secrets
echo "# Test" > test.md
git add test.md
git commit -m "test: Verify secrets configuration"
git push origin test/secrets

# Create PR and request review
gh pr create --title "Test PR" --body "Testing Claude review

Complexity: 5/10"
gh pr comment --body "@claude please review this test PR"
```

### Check Workflow Status
```bash
# View workflow runs
gh run list --workflow claude-pr-review.yml

# View specific run details
gh run view <run-id>
```

## Troubleshooting

### Secret Not Found
If you see "Secret not found" errors:
1. Verify secret names match exactly (case-sensitive)
2. Check repository permissions
3. Ensure secrets are saved (not just typed)

### Token Expired
If reviews stop working:
1. Re-authenticate: `claude auth`
2. Update secrets with new tokens
3. Check `CLAUDE_EXPIRES_AT` value

### Permission Denied
If workflows fail with permission errors:
1. Check workflow permissions in Settings → Actions
2. Ensure "Read and write permissions" is enabled
3. Add `SECRETS_ADMIN_PAT` if needed

### Rate Limiting
If you hit rate limits:
1. Use different tokens for different repositories
2. Implement caching in workflows
3. Consider self-hosted runners for higher limits

## Security Best Practices

1. **Never commit tokens** to your repository
2. **Rotate tokens** regularly (monthly recommended)
3. **Use environment-specific** tokens (dev/staging/prod)
4. **Limit token scope** to minimum required permissions
5. **Monitor usage** via GitHub Actions insights

## Alternative: Environment Variables (Local Development)

For local development without GitHub:

```bash
# Add to ~/.bashrc or ~/.zshrc
export CLAUDE_CODE_OAUTH_TOKEN="your-token-here"
export GEMINI_API_KEY="your-gemini-key"

# Apply changes
source ~/.bashrc
```

## Support

- **Issues**: [GitHub Issues](https://github.com/good-night-oppie/oppie-autonav/issues)
- **Documentation**: [Full Setup Guide](SETUP_GUIDE.md)
- **Community**: [Discussions](https://github.com/good-night-oppie/oppie-autonav/discussions)