#!/bin/bash
# MCTS Pre-execution Hook for Oppie AutoNav
# Prepares helios snapshot transition and MCTS context

set -euo pipefail

MCTS_NODE=${1:-""}
TARGET_SNAPSHOT=${2:-""}
PARENT_SNAPSHOT=${3:-"main"}
EXPLORATION_GOAL=${4:-"general_optimization"}

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 MCTS Pre-execution Hook${NC}"
echo -e "${YELLOW}   Node: $MCTS_NODE${NC}"
echo -e "${YELLOW}   Target Snapshot: $TARGET_SNAPSHOT${NC}"
echo -e "${YELLOW}   Parent Snapshot: $PARENT_SNAPSHOT${NC}"
echo -e "${YELLOW}   Exploration Goal: $EXPLORATION_GOAL${NC}"

# Validate inputs
if [[ -z "$MCTS_NODE" || -z "$TARGET_SNAPSHOT" ]]; then
    echo "❌ Error: MCTS_NODE and TARGET_SNAPSHOT are required"
    echo "Usage: $0 <mcts_node> <target_snapshot> [parent_snapshot] [exploration_goal]"
    exit 1
fi

# Ensure we're in the right project
if [[ ! -d "../helios-engine" && ! -d "helios-engine" ]]; then
    echo "❌ Error: helios-engine directory not found"
    exit 1
fi

# Navigate to helios-engine
if [[ -d "helios-engine" ]]; then
    cd helios-engine
elif [[ -d "../helios-engine" ]]; then
    cd ../helios-engine
fi

echo -e "${BLUE}📍 Working in: $(pwd)${NC}"

# Ensure we're at the correct baseline snapshot
echo -e "${BLUE}🔄 Setting up baseline snapshot: $PARENT_SNAPSHOT${NC}"
git fetch origin --tags 2>/dev/null || true

if git tag | grep -q "^$PARENT_SNAPSHOT$"; then
    git checkout "$PARENT_SNAPSHOT"
    echo -e "${GREEN}✅ Checked out snapshot tag: $PARENT_SNAPSHOT${NC}"
elif git branch -r | grep -q "origin/$PARENT_SNAPSHOT"; then
    git checkout "$PARENT_SNAPSHOT"
    echo -e "${GREEN}✅ Checked out branch: $PARENT_SNAPSHOT${NC}"
else
    echo -e "${YELLOW}⚠️  Snapshot $PARENT_SNAPSHOT not found, using current HEAD${NC}"
fi

# Create MCTS context directory
MCTS_CONTEXT_DIR=".mcts/contexts"
mkdir -p "$MCTS_CONTEXT_DIR"

# Prepare MCTS context file
CONTEXT_FILE="$MCTS_CONTEXT_DIR/node_${MCTS_NODE}_context.json"
cat > "$CONTEXT_FILE" << EOF
{
  "node_id": "$MCTS_NODE",
  "target_snapshot": "$TARGET_SNAPSHOT",
  "parent_snapshot": "$PARENT_SNAPSHOT",
  "exploration_goal": "$EXPLORATION_GOAL",
  "timestamp": "$(date -Iseconds)",
  "baseline_commit": "$(git rev-parse HEAD)",
  "baseline_performance": null,
  "expected_improvement": null,
  "status": "preparing"
}
EOF

echo -e "${GREEN}✅ Created MCTS context: $CONTEXT_FILE${NC}"

# Collect baseline performance metrics
echo -e "${BLUE}📊 Collecting baseline performance metrics...${NC}"
if [[ -f "go.mod" ]]; then
    # Run baseline benchmarks
    BASELINE_RESULTS=$(go test -bench=. -benchmem -benchtime=5s ./pkg/helios 2>/dev/null | grep -E "Benchmark|ns/op|B/op" || echo "baseline_collection_failed")
    
    # Update context with baseline
    jq --arg baseline "$BASELINE_RESULTS" '.baseline_performance = $baseline | .status = "ready"' "$CONTEXT_FILE" > "${CONTEXT_FILE}.tmp" && mv "${CONTEXT_FILE}.tmp" "$CONTEXT_FILE"
    
    echo -e "${GREEN}✅ Baseline performance collected${NC}"
else
    echo -e "${YELLOW}⚠️  No go.mod found, skipping baseline collection${NC}"
fi

# Load MCTS learnings for this domain/goal
echo -e "${BLUE}🧠 Loading MCTS learnings for: $EXPLORATION_GOAL${NC}"
LEARNINGS_DIR=".mcts/learnings"
mkdir -p "$LEARNINGS_DIR"

PATTERNS_FILE="$LEARNINGS_DIR/${EXPLORATION_GOAL}_patterns.json"
if [[ ! -f "$PATTERNS_FILE" ]]; then
    # Initialize patterns file
    cat > "$PATTERNS_FILE" << EOF
{
  "successful_patterns": [],
  "failure_patterns": [],
  "avg_improvement": 0.05,
  "exploration_count": 0,
  "last_updated": "$(date -Iseconds)"
}
EOF
    echo -e "${YELLOW}⚠️  Initialized new patterns file: $PATTERNS_FILE${NC}"
else
    echo -e "${GREEN}✅ Loaded existing patterns: $PATTERNS_FILE${NC}"
fi

# Set environment variables for the TDD workflow
export MCTS_NODE="$MCTS_NODE"
export TARGET_SNAPSHOT="$TARGET_SNAPSHOT" 
export PARENT_SNAPSHOT="$PARENT_SNAPSHOT"
export EXPLORATION_GOAL="$EXPLORATION_GOAL"
export MCTS_CONTEXT_FILE="$CONTEXT_FILE"
export MCTS_PATTERNS_FILE="$PATTERNS_FILE"

echo -e "${GREEN}✅ MCTS environment prepared for execution${NC}"
echo -e "${BLUE}🎯 Ready for: oppie-autonav → Claude Code → TDD workflow${NC}"

# Return to oppie-autonav directory
cd - > /dev/null

exit 0