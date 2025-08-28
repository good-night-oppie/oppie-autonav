# 📚 Oppie AutoNav - Complete Setup Guide

This guide walks you through setting up Oppie AutoNav from scratch to full automation.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Testing](#testing)
5. [First PR with Review](#first-pr-with-review)
6. [Advanced Setup](#advanced-setup)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

### 1. Install Required Tools

#### Claude CLI
```bash
# Install via npm
npm install -g @anthropic-ai/claude-code

# Verify installation
claude --version

# Login (for OAuth)
claude auth login
```

#### Gemini CLI
```bash
# Download from GitHub
git clone https://github.com/google/generative-ai-cli.git
cd generative-ai-cli
# Follow installation instructions

# Verify
gemini --version
```

#### GitHub CLI
```bash
# Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# macOS
brew install gh

# Login
gh auth login
```

#### Other Tools
```bash
# jq (JSON processor)
sudo apt-get install jq  # Ubuntu
brew install jq          # macOS

# ShellCheck (optional but recommended)
sudo apt-get install shellcheck  # Ubuntu
brew install shellcheck          # macOS
```

### 2. Set Up API Keys

#### Gemini API Key
1. Go to https://makersuite.google.com/app/apikey
2. Create a new API key
3. Export it:
```bash
export GEMINI_API_KEY="your-api-key-here"

# Add to ~/.bashrc or ~/.zshrc for persistence
echo 'export GEMINI_API_KEY="your-api-key-here"' >> ~/.bashrc
```

#### GitHub Tokens (for Actions)
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Create tokens with appropriate scopes
3. Note them for later GitHub Actions setup

## Installation

### Step 1: Clone Oppie AutoNav

```bash
cd ~/workspace
git clone https://github.com/yourusername/oppie-autonav.git
cd oppie-autonav
```

### Step 2: Run Installation Script

#### Option A: Project-Specific Installation (Recommended)
```bash
# Navigate to your project
cd /path/to/your/project

# Install bridge in current project
~/workspace/oppie-autonav/scripts/install-bridge.sh --project
```

#### Option B: Global Installation
```bash
# Install globally for all projects
~/workspace/oppie-autonav/scripts/install-bridge.sh --global
```

### Step 3: Verify Installation

```bash
# Run verification script
./scripts/verify-installation.sh

# You should see all green checkmarks
```

### Step 4: Load Helper Aliases

```bash
# For project installation
source .claude-gemini-bridge/aliases.sh

# For global installation
source ~/.claude-gemini-bridge/aliases.sh

# Add to ~/.bashrc for persistence
echo 'source ~/.claude-gemini-bridge/aliases.sh' >> ~/.bashrc
```

## Configuration

### 1. Claude Settings

The installer automatically configures `~/.claude/settings.json`. Verify it contains:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Grep|Glob|Task",
        "hooks": [{
          "type": "command",
          "command": "/path/to/.claude-gemini-bridge/hooks/gemini-bridge.sh"
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "/path/to/.claude-gemini-bridge/hooks/unified-automation.sh"
        }]
      }
    ]
  }
}
```

### 2. GitHub Actions Setup

#### Copy Workflow to Your Project
```bash
# In your project directory
mkdir -p .github/workflows
cp ~/workspace/oppie-autonav/.github/workflows/claude-pr-review.yml .github/workflows/
```

#### Set GitHub Secrets
```bash
# Using GitHub CLI
gh secret set CLAUDE_CODE_OAUTH_TOKEN --body "your-token"
gh secret set CLAUDE_ACCESS_TOKEN --body "your-token"  # Optional
gh secret set CLAUDE_REFRESH_TOKEN --body "your-token"  # Optional

# Or via GitHub UI:
# Go to Settings → Secrets → Actions → New repository secret
```

### 3. Delegation Thresholds (Optional)

Edit `hooks/config/debug.conf`:

```bash
# Customize delegation thresholds
MIN_FILES_FOR_GEMINI=3          # Delegate Task with ≥3 files
MIN_FILE_SIZE_FOR_GEMINI=5120   # Minimum 5KB size
MAX_TOTAL_SIZE_FOR_GEMINI=10485760  # Maximum 10MB

# Debug settings
DEBUG_LEVEL=2  # 0=off, 1=basic, 2=verbose, 3=trace
```

## Testing

### 1. Test Gemini Connection

```bash
echo "Hello" | gemini -p "Say hi back"
# Should respond with a greeting
```

### 2. Test Hook Execution

```bash
# Test Gemini delegation
echo '{"tool_name":"Read","tool_input":{"file_path":"large_file.txt"}}' | \
  .claude-gemini-bridge/hooks/gemini-bridge.sh

# Test PR monitoring
echo "git push origin main" | \
  .claude-gemini-bridge/hooks/unified-automation.sh
```

### 3. Test Claude Integration

```bash
# In Claude Code
claude "Read this file: @README.md"
# Should delegate to Gemini if file is large
```

## First PR with Review

### Step 1: Create Feature Branch

```bash
git checkout -b feature/test-autonav
```

### Step 2: Make Changes

```bash
echo "# Test Feature" > test-feature.md
git add test-feature.md
```

### Step 3: Commit with Complexity

```bash
git commit -m "feat: Add test feature for AutoNav

This tests the automated PR review system.

Complexity: 7/10
Domain: documentation"
```

### Step 4: Push and Create PR

```bash
# Push branch
git push origin feature/test-autonav

# Create PR
gh pr create \
  --title "Test AutoNav PR Review" \
  --body "Testing automated review

Complexity: 7/10
Domain: documentation

This PR tests:
- Automated review triggering
- Complexity-based personas
- Debate protocol"
```

### Step 5: Request Claude Review

```bash
# The system automatically monitors high-complexity PRs
# Or manually request review:
gh pr comment --body "@claude please review this PR"
```

### Step 6: Monitor the Review

```bash
# Check monitoring status
autonav-pr-status

# View PR logs
autonav-pr-logs

# The system will:
# 1. Post specialized review request
# 2. Monitor Claude's response
# 3. Handle multi-round debates
# 4. Collect evidence if needed
```

## Advanced Setup

### 1. Install OTW Commands

For Research-TDD workflows:

```bash
# Link OTW commands
ln -s ~/workspace/oppie-autonav/.claude/commands/otw ~/.claude/commands/otw

# Test command availability
ls ~/.claude/commands/otw/
```

### 2. Configure Self-Hosted Runner

If using self-hosted GitHub runners:

```bash
# Install runner
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz

# Configure
./config.sh --url https://github.com/yourusername/yourrepo \
  --token YOUR_RUNNER_TOKEN \
  --labels ai-dev-runner-1

# Run
./run.sh
```

Update workflow to use self-hosted runner:
```yaml
runs-on: [self-hosted, ai-dev-runner-1]
```

### 3. Custom Reviewer Personas

Edit `hooks/pr-review/pr-monitor.sh`:

```bash
# Add custom domain personas
case $domain in
    "frontend")
        REVIEWER_ROLE="Frontend Expert"
        FOCUS_AREAS="React, performance, accessibility"
        ;;
    "database")
        REVIEWER_ROLE="Database Architect"
        FOCUS_AREAS="Schema, queries, indexing"
        ;;
esac
```

### 4. Evidence Collectors

Add custom evidence collection in `hooks/lib/evidence-collector.sh`:

```bash
# Custom test runner
collect_custom_tests() {
    npm test -- --coverage > evidence/test-coverage.txt
    pytest --cov=src > evidence/python-coverage.txt
}
```

## Troubleshooting

### Issue: Hooks Not Triggering

**Symptom**: Commands run but automation doesn't start

**Solution**:
```bash
# 1. Restart Claude Code
pkill -f claude
claude

# 2. Verify hooks configuration
cat ~/.claude/settings.json | jq '.hooks'

# 3. Check hook logs
tail -f ~/.claude/logs/hooks.log
```

### Issue: Gemini Not Responding

**Symptom**: Delegation fails or times out

**Solution**:
```bash
# 1. Check API key
echo $GEMINI_API_KEY

# 2. Test connection
echo "test" | gemini -p "respond"

# 3. Check rate limits
# May need to wait if quota exceeded
```

### Issue: PR Review Not Starting

**Symptom**: @claude mention doesn't trigger review

**Solution**:
```bash
# 1. Check GitHub Actions
gh run list --workflow=claude-pr-review.yml

# 2. Verify secrets
gh secret list

# 3. Check workflow logs
gh run view --log
```

### Issue: Evidence Collection Failing

**Symptom**: Debate responses lack evidence

**Solution**:
```bash
# 1. Check test scripts exist
ls test/

# 2. Make scripts executable
chmod +x test/*.sh

# 3. Run tests manually
./test/test-runner.sh
```

## Best Practices

### 1. Always Specify Complexity
```bash
git commit -m "feat: Feature

Complexity: 8/10"
```

### 2. Use Semantic Commits
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation
- `refactor:` Code refactoring
- `test:` Test additions

### 3. Let Debates Complete
Don't interrupt monitoring - let multi-round debates finish

### 4. Monitor Resource Usage
```bash
# Check cache size
autonav-cache-size

# Clear if needed
autonav-cache-clear
```

### 5. Review Logs Regularly
```bash
# Check for errors
autonav-logs | grep ERROR

# Monitor performance
autonav-logs | grep "execution time"
```

## Next Steps

1. **Create Your First Real PR**: Apply the system to actual development
2. **Customize Personas**: Add domain-specific reviewers
3. **Tune Thresholds**: Adjust delegation criteria for your needs
4. **Add Evidence Collectors**: Integrate your test frameworks
5. **Join Community**: Share experiences and get help

## Support

- 📖 [Full Documentation](../README.md)
- 🐛 [Report Issues](https://github.com/yourusername/oppie-autonav/issues)
- 💬 [Discussions](https://github.com/yourusername/oppie-autonav/discussions)
- 📧 Email: support@oppie-autonav.dev

---

**Happy Automating! 🚀**