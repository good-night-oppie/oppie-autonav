# PRD: Oppie AutoNav - Universal MCTS Orchestration Framework

**Version**: 1.0  
**Date**: 2025-09-06  
**Status**: Active  
**Domain**: oppie.xyz

## Executive Summary

Oppie AutoNav is a **universal, component-based MCTS orchestration framework** designed for intelligent development path exploration. Inspired by SuperClaude's proven architecture, it enables coding agents to explore, evaluate, and optimize solutions through metadata-driven commands, modular components, and secure containerized experimentation.

### Core Value Proposition
- **Component Registry**: Modular architecture with versioned components and dependency resolution
- **Metadata-Driven Commands**: YAML frontmatter-based command system for flexible orchestration
- **Two-Stage Installation**: Interactive setup that reduces complexity while ensuring security
- **MCTS-Driven Development**: Intelligent exploration through configurable evaluation strategies
- **Security-First Design**: Path validation, API key management, and component integrity verification
- **Container-Based Sandboxing**: Safe parallel experimentation without affecting main codebase

## Vision

Transform AI-assisted development from linear execution to intelligent exploration, where every development decision is:
1. **Explored** through multiple parallel paths
2. **Evaluated** in isolated containers
3. **Optimized** based on empirical results
4. **Learned** for future decisions

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│              Oppie AutoNav Component Architecture           │
├──────────────────────────────────────────────────────────┤
│                                                            │
│  ┌────────────────────┐    ┌────────────────────┐       │
│  │  Component         │    │   Metadata-Driven │       │
│  │  Registry          │───▶│   Command System   │       │
│  │  (YAML-based)      │    │   (YAML Frontmatter)│      │
│  └────────────────────┘    └────────────────────┘       │
│           │                          │                    │
│           ▼                          ▼                    │
│  ┌────────────────────┐    ┌────────────────────┐       │
│  │  MCTS Orchestration│    │   Security Layer   │       │
│  │  Engine            │    │   (Path Validation)│       │
│  └────────────────────┘    └────────────────────┘       │
│           │                          │                    │
│           ▼                          ▼                    │
│  ┌────────────────────┐    ┌────────────────────┐       │
│  │  Container         │    │   CI/CD Validation │       │
│  │  Orchestrator      │    │   Pipeline         │       │
│  └────────────────────┘    └────────────────────┘       │
│                                                            │
└──────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Component Registry & Two-Stage Installation

**Objective**: Modular, secure setup with interactive configuration and dependency resolution.

#### Two-Stage Installation Pattern
```bash
# Stage 1: Core installation
pip install oppie-autonav    # Python projects
npm install oppie-autonav    # Node.js projects
cargo install oppie-autonav  # Rust projects

# Stage 2: Interactive framework setup
oppie init  # Interactive configuration wizard
```

#### Component Registry Structure
```yaml
# ~/.oppie/registry.yaml
components:
  - name: UCBEvaluator
    version: 1.2.0
    type: evaluator
    dependencies:
      - name: MathUtils
        version: ">=1.0.0"
    security:
      checksum: sha256:abc123...
      
  - name: DockerSimulator
    version: 2.1.0
    type: simulator
    dependencies:
      - UCBEvaluator
    api_keys:
      - DOCKER_REGISTRY_TOKEN
```

#### Auto-Detection with Security Validation
```javascript
detectAndValidate() {
  // Project type detection
  const projectType = detectProjectType();
  
  // Path validation (prevent traversal)
  validatePaths(config.componentPaths);
  
  // Component integrity verification
  verifyComponentChecksums();
  
  return { projectType, validatedConfig };
}
```

### 2. Metadata-Driven MCTS Commands

**Objective**: Flexible, configurable MCTS orchestration through metadata-driven commands.

#### Command Definition Structure
```markdown
---
name: mcts:select
description: "UCB1-based node selection with configurable exploration"
category: selection
complexity: medium
parameters:
  - name: exploration_constant
    type: float
    default: 1.414
    validation: ">0"
  - name: depth_limit
    type: int
    default: 3
dependencies:
  - UCBEvaluator
  - MathUtils
security:
  sandbox: required
  api_keys: []
---

# MCTS Selection Command

## Workflow
1. Load UCB evaluator with exploration constant
2. Compute UCB scores for all child nodes
3. Return node with highest UCB score
4. Log selection decision with metadata

## Examples
```bash
oppie mcts:select --exploration_constant=1.0
oppie mcts:select --depth_limit=5
```
```

#### Core MCTS Commands
```yaml
commands:
  - mcts:select    # Node selection with UCB1
  - mcts:expand    # Child node generation
  - mcts:simulate  # Rollout in containers
  - mcts:backup    # Value backpropagation
  - mcts:learn     # Update strategies from results
```

#### Component-Based Node Structure
```typescript
interface MCTSNode {
  id: string;
  state: CodeState;
  action: DevelopmentAction;
  value: number;           // Estimated value
  visits: number;          // Exploration count
  children: MCTSNode[];
  parent: MCTSNode | null;
  
  // Component metadata
  components: {
    evaluator: ComponentReference;
    simulator: ComponentReference;
    strategy: ComponentReference;
  };
  
  // Experiment results
  experiments: {
    container_id: string;
    outcome: ExperimentResult;
    metrics: PerformanceMetrics;
    artifacts: string[];     // Generated files
    component_versions: ComponentVersion[];
  }[];
}

interface ComponentReference {
  name: string;
  version: string;
  checksum: string;
  metadata: Record<string, any>;
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

### 4. Component-Based Agent System

**Objective**: Modular, metadata-driven agent orchestration with dependency resolution.

#### Component Definition Structure
```markdown
---
name: TDDAgent
version: 2.1.0
type: agent
category: testing
description: "Test-driven development agent with coverage analysis"
capabilities: [write_tests, verify_coverage, suggest_edge_cases]
dependencies:
  - name: TestFrameworkDetector
    version: ">=1.0.0"
  - name: CoverageAnalyzer
    version: ">=2.5.0"
api_requirements:
  - TESTING_FRAMEWORK_API
security:
  sandbox_required: true
  network_access: false
resources:
  memory_limit: 1GB
  cpu_limit: 0.5
---

# TDD Agent Implementation

## Core Functions
- Analyze code structure for testability
- Generate comprehensive test suites
- Validate test coverage thresholds
- Suggest edge case scenarios
```

#### Component Registry Integration
```yaml
registered_agents:
  testing:
    - TDDAgent@2.1.0
    - BehaviorTestAgent@1.3.0
    
  refactoring:
    - CodeSmellDetector@3.0.1
    - PerformanceOptimizer@1.8.2
    
  security:
    - VulnerabilityScanner@4.2.0
    - ComplianceValidator@2.0.5
    
  review:
    - StandardsChecker@1.9.3
    - LogicValidator@2.4.1
```

#### Component-Based Orchestration
```typescript
// Component loading with dependency resolution
async function loadComponent(name: string, version: string): Promise<Component> {
  const registry = await Registry.load();
  const component = await registry.resolve(name, version);
  
  // Verify component integrity
  await verifyChecksum(component);
  
  // Load dependencies recursively
  const dependencies = await Promise.all(
    component.dependencies.map(dep => loadComponent(dep.name, dep.version))
  );
  
  return new ComponentInstance(component, dependencies);
}

// Metadata-driven parallel exploration
async function exploreWithComponents(task: Task, componentSpecs: ComponentSpec[]) {
  const components = await Promise.all(
    componentSpecs.map(spec => loadComponent(spec.name, spec.version))
  );
  
  const results = await Promise.all(
    components.map(component => {
      return sandboxedExecution(component, task, {
        memoryLimit: component.metadata.resources.memory_limit,
        cpuLimit: component.metadata.resources.cpu_limit,
        networkAccess: component.metadata.security.network_access
      });
    })
  );
  
  return mergeSolutions(results);
}
```

### 5. CI/CD Validation Pipeline Integration

**Objective**: Comprehensive validation system ensuring component integrity, security, and performance.

#### Validation Pipeline Structure
```yaml
# .github/workflows/oppie-validation.yml
name: Oppie Component Validation
on: [push, pull_request, component_update]

jobs:
  component_validation:
    runs-on: ubuntu-latest
    steps:
      - name: Component Integrity Check
        run: |
          oppie registry verify --all
          oppie registry checksum --validate
          
      - name: Metadata Schema Validation
        run: |
          oppie validate schema --components
          oppie validate metadata --strict
          
      - name: Security Scanning
        run: |
          oppie scan vulnerabilities --components
          oppie scan dependencies --security
          
      - name: Performance Benchmarks
        run: |
          oppie benchmark --baseline
          oppie test performance --threshold=95%
          
      - name: Integration Testing
        run: |
          oppie test mcts --full-cycle
          oppie test components --integration
```

#### Quality Gates
```yaml
quality_requirements:
  component_integrity:
    checksum_validation: required
    signature_verification: required
    dependency_resolution: required
    
  security_standards:
    vulnerability_scan: passing
    dependency_audit: clean
    api_key_validation: secure
    
  performance_criteria:
    component_load_time: <2s
    memory_usage: <1GB per component
    mcts_decision_time: <5s depth_3
    
  test_coverage:
    unit_tests: >90%
    integration_tests: >80%
    end_to_end: >70%
```

#### Learning Integration
```yaml
ci_learning_loop:
  monitor:
    - Component performance metrics
    - MCTS decision effectiveness
    - Container resource utilization
    - Security scan results
    
  analyze:
    - Performance regression patterns
    - Component compatibility issues
    - Resource optimization opportunities
    - Security vulnerability trends
    
  update:
    - Component version recommendations
    - Resource allocation strategies
    - Security policy adjustments
    - Performance optimization hints
```

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- [x] Component registry with YAML-based configuration
- [x] Two-stage interactive installation system
- [x] Metadata-driven command framework
- [ ] Basic MCTS orchestration commands
- [ ] Security layer with path validation

### Phase 2: Intelligence (Weeks 3-4)
- [ ] Container-based simulation framework
- [ ] CI/CD validation pipeline integration
- [ ] Component dependency resolution system
- [ ] Advanced MCTS strategies with learning
- [ ] Multi-agent parallel exploration

### Phase 3: Scale (Weeks 5-6)
- [ ] Distributed MCTS across multiple machines
- [ ] Plugin architecture for custom components
- [ ] Advanced caching and memoization
- [ ] Production deployment and monitoring tools
- [ ] Enterprise security and compliance features

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

### Configuration Files

#### Main Configuration
```yaml
# ~/.oppie/config.yml
project:
  type: auto  # auto-detect or specify
  language: node
  framework: react
  
registry:
  components_dir: ~/.oppie/components/
  cache_dir: ~/.oppie/cache/
  security:
    verify_checksums: true
    allow_unsigned: false

mcts:
  max_depth: 3
  exploration_constant: 1.414
  simulation_timeout: 30s
  value_threshold: 0.7
  
commands:
  metadata_validation: strict
  parameter_sanitization: enabled
  audit_logging: true

containers:
  provider: docker  # docker, podman, firecracker
  max_parallel: 10
  security:
    network_isolation: true
    read_only_filesystem: true
  resource_limits:
    memory: 2GB
    cpu: 1.0

ci_cd:
  validation_pipeline: enabled
  test_coverage_threshold: 80
  security_scanning: enabled
```

#### Component Registry
```yaml
# ~/.oppie/registry.yaml
schema_version: "1.0"
components:
  evaluators:
    - name: UCBEvaluator
      version: 1.2.0
      checksum: sha256:abc123...
      dependencies: [MathUtils>=1.0.0]
      
  simulators:
    - name: DockerSimulator
      version: 2.1.0
      checksum: sha256:def456...
      dependencies: [UCBEvaluator]
      api_keys: [DOCKER_REGISTRY_TOKEN]
      
  strategies:
    - name: AdaptiveMCTS
      version: 3.0.1
      checksum: sha256:ghi789...
      dependencies: [UCBEvaluator, DockerSimulator]
```

## Security Considerations

### Component Integrity & Path Validation
- **Component Verification**: SHA256 checksums for all registry components
- **Path Allowlisting**: Strict validation against path traversal attacks
- **Signature Verification**: Signed component packages with integrity checks
- **Dependency Resolution**: Secure resolution of component dependencies

### Token Management
- **Environment-Based**: API keys loaded from secure environment variables
- **Schema Validation**: Regex patterns for API key format validation
- **Multi-Backend Support**: git-credential-helper, keyring, vault integration
- **Runtime-Only**: Never persist tokens to disk or logs

### Container Security
- **Minimal Privileges**: Run containers with restricted user permissions
- **Read-Only Filesystems**: Prevent container modification attacks
- **Network Isolation**: Default deny network access with explicit allowlists
- **Resource Limits**: CPU/memory limits enforced per container
- **Image Scanning**: Vulnerability scanning of base container images

### Command Validation
- **YAML Schema**: Strict validation of metadata frontmatter
- **Parameter Sanitization**: Input validation on all command parameters
- **Sandbox Enforcement**: Required sandboxing for untrusted components
- **Audit Logging**: Complete audit trail of all command executions

## API Reference

### CLI Commands

#### Core Commands
```bash
# Installation & Setup
oppie init                    # Interactive framework setup
oppie registry list           # Show available components
oppie registry install <component>  # Install specific component
oppie registry verify         # Verify component integrity

# MCTS Operations
oppie mcts:select <options>   # Execute selection phase
oppie mcts:expand <options>   # Execute expansion phase
oppie mcts:simulate <options> # Execute simulation phase
oppie mcts:backup <options>   # Execute backpropagation phase
oppie explore <task>          # Full MCTS exploration cycle

# Management
oppie status                  # Show exploration state
oppie learn                   # Update from results
oppie clean                   # Remove experiment containers
oppie validate               # Run validation pipeline
```

#### Metadata-Driven Command Examples
```bash
# Selection with custom exploration
oppie mcts:select --exploration_constant=1.5 --depth_limit=4

# Simulation with specific container
oppie mcts:simulate --container=docker --timeout=60s --parallel=5

# Learning from CI outcomes
oppie mcts:learn --source=ci --update_strategy=adaptive
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

## Conclusion

This refined PRD transforms Oppie AutoNav from a simple universal installer into a sophisticated, **component-based MCTS orchestration framework** that leverages proven architectural patterns from SuperClaude:

### Key Architectural Improvements

1. **Component Registry System**: Modular, versioned components with dependency resolution
2. **Metadata-Driven Commands**: YAML frontmatter-based command definitions with automatic validation
3. **Two-Stage Installation**: Interactive setup reducing complexity while ensuring security
4. **Security-First Design**: Comprehensive path validation, component integrity, and API key management
5. **CI/CD Integration**: Automated validation pipelines ensuring quality and performance

### Strategic Benefits

- **Modularity**: Plugin-based architecture enabling custom MCTS strategies
- **Security**: Production-ready security model preventing common vulnerabilities
- **Maintainability**: Clear separation of concerns with component-based design
- **Scalability**: Framework capable of supporting complex, distributed MCTS implementations
- **Developer Experience**: Interactive installation and metadata-driven commands reduce friction

### Evolution Path

The framework now follows a clear evolution from:
- **Simple Installer** → **Component-Based Framework**
- **Linear Commands** → **Metadata-Driven Orchestration**
- **Basic Security** → **Production-Ready Security Model**
- **Manual Setup** → **Interactive, Validated Installation**

This architectural foundation positions Oppie AutoNav as a mature, enterprise-ready MCTS orchestration platform that can adapt to diverse development scenarios while maintaining security, performance, and usability standards.

---

*This PRD defines Oppie AutoNav as a component-based MCTS orchestration framework for intelligent, secure, and scalable development automation.*