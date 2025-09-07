# MCTS-TDD Integration Workflow

## Overview
Enhanced Research-TDD-PR-Review workflow that integrates with MCTS for helios snapshot exploration and learning.

## Usage
```bash
# MCTS triggers this workflow during exploration
/otw/research-tdd-pr-review --mcts-node ${NODE_ID} --target-snapshot A.1 --enable-mcts-feedback
```

## MCTS Integration Points

### Phase 1: MCTS Node Selection → TDD Initiation
```bash
# MCTS Engine selects node A.1 for exploration
mcts_explore_node() {
  local node_id=$1
  local action_plan=$2
  local parent_snapshot=$3
  local target_snapshot=$4
  
  # Trigger oppie-autonav orchestration
  oppie_coordinate_execution \
    --mcts-node "$node_id" \
    --action "$action_plan" \
    --parent-snapshot "$parent_snapshot" \
    --target-snapshot "$target_snapshot"
}

# OpppieAutoNav coordinates Claude Code execution
oppie_coordinate_execution() {
  local mcts_node=$1
  local action_plan=$2
  
  # Enhanced TDD workflow with MCTS context
  /otw/research-tdd-pr-review \
    --mcts-node "$mcts_node" \
    --action-plan "$action_plan" \
    --enable-mcts-feedback \
    --target-snapshot "$target_snapshot"
}
```

### Phase 2: Enhanced Research Phase (MCTS-Informed)
```bash
# Research phase includes MCTS context
enhanced_research_phase() {
  local mcts_node=$1
  local target_snapshot=$2
  
  # Load MCTS node context
  MCTS_CONTEXT=$(mcts_get_node_context "$mcts_node")
  PARENT_PERFORMANCE=$(mcts_get_parent_metrics "$mcts_node")
  EXPLORATION_GOAL=$(mcts_get_action_plan "$mcts_node")
  
  # Research with MCTS guidance
  echo "📊 MCTS-Guided Research Phase"
  echo "   Node: $mcts_node"
  echo "   Target: $target_snapshot"
  echo "   Goal: $EXPLORATION_GOAL"
  echo "   Parent Performance: $PARENT_PERFORMANCE"
  
  # Include MCTS learnings in research
  mcp__serena__read_memory "mcts_learnings_${domain}" >> research_context.md
  mcp__serena__read_memory "helios_optimization_patterns" >> research_context.md
}
```

### Phase 3: TDD with Performance Targets
```bash
# Red-Green-Refactor with MCTS performance targets
mcts_informed_tdd() {
  local target_improvement=$1
  local current_baseline=$2
  
  echo "🎯 MCTS Performance Targets:"
  echo "   Current Baseline: $current_baseline"
  echo "   Target Improvement: $target_improvement"
  echo "   Acceptance Criteria: Performance delta > 0"
  
  # RED: Write failing tests with performance assertions
  write_performance_tests "$target_improvement"
  
  # GREEN: Implement with MCTS guidance
  implement_with_mcts_learnings
  
  # REFACTOR: Optimize based on MCTS patterns
  refactor_using_mcts_patterns
}
```

### Phase 4: Validation with Helios Benchmarks
```bash
# Enhanced validation that feeds back to MCTS
mcts_validation_phase() {
  local mcts_node=$1
  local target_snapshot=$2
  
  echo "🧪 MCTS Validation Phase"
  
  # Run helios benchmarks
  cd helios-engine
  BENCHMARK_RESULTS=$(go test -bench=. -benchmem -benchtime=10s ./pkg/helios)
  RACE_TEST_RESULTS=$(go test -race -count=100 ./pkg/helios)
  
  # Extract performance metrics
  CURRENT_PERFORMANCE=$(extract_performance_metrics "$BENCHMARK_RESULTS")
  
  # Compare with MCTS expectations
  EXPECTED_PERFORMANCE=$(mcts_get_expected_performance "$mcts_node")
  PERFORMANCE_DELTA=$(calculate_performance_delta "$CURRENT_PERFORMANCE" "$EXPECTED_PERFORMANCE")
  
  echo "📈 Performance Results:"
  echo "   Current: $CURRENT_PERFORMANCE"
  echo "   Expected: $EXPECTED_PERFORMANCE"
  echo "   Delta: $PERFORMANCE_DELTA"
  
  # Feed results back to MCTS
  mcts_update_node_metrics \
    --node-id "$mcts_node" \
    --performance-delta "$PERFORMANCE_DELTA" \
    --benchmark-results "$BENCHMARK_RESULTS"
    
  # Create helios snapshot A.1
  helios_create_snapshot "$target_snapshot" "$BENCHMARK_RESULTS"
}
```

### Phase 5: PR Review with MCTS Context
```bash
# Enhanced PR review that includes MCTS learning
create_mcts_enhanced_pr() {
  local mcts_node=$1
  local performance_delta=$2
  
  # Generate PR with MCTS context
  gh pr create --title "MCTS Node $mcts_node: $EXPLORATION_GOAL" \
    --body "$(generate_mcts_pr_description)"
    
  # Request specialized review with MCTS focus
  gh pr comment "$PR_NUMBER" --body "@claude Please review this MCTS exploration.

## MCTS Context
- **Node ID**: $mcts_node
- **Exploration Goal**: $EXPLORATION_GOAL
- **Parent Performance**: $PARENT_PERFORMANCE
- **Achieved Performance**: $CURRENT_PERFORMANCE
- **Performance Delta**: $PERFORMANCE_DELTA

## Review Focus
As a **Performance Engineering Specialist**, please evaluate:
1. **Performance Validation**: Verify claimed performance improvements
2. **MCTS Learning**: Assess quality of exploration and learning
3. **Helios Impact**: Validate helios engine optimization
4. **Correctness**: Ensure no regressions or bugs introduced

## Expected Deliverables
- [ ] Performance benchmark validation
- [ ] Correctness verification with race testing
- [ ] MCTS learning assessment
- [ ] Recommendation for MCTS tree update
"
}
```

### Phase 6: MCTS Backpropagation
```bash
# Final phase: Update MCTS tree based on results
mcts_backpropagation_phase() {
  local mcts_node=$1
  local pr_approved=$2
  local performance_delta=$3
  
  if [[ $pr_approved == "true" && $performance_delta > 0 ]]; then
    # Successful exploration - positive reward
    REWARD=$(calculate_mcts_reward "$performance_delta")
    
    mcts_update_tree \
      --node-id "$mcts_node" \
      --reward "$REWARD" \
      --status "success" \
      --metrics "$BENCHMARK_RESULTS"
    
    # Store successful pattern for future use
    mcp__serena__write_memory \
      "mcts_successful_pattern_${domain}" \
      "Action: $EXPLORATION_GOAL, Reward: $REWARD, Context: $MCTS_CONTEXT"
    
    echo "✅ MCTS: Node $mcts_node successful, reward: $REWARD"
    
  elif [[ $pr_approved == "false" || $performance_delta < 0 ]]; then
    # Failed exploration - negative reward
    PENALTY=$(calculate_mcts_penalty "$performance_delta")
    
    mcts_update_tree \
      --node-id "$mcts_node" \
      --reward "$PENALTY" \
      --status "failure" \
      --reason "$FAILURE_REASON"
    
    # Store failure pattern to avoid repeating
    mcp__serena__write_memory \
      "mcts_failure_pattern_${domain}" \
      "Action: $EXPLORATION_GOAL, Penalty: $PENALTY, Reason: $FAILURE_REASON"
    
    echo "❌ MCTS: Node $mcts_node failed, penalty: $PENALTY"
    
    # Trigger backtrack to parent snapshot
    helios_restore_snapshot "$parent_snapshot"
  fi
  
  # Update MCTS exploration statistics
  mcts_update_statistics \
    --total-explorations "$((TOTAL_EXPLORATIONS + 1))" \
    --successful-explorations "$SUCCESSFUL_COUNT" \
    --average-reward "$AVERAGE_REWARD"
}
```

## MCTS-Specific Enhancements

### Performance Target Calculation
```bash
calculate_mcts_performance_target() {
  local parent_performance=$1
  local exploration_goal=$2
  
  # Base target on MCTS learnings
  BASE_IMPROVEMENT=$(mcp__serena__read_memory "average_improvement_${domain}")
  
  # Adjust based on exploration type
  case $exploration_goal in
    "lock_free_optimization")
      TARGET_IMPROVEMENT="20%"  # Aggressive target
      ;;
    "memory_pooling")
      TARGET_IMPROVEMENT="15%"  # Moderate target
      ;;
    "cache_optimization")
      TARGET_IMPROVEMENT="10%"  # Conservative target
      ;;
    *)
      TARGET_IMPROVEMENT="5%"   # Default target
      ;;
  esac
  
  echo "$TARGET_IMPROVEMENT"
}
```

### MCTS Learning Integration
```bash
integrate_mcts_learnings() {
  local domain=$1
  
  # Load successful patterns
  SUCCESSFUL_PATTERNS=$(mcp__serena__read_memory "mcts_successful_pattern_${domain}")
  
  # Load failure patterns to avoid
  FAILURE_PATTERNS=$(mcp__serena__read_memory "mcts_failure_pattern_${domain}")
  
  echo "🧠 MCTS Learnings:"
  echo "   Successful Patterns: $SUCCESSFUL_PATTERNS"
  echo "   Patterns to Avoid: $FAILURE_PATTERNS"
  
  # Apply learnings to current implementation
  apply_successful_patterns "$SUCCESSFUL_PATTERNS"
  avoid_failure_patterns "$FAILURE_PATTERNS"
}
```

### Helios Snapshot Management
```bash
# Coordinate with helios for snapshot creation/restoration
helios_create_snapshot() {
  local snapshot_name=$1
  local benchmark_results=$2
  
  cd helios-engine
  
  # Create snapshot with performance metadata
  git tag -a "$snapshot_name" -m "MCTS Snapshot: $snapshot_name
Performance Results:
$benchmark_results

MCTS Node: $MCTS_NODE
Exploration Goal: $EXPLORATION_GOAL"
  
  # Store snapshot metadata for MCTS
  echo "$benchmark_results" > ".mcts/snapshots/${snapshot_name}.metrics"
  
  echo "📸 Created helios snapshot: $snapshot_name"
}

helios_restore_snapshot() {
  local snapshot_name=$1
  
  cd helios-engine
  git checkout "$snapshot_name"
  
  echo "🔄 Restored helios snapshot: $snapshot_name"
}
```

## Integration with Oppie-AutoNav Hooks

### Pre-execution Hook
```bash
# .oppie-hooks/mcts-pre-execution.sh
#!/bin/bash

MCTS_NODE=$1
TARGET_SNAPSHOT=$2

echo "🚀 MCTS Pre-execution Hook"
echo "   Preparing helios for snapshot transition: $TARGET_SNAPSHOT"

# Ensure helios is at correct baseline
cd helios-engine
git checkout "${TARGET_SNAPSHOT%.*}"  # Parent snapshot

# Prepare MCTS context
mcts_prepare_context "$MCTS_NODE"
```

### Post-execution Hook
```bash
# .oppie-hooks/mcts-post-execution.sh
#!/bin/bash

MCTS_NODE=$1
PERFORMANCE_DELTA=$2
PR_STATUS=$3

echo "🏁 MCTS Post-execution Hook"
echo "   Finalizing MCTS learning for node: $MCTS_NODE"

# Update MCTS tree with results
mcts_finalize_exploration \
  --node "$MCTS_NODE" \
  --performance "$PERFORMANCE_DELTA" \
  --status "$PR_STATUS"
```

## Configuration

### MCTS-TDD Config
```yaml
# .mcts/config/tdd-integration.yml
mcts_tdd_integration:
  performance_targets:
    conservative: 5%
    moderate: 10%
    aggressive: 20%
  
  reward_calculation:
    base_reward: 1.0
    performance_multiplier: 0.1
    correctness_bonus: 0.5
    failure_penalty: -1.0
  
  helios_integration:
    snapshot_prefix: "mcts-"
    baseline_branch: "main"
    benchmark_timeout: 300s
    
  learning_thresholds:
    min_explorations: 10
    convergence_threshold: 0.01
    max_tree_depth: 5
```

## Success Metrics

### MCTS Learning Quality
- **Exploration Efficiency**: Better solutions found faster over time
- **Pattern Recognition**: Successful strategies are reused
- **Tree Convergence**: Values stabilize within expected iterations

### Integration Quality
- **Workflow Latency**: < 10 minutes for complete MCTS cycle
- **Performance Accuracy**: Actual vs predicted performance within 10%
- **Learning Retention**: Previous learnings successfully applied

### Helios Optimization
- **Cumulative Improvement**: Total performance gain across all explorations
- **Regression Rate**: < 5% of explorations cause performance regression
- **Snapshot Quality**: All snapshots maintain correctness