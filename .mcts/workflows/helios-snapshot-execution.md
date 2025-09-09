# MCTS Helios Snapshot Execution Workflow

## Architecture Overview

```
MCTS Engine (Planning & Reflection)
      ↓ decides: A → A.1
Oppie-AutoNav (Orchestration)
      ↓ triggers: @.claude/commands/otw/research-tdd-pr-review
Claude Code (Execution)
      ↓ executes: TDD cycle + PR review
Helios Engine (Target)
      ↓ produces: Snapshot A.1 + metrics
MCTS Engine (Backpropagation)
      ↓ learns: A.1 value + updates tree
```

## Workflow Phases

### Phase 1: MCTS Decision (Planning)
- **Actor**: MCTS Planner
- **Input**: Current helios snapshot A
- **Process**: UCB1 selection of next exploration node
- **Output**: Action plan for A → A.1 transition
- **Integration**: Triggers oppie-autonav orchestration hooks

### Phase 2: AutoNav Orchestration (Execute-Test-Backtrack)
- **Actor**: oppie-autonav workflow coordinator
- **Input**: MCTS action plan
- **Process**: 
  ```bash
  # Coordinate execution via Claude Code
  @.claude/commands/otw/research-tdd-pr-review --snapshot A.1 --mcts-node ${NODE_ID}
  ```
- **Output**: Orchestrated execution request to Claude
- **Integration**: Activates execute-test-backtrack cycle

### Phase 3: Claude Code Execution (TDD Implementation)
- **Actor**: Claude Code + research-tdd-pr-review workflow
- **Input**: Snapshot transition requirements
- **Process**: Research → Red → Green → Refactor → Validate → PR
- **Output**: Implemented code changes + test results
- **Integration**: Feeds results back to oppie-autonav hooks

### Phase 4: Test & Validation (Backtrack Decision)
- **Actor**: oppie-autonav hooks + helios benchmarks
- **Input**: Implementation results + performance metrics
- **Process**: 
  - Run helios benchmarks
  - Compare A vs A.1 performance
  - Validate correctness
  - Generate snapshot report
- **Output**: Success/failure + performance delta
- **Integration**: Reports to MCTS for backpropagation

### Phase 5: MCTS Learning (Reflection & All-Reducing)
- **Actor**: MCTS Engine reflection module
- **Input**: Execution results + performance metrics
- **Process**:
  - Update node value based on outcomes
  - Backpropagate rewards up the tree
  - Adjust exploration strategy
  - All-reduce across distributed MCTS instances
- **Output**: Updated MCTS tree + learned patterns
- **Integration**: Prepares for next exploration cycle

## File Structure

```
.mcts/workflows/
├── helios-snapshot-execution.md     # This workflow
├── execution-templates/
│   ├── snapshot-transition.yml     # A → A.1 template
│   ├── tdd-integration.yml         # TDD workflow integration
│   └── backtrack-decision.yml      # Backtrack logic
├── hooks/
│   ├── pre-execution.sh           # Setup helios snapshot
│   ├── post-execution.sh          # Collect metrics
│   └── backtrack-handler.sh       # Handle failures
└── coordination/
    ├── mcts-autonav-bridge.js     # MCTS ↔ AutoNav coordination
    ├── autonav-claude-bridge.sh   # AutoNav ↔ Claude coordination
    └── metrics-collector.py       # Performance data collection
```

## Integration Points

### MCTS → AutoNav
```yaml
trigger:
  event: mcts.node.selected
  payload:
    node_id: ${NODE_ID}
    action: ${ACTION_DESCRIPTION}
    parent_snapshot: A
    target_snapshot: A.1
    expected_improvement: ${EXPECTED_DELTA}
```

### AutoNav → Claude
```bash
# Trigger via oppie-autonav hooks
oppie_hooks_trigger() {
  local node_id=$1
  local snapshot_target=$2
  
  # Coordinate with Claude Code
  @.claude/commands/otw/research-tdd-pr-review \
    --mcts-node "$node_id" \
    --target-snapshot "$snapshot_target" \
    --enable-mcts-feedback
}
```

### Claude → Helios → MCTS
```bash
# Post-execution feedback loop
helios_benchmark_feedback() {
  local results=$(run_helios_benchmarks)
  local performance_delta=$(calculate_improvement)
  
  # Feed back to MCTS
  mcts_update_node \
    --node-id "$NODE_ID" \
    --reward "$performance_delta" \
    --metrics "$results"
}
```

## Success Metrics

### Execution Quality
- **Code Correctness**: All tests pass
- **Performance Delta**: Measurable improvement in helios benchmarks
- **Integration Success**: Successful A → A.1 transition

### Learning Quality  
- **MCTS Convergence**: Tree values stabilize over iterations
- **Exploration Efficiency**: Better solutions found faster over time
- **Pattern Recognition**: Successful strategies are reused

### Coordination Quality
- **Workflow Latency**: < 5 minutes for simple transitions
- **Error Recovery**: Automatic backtrack on failures
- **State Consistency**: Snapshots remain valid throughout process

## Error Handling & Backtracking

### Execution Failures
```bash
if [[ $execution_status != "success" ]]; then
  # Backtrack to previous snapshot
  helios_restore_snapshot A
  
  # Update MCTS with negative reward
  mcts_update_node --node-id "$NODE_ID" --reward -1.0
  
  # Try alternative approach
  mcts_explore_alternative --parent-node "$PARENT_ID"
fi
```

### Performance Regressions
```bash
if [[ $performance_delta < 0 ]]; then
  echo "Performance regression detected"
  
  # Conditional backtrack based on severity
  if [[ $performance_delta < -0.1 ]]; then
    helios_restore_snapshot A
    mcts_mark_node_failed "$NODE_ID"
  else
    # Minor regression, continue with penalty
    mcts_update_node --node-id "$NODE_ID" --reward -0.5
  fi
fi
```

## Next Steps for Implementation

1. **Create coordination bridges** between MCTS, AutoNav, and Claude
2. **Implement helios snapshot management** for A → A.1 transitions  
3. **Enhance research-tdd-pr-review** with MCTS integration hooks
4. **Set up metrics collection** and performance feedback loops
5. **Test end-to-end workflow** with simple helios improvements