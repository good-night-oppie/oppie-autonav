# ADR-002: MCTS Orchestration Architecture for Oppie AutoNav

**Date**: 2025-09-06  
**Status**: Proposed  
**Context**: Evolution from linear execution to intelligent exploration  
**Decision Makers**: Architecture Team  

## Executive Summary

This ADR documents the decision to implement Monte Carlo Tree Search (MCTS) as the core decision engine for Oppie AutoNav, enabling intelligent parallel exploration of development paths through containerized experimentation.

## Context

### The Problem
Current AI coding assistants execute tasks linearly without exploring alternatives:
- Single solution path without comparison
- No learning from failed attempts
- Limited ability to optimize solutions
- No systematic exploration of design space

### The Opportunity
MCTS, proven in game AI (AlphaGo/AlphaZero), can revolutionize development:
- Explore multiple solutions in parallel
- Learn from each experiment
- Converge on optimal approaches
- Build knowledge over time

## Decision

### Core Architecture: MCTS with Container-Based Simulation

```
┌────────────────────────────────────────────────┐
│              MCTS Decision Engine               │
├────────────────────────────────────────────────┤
│                                                 │
│  Selection → Expansion → Simulation → Backprop │
│      ↓           ↓            ↓           ↓    │
│    UCB1      Generate    Container    Update   │
│             Actions     Experiments    Values  │
│                                                 │
└────────────────────────────────────────────────┘
```

### Key Components

#### 1. MCTS Node Structure
```typescript
interface MCTSNode {
  // Identity
  id: string;
  parentId: string | null;
  
  // State
  codeState: {
    files: Map<string, string>;
    tests: TestResults;
    metrics: PerformanceMetrics;
  };
  
  // Action that led to this state
  action: {
    type: 'refactor' | 'implement' | 'test' | 'optimize';
    description: string;
    agent: string;
  };
  
  // MCTS Statistics
  value: number;        // Average reward
  visits: number;       // Exploration count
  ucb1Score: number;    // Upper Confidence Bound
  
  // Experiment History
  experiments: [{
    containerId: string;
    duration: number;
    outcome: 'success' | 'failure' | 'timeout';
    metrics: object;
  }];
  
  // Tree Structure
  children: MCTSNode[];
}
```

#### 2. Container Orchestration
```yaml
container_tiers:
  tier_1_syntax:
    provider: Docker Alpine
    startup: <500ms
    memory: 256MB
    use: Syntax validation, linting
    
  tier_2_unit:
    provider: Docker Standard
    startup: 1-2s
    memory: 1GB
    use: Unit tests, compilation
    
  tier_3_integration:
    provider: Podman
    startup: 2-5s
    memory: 2GB
    use: Integration tests, benchmarks
    
  tier_4_system:
    provider: Firecracker
    startup: 5-10s
    memory: 4GB
    use: Full system tests, load tests
```

#### 3. Exploration Strategy
```javascript
// UCB1 Algorithm for node selection
function selectNode(node, explorationConstant = 1.414) {
  const exploitation = node.value / node.visits;
  const exploration = explorationConstant * 
    Math.sqrt(Math.log(node.parent.visits) / node.visits);
  return exploitation + exploration;
}

// Parallel exploration
async function exploreParallel(root, maxContainers = 10) {
  const promises = [];
  for (let i = 0; i < maxContainers; i++) {
    promises.push(explorePathAsync(root));
  }
  return Promise.all(promises);
}
```

## Rationale

### Why MCTS?

1. **Proven Success**: AlphaGo/AlphaZero demonstrated superhuman performance
2. **Balance**: Natural balance between exploration and exploitation
3. **Parallelizable**: Can leverage multiple containers simultaneously
4. **Learning**: Improves with each iteration
5. **Explainable**: Clear decision tree for debugging

### Why Containers?

1. **Isolation**: Safe experimentation without side effects
2. **Reproducibility**: Consistent environment for each experiment
3. **Parallelism**: Run multiple experiments simultaneously
4. **Resource Control**: Precise CPU/memory limits
5. **Fast Iteration**: Quick spawn/destroy cycles

### Alternative Considered: Linear Execution
- **Pros**: Simple, predictable, easy to debug
- **Cons**: No exploration, no learning, no optimization
- **Verdict**: Insufficient for complex development tasks

### Alternative Considered: Random Search
- **Pros**: Simple to implement, good coverage
- **Cons**: Inefficient, no learning, no guided exploration
- **Verdict**: MCTS provides better convergence

## Implementation Strategy

### Phase 1: Core MCTS Engine (Week 1)
```typescript
class MCTSEngine {
  constructor(
    private containerOrchestrator: ContainerOrchestrator,
    private agentPool: AgentPool
  ) {}
  
  async explore(task: Task, config: MCTSConfig) {
    const root = this.initializeRoot(task);
    
    for (let i = 0; i < config.iterations; i++) {
      const leaf = this.select(root);
      const child = this.expand(leaf);
      const reward = await this.simulate(child);
      this.backpropagate(child, reward);
    }
    
    return this.getBestPath(root);
  }
}
```

### Phase 2: Container Integration (Week 2)
```typescript
class ContainerOrchestrator {
  async runExperiment(node: MCTSNode) {
    const container = await this.spawnContainer(node.tier);
    
    try {
      await container.applyCode(node.codeState);
      const results = await container.runTests();
      const metrics = await container.collectMetrics();
      
      return {
        success: results.passed === results.total,
        metrics: metrics,
        duration: container.elapsed()
      };
    } finally {
      await container.destroy();
    }
  }
}
```

### Phase 3: Learning & Optimization (Week 3)
```typescript
class ValueNetwork {
  predict(state: CodeState): number {
    // Neural network or heuristic evaluation
    return this.model.evaluate(state);
  }
  
  update(state: CodeState, actualValue: number) {
    this.trainingData.add(state, actualValue);
    if (this.trainingData.size % 100 === 0) {
      this.retrain();
    }
  }
}
```

## Metrics for Success

### Performance Metrics
- **Exploration Rate**: > 100 nodes/minute
- **Container Utilization**: > 80% parallel usage
- **Convergence Speed**: < 50 iterations for common tasks
- **Solution Quality**: > 20% improvement vs linear approach

### Resource Metrics
- **Memory Usage**: < 4GB for 10 parallel containers
- **CPU Usage**: < 80% on 4-core machine
- **Disk I/O**: < 100MB/s sustained
- **Network**: < 10Mbps for package downloads

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Container overhead | High | Use lightweight Alpine images, cache layers |
| State explosion | High | Prune low-value branches, limit depth |
| Non-determinism | Medium | Set random seeds, snapshot containers |
| Resource exhaustion | High | Implement hard limits, auto-cleanup |
| Slow convergence | Medium | Tune UCB1 constant, add heuristics |

## Security Considerations

1. **Container Isolation**: Use gVisor or Kata for untrusted code
2. **Resource Limits**: Enforce CPU, memory, disk quotas
3. **Network Isolation**: No external network by default
4. **Code Validation**: Scan generated code before execution
5. **Audit Trail**: Log all experiments and outcomes

## Future Enhancements

### Near Term (3-6 months)
- Distributed MCTS across multiple machines
- GPU acceleration for value network
- Advanced caching strategies
- Plugin architecture for custom agents

### Long Term (6-12 months)
- Multi-objective optimization (speed vs quality)
- Transfer learning between projects
- Automated hyperparameter tuning
- Integration with cloud providers

## Decision Outcome

**Status**: Approved for implementation

**Rationale**: MCTS provides the optimal balance of exploration, learning, and convergence for automated development tasks. Container-based simulation ensures safety and reproducibility.

**Next Steps**:
1. Implement core MCTS engine
2. Integrate container orchestration
3. Deploy to test projects
4. Measure and optimize

---

**Review Schedule**: Monthly during initial implementation, quarterly thereafter

**Success Criteria**: 20% improvement in solution quality, 50% reduction in development time for complex tasks