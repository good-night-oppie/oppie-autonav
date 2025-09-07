# Oppie AutoNav Consolidation Plan for MCTS Orchestration

## Overview
Consolidating multiple copied folders into a unified structure optimized for MCTS Inner cycle simulation and public agent orchestration workflows.

## Directory Structure (Consolidated)

```
oppie-autonav/
├── .mcts/                      # Core MCTS orchestration (NEW - consolidated)
│   ├── agents/                 # Agent definitions for MCTS nodes
│   ├── containers/             # Container orchestration configs
│   ├── experiments/            # Experiment templates and results
│   ├── memories/               # MCTS learning and history
│   └── workflows/              # MCTS workflow definitions
│
├── .claude/                    # Claude-specific (KEEP - enhanced)
│   ├── agents/                 # Merge from ".claude copy/agents"
│   ├── commands/               # Unified commands including TM
│   ├── config/                 # Consolidated configs
│   ├── context/                # MCTS context management
│   ├── docs/                   # Keep ADRs
│   └── hooks/                  # Keep monitor-daemon
│
├── .serena/                    # Semantic memory (KEEP - enhanced)
│   ├── memories/               # Including MCTS ADRs
│   └── index/                  # Code search index
│
├── agents/                     # Public agent definitions (CONSOLIDATED)
│   └── mcts/                   # MCTS-specific agents
│       ├── explorer.yml        # Exploration agent
│       ├── evaluator.yml       # Evaluation agent
│       └── optimizer.yml       # Optimization agent
│
├── scripts/                    # Executable scripts (CONSOLIDATED)
│   ├── install.sh              # Universal installer (preserved)
│   ├── mcts/                   # MCTS-specific scripts
│   └── monitoring/             # CI/PR monitoring
│
├── docs/                       # Public documentation (CONSOLIDATED)
│   ├── mcts/                   # MCTS documentation
│   ├── agents/                 # Agent documentation
│   └── workflows/              # Workflow documentation
│
└── workflows/                  # MCTS workflow definitions (NEW)
    ├── exploration/            # Exploration strategies
    ├── simulation/             # Simulation configs
    └── backpropagation/        # Learning algorithms
```

## Consolidation Actions

### 1. Merge Duplicate Folders
- `.claude copy` → `.claude` (selective merge)
- `.serena copy` → `.serena` (selective merge)
- `agents copy` → `agents` (merge unique content)
- `docs copy` → `docs` (merge unique content)
- `scripts copy` → `scripts` (merge unique content)

### 2. Create MCTS-Specific Structure
- Create `.mcts/` for MCTS orchestration
- Move MCTS-related content from other folders
- Establish clear separation of concerns

### 3. Remove Internal/Private References
- Clean oppie-thunder specific paths
- Remove personal workspace references
- Generalize for public use

### 4. Preserve Universal Installer
- Keep `scripts/install.sh` intact
- Ensure compatibility with existing strategy
- Add MCTS-specific installation options

## Files to Consolidate

### High Priority (MCTS Core)
1. `.serena/memories/adr-002-mcts-orchestration-architecture.md` → Keep
2. `issues/mcts-improvements.md` → `.mcts/docs/improvements.md`
3. `.trae/rules/dev_workflow.md` → `.mcts/workflows/dev_workflow.md`

### Medium Priority (Agent Support)
1. `.taskmaster/` content → `.mcts/agents/taskmaster/`
2. `.gemini-oddity/` → `.mcts/agents/gemini/`
3. `.cursor/` → Remove (IDE-specific)

### Low Priority (Archive)
1. `archive/` → Keep for reference
2. Duplicate "copy" folders → Remove after merge

## Implementation Steps

1. **Backup current state** (just in case)
2. **Create .mcts structure**
3. **Merge and consolidate files**
4. **Update references and paths**
5. **Remove duplicates**
6. **Test universal installer**
7. **Document changes**