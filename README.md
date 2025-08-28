# 🚀 Oppie AutoNav - Advanced AI Development Automation

> Complete automation suite for Claude Code with PR reviews, debate protocols, CI/CD monitoring, and intelligent task delegation

## 🌟 Features

- **🤖 Automated PR Reviews**: Claude reviews every PR with complexity-based depth
- **💬 Debate Protocol**: Multi-round evidence-based discussions with Claude
- **🔄 CI/CD Monitoring**: Automatic detection and fixing of CI failures  
- **🎯 Task Delegation**: Intelligent routing to Gemini for large-scale operations
- **📊 Research-TDD Workflow**: Automated research → test → implement → review cycle
- **🧠 Sub-agent Orchestration**: Specialized agents for different domains
- **⚡ Performance Optimized**: Sub-second hook execution with caching

## 📋 Prerequisites

Before installation, ensure you have:

```bash
# Required tools
- claude (Claude CLI) - npm install -g @anthropic-ai/claude-code
- gemini (Gemini CLI) - https://github.com/google/generative-ai-cli
- gh (GitHub CLI) - https://cli.github.com/
- jq - JSON processor
- shellcheck - Shell script analyzer

# Optional but recommended
- npm/node - For Claude Code installation
- python3 - For test runners
- git - Version 2.0+
```

## 🛠️ Installation

### Step 1: Clone the Repository

```bash
cd ~/workspace
git clone https://github.com/yourusername/oppie-autonav.git
cd oppie-autonav
```

### Step 2: Configure API Keys

```bash
# Set up Gemini API key
export GEMINI_API_KEY="your-gemini-api-key"

# Set up GitHub token (for PR operations)
gh auth login

# Configure Claude Code (if using OAuth)
claude auth login
```

### Step 3: Install Claude-Gemini Bridge

This enables intelligent delegation of large tasks to Gemini:

```bash
# Option A: Install in current project
./scripts/install-bridge.sh

# Option B: Install globally
./scripts/install-bridge.sh --global
```

### Step 4: Install Advanced Hooks

Configure Claude Code hooks for automation:

```bash
# Install PR monitoring and CI hooks
./scripts/install-hooks.sh

# Verify installation
./scripts/verify-installation.sh
```

### Step 5: Configure GitHub Actions

Set up automated PR reviews in your repository:

```bash
# Copy workflow templates to your project
cp .github/workflows/claude-pr-review.yml /path/to/your/project/.github/workflows/

# Set required secrets in GitHub:
# - CLAUDE_CODE_OAUTH_TOKEN (from Claude Code Max plan)
# - CLAUDE_ACCESS_TOKEN (optional, for OAuth)
# - CLAUDE_REFRESH_TOKEN (optional, for OAuth)
# - SECRETS_ADMIN_PAT (for secret management)
```

### Step 6: Install OTW Commands (Optional)

For advanced Research-TDD workflow:

```bash
# Link OTW commands to Claude
ln -s ~/workspace/oppie-autonav/.claude/commands ~/.claude/commands

# Or copy specific workflows
cp -r .claude/commands/otw /path/to/project/.claude/commands/
```

## 🎯 Quick Start

### Basic PR Review Workflow

```bash
# 1. Create feature branch
git checkout -b feature/awesome-feature

# 2. Make changes and commit with complexity hint
git add .
git commit -m "feat: Add awesome feature

Complexity: 7/10
Domain: backend"

# 3. Push and create PR
git push origin feature/awesome-feature
gh pr create --title "Add awesome feature" --body "Complexity: 7/10"

# 4. Request Claude review (automatic for complexity >= 7)
gh pr comment --body "@claude please review this PR"

# The system will:
# - Post specialized review request
# - Monitor Claude's responses
# - Handle multi-round debates
# - Collect evidence as needed
```

### Research-TDD Workflow

```bash
# 1. Start a complex task
/otw/research-tdd-pr-review task-123 --complexity 9

# Automatically:
# - Conducts research phase
# - Implements with TDD (Red → Green → Refactor)
# - Creates PR with context
# - Initiates Claude review with debate
# - Monitors until approved
```

## 🏗️ Architecture

```
oppie-autonav/
├── .github/workflows/        # GitHub Actions for PR reviews
│   ├── claude-pr-review.yml  # Main review workflow
│   └── claude-debate.yml     # Debate protocol workflow
│
├── .claude/                  # Claude Code configuration
│   ├── commands/otw/         # Advanced workflow commands
│   │   ├── research-tdd-pr-review.md
│   │   └── execute-workflow.sh
│   └── hooks/                # Runtime hooks
│       ├── pr-review-monitor.sh
│       └── unified-automation.sh
│
├── hooks/                    # Core automation scripts
│   ├── pr-review/           # PR monitoring system
│   │   ├── pr-monitor.sh
│   │   └── debate-handler.sh
│   ├── lib/                # Shared libraries
│   │   ├── gemini-wrapper.sh
│   │   └── evidence-collector.sh
│   └── config/             # Configuration files
│       └── complexity.conf
│
├── scripts/                 # Installation and utilities
│   ├── install-bridge.sh
│   ├── install-hooks.sh
│   └── verify-installation.sh
│
└── docs/                   # Documentation
    ├── SETUP.md
    ├── WORKFLOWS.md
    └── TROUBLESHOOTING.md
```

## 🔧 Configuration

### Complexity Levels

Configure review depth based on task complexity:

| Level | Reviewer | Focus | Debate Rounds |
|-------|----------|-------|---------------|
| 1-3 | Basic Reviewer | Syntax, style | 1 |
| 4-6 | Senior Developer | Logic, patterns | 1-2 |
| 7-8 | Principal Engineer | Architecture, trade-offs | 2-3 |
| 9-10 | Chief Architect | Proof, validation | 3-4 |

Edit `hooks/config/complexity.conf` to customize.

### Hook Configuration

Customize automation behavior in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Grep|Glob|Task",
        "hooks": [{
          "type": "command",
          "command": "~/workspace/oppie-autonav/hooks/gemini-bridge.sh"
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "~/workspace/oppie-autonav/hooks/pr-review/pr-monitor.sh detect"
        }]
      }
    ]
  }
}
```

### GitHub Actions Secrets

Required secrets for your repository:

```yaml
CLAUDE_CODE_OAUTH_TOKEN: # From Claude Code Max plan
CLAUDE_ACCESS_TOKEN:     # For OAuth flow (optional)
CLAUDE_REFRESH_TOKEN:    # For token refresh (optional)
SECRETS_ADMIN_PAT:       # GitHub PAT for secret management
```

## 📊 Usage Examples

### Manual PR Monitoring

```bash
# Start monitoring a PR
./hooks/pr-review/pr-monitor.sh monitor 123 8

# Request review with specific complexity
./hooks/pr-review/pr-monitor.sh request 123 9 security

# Check monitoring status
./hooks/pr-review/pr-monitor.sh status

# Stop monitoring
./hooks/pr-review/pr-monitor.sh stop 123
```

### CI/CD Auto-Fix

```bash
# Trigger auto-fix for CI failures
./hooks/ci-monitor.sh autofix 123

# Monitor CI status
./hooks/ci-monitor.sh status
```

### Evidence Collection

During debates, evidence is automatically collected:

```bash
# Manual evidence collection
./hooks/lib/evidence-collector.sh 123 round-2

# Generates:
# - Test results
# - Benchmark data
# - Code coverage
# - Security scan results
```

## 🎨 Customization

### Add Custom Reviewer Personas

Edit `hooks/pr-review/personas.conf`:

```bash
case $domain in
    "security")
        REVIEWER_ROLE="Security Expert"
        FOCUS_AREAS="OWASP, auth, crypto"
        ;;
    "ml")
        REVIEWER_ROLE="ML Engineer"
        FOCUS_AREAS="Models, data, metrics"
        ;;
esac
```

### Custom Evidence Collectors

Add to `hooks/lib/evidence-collector.sh`:

```bash
collect_custom_evidence() {
    # Run your custom validation
    your-tool --validate > evidence/custom.txt
}
```

### Workflow Templates

Create custom workflows in `.claude/commands/`:

```markdown
# /custom/my-workflow
Triggers: specific-condition
Actions: 
1. Research phase
2. Implementation
3. Review with custom persona
```

## 🐛 Troubleshooting

### Hooks Not Triggering

```bash
# Check installation
./scripts/verify-installation.sh

# View hook logs
tail -f ~/.claude/logs/hooks.log

# Test hooks manually
./hooks/pr-review/pr-monitor.sh test
```

### Claude Not Responding

```bash
# Check GitHub Actions
gh run list --workflow=claude-pr-review.yml

# Verify secrets
gh secret list

# Test Claude connection
claude --version
```

### Gemini Delegation Issues

```bash
# Test Gemini connection
echo "test" | gemini -p "respond with ok"

# Check cache
ls -la hooks/cache/gemini/

# View delegation logs
tail -f logs/gemini-bridge.log
```

## 📈 Performance

- **Hook Execution**: <500ms (async)
- **PR Detection**: <1s with caching
- **Evidence Collection**: 5-30s
- **Debate Response**: 10-60s
- **Gemini Delegation**: 2-10s

## 🔒 Security

- No API keys in code or logs
- Secure token storage with encryption
- Input validation and sanitization
- Automatic secret rotation support
- File exclusions for sensitive data

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

MIT License - see [LICENSE](LICENSE)

## 🙏 Acknowledgments

- Claude Code team for the amazing CLI
- Gemini team for the powerful API
- GitHub for Actions and CLI
- oppie-thunder contributors

## 📞 Support

- 📖 [Documentation](docs/)
- 🐛 [Issue Tracker](https://github.com/yourusername/oppie-autonav/issues)
- 💬 [Discussions](https://github.com/yourusername/oppie-autonav/discussions)

---

**Made with ❤️ for the AI development community**

*Automate everything, review everything, ship with confidence!*