# PRD: Oppie AutoNav - Universal MCTS Orchestration Framework

**Version**: 1.0  
**Date**: 2025-09-06  
**Status**: Active  
**Domain**: oppie.xyz

## Executive Summary

Oppie AutoNav is a **universal, project-agnostic AI orchestration framework** designed for Monte Carlo Tree Search (MCTS) inner cycle simulation. It enables coding agents like Claude Code to explore, evaluate, and optimize development paths through intelligent parallel exploration and containerized experimentation.

### Core Value Proposition
- **Universal Installation**: One-command setup that auto-detects project type and configures appropriately
- **MCTS-Driven Development**: Explore multiple solution paths in parallel, learn from outcomes
- **Container-Based Sandboxing**: Safe experimentation without affecting main codebase
- **Agent Orchestration**: Coordinate multiple specialized agents for complex tasks
- **Continuous Learning**: Build knowledge from every execution cycle

## Vision

Transform AI-assisted development from linear execution to intelligent exploration, where every development decision is:
1. **Explored** through multiple parallel paths
2. **Evaluated** in isolated containers
3. **Optimized** based on empirical results
4. **Learned** for future decisions

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                    Oppie AutoNav Core                      │
├──────────────────────────────────────────────────────────┤
│                                                            │
│  ┌────────────────────┐    ┌────────────────────┐       │
│  │  Universal          │    │   MCTS Decision    │       │
│  │  Installer          │───▶│   Engine           │       │
│  └────────────────────┘    └────────────────────┘       │
│           │                          │                    │
│           ▼                          ▼                    │
│  ┌────────────────────┐    ┌────────────────────┐       │
│  │  Project Type      │    │   Node/Container   │       │
│  │  Detection         │    │   Orchestrator     │       │
│  └────────────────────┘    └────────────────────┘       │
│           │                          │                    │
│           ▼                          ▼                    │
│  ┌────────────────────┐    ┌────────────────────┐       │
│  │  Adaptive Config   │    │   Experiment       │       │
│  │  Generator         │    │   Sandboxes        │       │
│  └────────────────────┘    └────────────────────┘       │
│                                                            │
└──────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Universal Installer & Project Detection

**Objective**: Zero-friction installation that works with ANY project type.

#### Installation Methods
```bash
# Universal one-liner
curl -sSL https://oppie.xyz/install | bash

# Language-specific
npx oppie-autonav init      # Node.js projects
pip install oppie-autonav    # Python projects
cargo install oppie-autonav  # Rust projects
go install oppie.xyz/autonav # Go projects
```

#### Auto-Detection Logic
```javascript
detectProjectType() {
  // Detect by manifest files
  if (exists('package.json')) return 'node';
  if (exists('requirements.txt') || exists('pyproject.toml')) return 'python';
  if (exists('go.mod')) return 'go';
  if (exists('Cargo.toml')) return 'rust';
  if (exists('composer.json')) return 'php';
  if (exists('Gemfile')) return 'ruby';
  
  // Detect by file extensions
  const extensions = getFileExtensions();
  return inferFromExtensions(extensions);
}
```

### 2. MCTS Decision Engine

**Objective**: Guide development through intelligent exploration and exploitation.

#### Core MCTS Loop
```yaml
mcts_cycle:
  selection:
    description: Choose most promising node to explore
    algorithm: UCB1 with domain-specific heuristics
    
  expansion:
    description: Generate child nodes for unexplored actions
    methods:
      - Code generation variations
      - Refactoring strategies
      - Test approaches
      
  simulation:
    description: Run experiments in isolated containers
    environment:
      - Docker containers
      - Firecracker microVMs
      - GitHub Codespaces
      
  backpropagation:
    description: Update node values based on results
    metrics:
      - Test pass rate
      - Performance benchmarks
      - Code quality scores
      - Resource usage
```

#### Node Structure
```typescript
interface MCTSNode {
  id: string;
  state: CodeState;
  action: DevelopmentAction;
  value: number;           // Estimated value
  visits: number;          // Exploration count
  children: MCTSNode[];
  parent: MCTSNode | null;
  
  // Experiment results
  experiments: {
    container_id: string;
    outcome: ExperimentResult;
    metrics: PerformanceMetrics;
    artifacts: string[];     // Generated files
  }[];
}
```

### 3. Container-Based Experimentation

**Objective**: Safe, parallel exploration of solution spaces.

#### Container Types
```yaml
experiment_containers:
  lightweight:
    provider: Docker
    use_case: Quick iterations, syntax validation
    startup_time: <1s
    resource_limit: 512MB RAM, 0.5 CPU
    
  standard:
    provider: Podman
    use_case: Integration tests, build verification
    startup_time: 2-5s
    resource_limit: 2GB RAM, 1 CPU
    
  heavy:
    provider: Firecracker
    use_case: Full system tests, performance benchmarks
    startup_time: 5-10s
    resource_limit: 8GB RAM, 2 CPU
```

#### Experiment Workflow
```mermaid
graph LR
    A[MCTS Node] --> B[Spawn Container]
    B --> C[Apply Code Changes]
    C --> D[Run Tests]
    D --> E[Collect Metrics]
    E --> F[Update Node Value]
    F --> G[Destroy Container]
```

### 4. Agent Orchestration

**Objective**: Coordinate specialized agents for complex tasks.

#### Agent Types
```yaml
specialized_agents:
  tdd_agent:
    role: Test-driven development
    capabilities: [write_tests, verify_coverage, suggest_edge_cases]
    
  refactor_agent:
    role: Code improvement
    capabilities: [identify_smells, apply_patterns, optimize_performance]
    
  security_agent:
    role: Security analysis
    capabilities: [scan_vulnerabilities, suggest_fixes, verify_compliance]
    
  review_agent:
    role: Code review
    capabilities: [check_standards, suggest_improvements, validate_logic]
```

#### Orchestration Patterns
```typescript
// Parallel exploration
async function exploreParallel(task: Task) {
  const agents = [tddAgent, refactorAgent, securityAgent];
  const results = await Promise.all(
    agents.map(agent => agent.explore(task))
  );
  return mergeSolutions(results);
}

// Sequential refinement
async function refineSequential(code: Code) {
  let refined = code;
  refined = await tddAgent.addTests(refined);
  refined = await refactorAgent.improve(refined);
  refined = await securityAgent.harden(refined);
  return refined;
}
```

### 5. CI/PR Monitoring Integration

**Objective**: Learn from CI/CD outcomes to improve future decisions.

#### Monitoring Capabilities
- GitHub Actions workflow analysis
- PR review feedback extraction
- Test failure pattern recognition
- Performance regression detection

#### Learning Loop
```yaml
ci_learning_loop:
  monitor:
    - Watch PR creation
    - Track CI pipeline execution
    - Capture review comments
    
  analyze:
    - Extract failure patterns
    - Identify common issues
    - Measure fix effectiveness
    
  update:
    - Adjust MCTS value estimates
    - Update agent strategies
    - Refine exploration policies
```

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- [x] Universal installer with project detection
- [x] Basic MCTS engine implementation
- [ ] Docker container orchestration
- [ ] Simple agent coordination

### Phase 2: Intelligence (Weeks 3-4)
- [ ] MCTS learning and value networks
- [ ] Multi-agent parallel exploration
- [ ] Container resource optimization
- [ ] CI/PR monitoring integration

### Phase 3: Scale (Weeks 5-6)
- [ ] Distributed MCTS across multiple machines
- [ ] Advanced caching and memoization
- [ ] Plugin architecture for custom agents
- [ ] Production deployment tools

## Success Metrics

### Performance Targets
- **Installation Time**: < 30 seconds
- **Project Detection Accuracy**: > 95%
- **Container Spawn Time**: < 2 seconds average
- **MCTS Decision Time**: < 5 seconds for depth 3
- **Parallel Exploration**: Support 10+ concurrent containers

### Quality Metrics
- **Code Coverage**: Achieve > 80% on generated code
- **Bug Detection**: Find > 90% of issues before PR
- **Performance**: No regressions vs baseline
- **Learning Rate**: 20% improvement after 100 iterations

## Configuration

### Environment Variables
```bash
# Core settings
OPPIE_INSTALL_DIR=/usr/local/oppie
OPPIE_WORKSPACE=/tmp/oppie-experiments
OPPIE_MAX_CONTAINERS=10
OPPIE_MCTS_DEPTH=3
OPPIE_EXPLORATION_FACTOR=1.414

# Optional: Custom endpoints
OPPIE_MONITOR_PATH=/usr/local/bin/monitor_ci
OPPIE_REGISTRY=docker.io/oppie
```

### Configuration File
```yaml
# ~/.oppie/config.yml
project:
  type: auto  # auto-detect or specify
  language: node
  framework: react

mcts:
  max_depth: 3
  exploration_constant: 1.414
  simulation_timeout: 30s
  value_threshold: 0.7

containers:
  provider: docker  # docker, podman, firecracker
  max_parallel: 10
  resource_limits:
    memory: 2GB
    cpu: 1.0

agents:
  enabled:
    - tdd
    - refactor
    - security
  custom_agents_dir: ~/.oppie/agents/
```

## Security Considerations

### Token Management
- Use git-credential-helper pattern
- Support multiple secure backends
- Never store tokens in environment variables
- Implement token rotation

### Container Security
- Run containers with minimal privileges
- Use read-only filesystems where possible
- Network isolation by default
- Resource limits enforced

### Code Validation
- All generated code must pass linting
- Security scanning before execution
- Input validation on all parameters
- Sandbox escaping prevention

## API Reference

### CLI Commands
```bash
oppie init                    # Initialize in current project
oppie explore <task>          # Start MCTS exploration
oppie status                  # Show current exploration tree
oppie learn                   # Update value estimates from results
oppie clean                   # Remove experiment containers
```

### Programmatic API
```typescript
import { OppieAutoNav } from 'oppie-autonav';

const oppie = new OppieAutoNav({
  projectRoot: process.cwd(),
  mctsDepth: 3,
  containerProvider: 'docker'
});

// Start exploration
const exploration = await oppie.explore({
  task: 'implement OAuth2 login',
  constraints: {
    timeLimit: 300,
    maxContainers: 5
  }
});

// Get best solution
const solution = exploration.getBestPath();
await solution.apply();
```

## Migration Path

### From Manual Development
1. Install oppie-autonav
2. Run project detection
3. Start with single-agent exploration
4. Gradually increase MCTS depth
5. Add specialized agents as needed

### From Existing CI/CD
1. Keep existing pipelines
2. Add oppie monitoring
3. Learn from CI outcomes
4. Gradually shift to pre-commit exploration
5. Full MCTS-driven development

## Support & Documentation

- **Website**: https://oppie.xyz
- **Documentation**: https://oppie.xyz/docs
- **GitHub**: https://github.com/good-night-oppie/oppie-autonav
- **Discord**: https://discord.gg/oppie

## License

MIT License - See LICENSE file for details

---

*This PRD defines Oppie AutoNav as a universal MCTS orchestration framework for intelligent, exploration-based development.*