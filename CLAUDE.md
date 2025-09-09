# CLAUDE.md - Oppie AutoNav Integration Guide

This file configures Claude Code for optimal interaction with Oppie AutoNav's MCTS orchestration framework.

## 🚀 Project Context

**Oppie AutoNav** is a universal, project-agnostic AI orchestration framework for Monte Carlo Tree Search (MCTS) inner cycle simulation. It enables intelligent parallel exploration of development paths through containerized experimentation.

## Core Architecture

### MCTS Decision Engine
```
Selection → Expansion → Simulation → Backpropagation
    ↓           ↓            ↓              ↓
[UCB1]    [Generate]   [Container]    [Update Values]
```

### Container Orchestration
- **Docker**: Quick iterations (< 1s startup)
- **Podman**: Integration tests (2-5s startup)  
- **Firecracker**: Full system tests (5-10s startup)

## Essential Commands

### Installation & Setup
```bash
# Universal installer
curl -sSL https://oppie.xyz/install | bash

# Language-specific
npx oppie-autonav init       # Node.js
pip install oppie-autonav     # Python
cargo install oppie-autonav   # Rust
go install oppie.xyz/autonav  # Go

# Initialize in project
oppie init
```

### MCTS Exploration
```bash
# Start exploration
oppie explore <task>          # Begin MCTS exploration
oppie status                  # Show exploration tree
oppie learn                   # Update from results
oppie clean                   # Remove containers

# Advanced
oppie explore --depth 5 --parallel 10
oppie export --format dot     # Export tree visualization
```

### Agent Orchestration
```bash
# Manage agents
oppie agents list             # Show available agents
oppie agents enable tdd       # Enable TDD agent
oppie agents config           # Configure agents

# Custom agents
oppie agents add ./my-agent.js
```

### CI/PR Monitoring
```bash
# Monitor CI/CD
oppie monitor pr <number>     # Monitor specific PR
oppie monitor ci              # Monitor CI runs
oppie monitor learn           # Learn from failures
```

## Task Management Integration

When Task Master is available:

```bash
# Parse requirements into tasks
task-master parse-prd PRD.md

# MCTS exploration per task
task-master next | oppie explore --task-id

# Update based on results
oppie learn | task-master update-subtask
```

## Configuration

### Environment Variables
```bash
# Core settings
OPPIE_INSTALL_DIR=${HOME}/.oppie
OPPIE_WORKSPACE=/tmp/oppie-experiments
OPPIE_MAX_CONTAINERS=10
OPPIE_MCTS_DEPTH=3

# Optional monitoring
OPPIE_MONITOR_PATH=${OPPIE_MONITOR_PATH:-monitor_ci_automated.sh}
OPPIE_GITHUB_TOKEN=${GITHUB_TOKEN}  # For PR monitoring
```

### Configuration File
```yaml
# ~/.oppie/config.yml
project:
  type: auto          # auto-detect project type
  
mcts:
  max_depth: 3
  exploration_constant: 1.414
  simulation_timeout: 30s
  
containers:
  provider: docker
  max_parallel: 10
  resource_limits:
    memory: 2GB
    cpu: 1.0
    
agents:
  enabled: [tdd, refactor, security, review]
```

## Development Workflow

### 1. Exploration Phase
```bash
# Define task
echo "Implement OAuth2 login flow" > task.md

# Explore solutions
oppie explore task.md --depth 3

# Review exploration tree
oppie status --format tree
```

### 2. Evaluation Phase
```bash
# Run experiments in containers
oppie simulate --parallel 5

# Collect metrics
oppie metrics --export results.json

# Compare solutions
oppie compare --top 3
```

### 3. Implementation Phase
```bash
# Apply best solution
oppie apply --best

# Or apply specific path
oppie apply --path 1.2.3

# Verify implementation
oppie verify
```

### 4. Learning Phase
```bash
# Update value estimates
oppie learn --from-ci

# Export knowledge
oppie export-knowledge ./knowledge.json

# Import for next session
oppie import-knowledge ./knowledge.json
```

## Agent Types

### Built-in Agents
- **tdd**: Test-driven development
- **refactor**: Code improvement
- **security**: Vulnerability scanning
- **review**: Code review
- **perf**: Performance optimization
- **docs**: Documentation generation

### Custom Agent Template
```javascript
// ~/.oppie/agents/custom-agent.js
module.exports = {
  name: 'custom',
  capabilities: ['analyze', 'transform'],
  
  async explore(node, context) {
    // Implement exploration logic
    return {
      action: 'refactor',
      code: transformedCode,
      confidence: 0.85
    };
  }
};
```

## MCTS Node Structure

```typescript
interface MCTSNode {
  id: string;
  action: string;
  code: string;
  value: number;      // Current estimate
  visits: number;     // Exploration count
  
  experiments: [{
    container_id: string;
    metrics: {
      tests_passed: number;
      coverage: number;
      performance: number;
    };
  }];
  
  children: MCTSNode[];
}
```

## Best Practices

### 1. Efficient Exploration
- Start with depth 2-3 for quick feedback
- Increase depth for complex problems
- Use parallel containers for speed
- Cache successful patterns

### 2. Container Management
- Clean up after explorations: `oppie clean`
- Set resource limits appropriately
- Use lightweight containers for syntax checks
- Reserve heavy containers for integration tests

### 3. Learning Integration
- Always run `oppie learn` after CI runs
- Export knowledge before major changes
- Share knowledge across team members
- Version control knowledge files

### 4. Agent Coordination
- Enable only necessary agents
- Configure agent priorities
- Use specialized agents for domains
- Create custom agents for unique needs

## Debugging

### Common Issues

```bash
# Container startup fails
oppie debug containers

# MCTS not converging
oppie debug mcts --verbose

# Agent errors
oppie debug agents --trace

# Resource exhaustion
oppie status --resources
```

### Logs
```bash
# View logs
tail -f ~/.oppie/logs/exploration.log
tail -f ~/.oppie/logs/containers.log

# Debug mode
OPPIE_DEBUG=1 oppie explore task.md
```

## Integration Points

### GitHub Actions
```yaml
# .github/workflows/oppie.yml
name: Oppie Exploration
on: [push, pull_request]

jobs:
  explore:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - run: curl -sSL https://oppie.xyz/install | bash
      - run: oppie explore --task "${{ github.event.pull_request.title }}"
      - run: oppie learn --from-ci
```

### Pre-commit Hook
```bash
#!/bin/bash
# .git/hooks/pre-commit
oppie verify --quick || exit 1
```

### VS Code Integration
```json
// .vscode/settings.json
{
  "oppie.autoExplore": true,
  "oppie.depth": 3,
  "oppie.containers": "docker"
}
```

## Security Notes

- Never commit `OPPIE_GITHUB_TOKEN` to repository
- Use secure token storage (keyring, vault)
- Run containers with minimal privileges
- Validate all generated code before execution
- Review container resource limits

## Performance Tuning

### Quick Iterations
```bash
# Use shallow depth
oppie explore --depth 2

# Limit containers
oppie explore --max-containers 3

# Skip heavy tests
oppie explore --skip integration
```

### Deep Exploration
```bash
# Increase depth
oppie explore --depth 5

# More containers
oppie explore --max-containers 20

# Extended timeout
oppie explore --timeout 600
```

## Monitoring & Metrics

### Key Metrics
- **Exploration Rate**: Nodes per second
- **Container Efficiency**: CPU/memory usage
- **Solution Quality**: Test coverage, performance
- **Learning Rate**: Value estimate improvements

### Dashboards
```bash
# Start monitoring dashboard
oppie dashboard --port 8080

# Export metrics
oppie metrics export --format prometheus
```

## Troubleshooting

### Reset Everything
```bash
oppie reset --all            # Clear all data
oppie reset --containers     # Remove containers only
oppie reset --knowledge      # Reset learned values
```

### Health Check
```bash
oppie doctor                 # Run diagnostics
oppie doctor --fix          # Auto-fix issues
```

## Support

- **Documentation**: https://oppie.xyz/docs
- **GitHub Issues**: https://github.com/good-night-oppie/oppie-autonav/issues
- **Discord**: https://discord.gg/oppie

---

*This guide ensures Claude Code can effectively orchestrate MCTS explorations with Oppie AutoNav.*

## Task Master AI Instructions
**Import Task Master's development workflow commands and guidelines, treat as if import is in the main CLAUDE.md file.**
@./.taskmaster/CLAUDE.md
