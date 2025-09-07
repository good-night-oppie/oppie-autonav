# Agent Instructions & Enhanced TDD Workflow

## 🔬 MANDATORY Research-First Development

### Core Principle: Research → Red → Green → Refactor → Validate

**CRITICAL**: Every task MUST begin with a comprehensive research phase before any implementation.

### Research Phase Protocol (Required)

When setting any task to `in-progress`, automatically execute parallel research:

```bash
# Triggered by:
task-master set-status --id=X.Y --status=in-progress

# Parallel Research Tools (MUST USE ALL):
1. Context7 (mcp__context7__*) - Official docs, API refs, framework guides
2. DeepWiki (mcp__deepwiki__*) - Technical concepts, algorithms, data structures  
3. Exa Deep Research (mcp__exa__deep_researcher_*) - Industry best practices, case studies
```

### Research Focus Areas:
- **Architecture**: Design patterns, system architecture, component relationships
- **Performance**: Optimization techniques, benchmarks, bottlenecks to avoid
- **Security**: Vulnerabilities, authentication, authorization, data protection
- **Testing**: Test strategies, edge cases, property-based testing approaches
- **Best Practices**: Industry standards, common patterns, anti-patterns to avoid

### Research Documentation:
```bash
# Record findings to task BEFORE implementation
task-master update-subtask --id=X.Y --prompt="
Research Findings:
- Architecture: [key patterns discovered]
- Performance: [optimization opportunities]
- Security: [considerations identified]
- Testing: [strategies to implement]
- Risks: [potential issues to avoid]
"
```

## Task Master AI Instructions
**Import Task Master's development workflow commands and guidelines, treat as if import is in the main AGENT.md file.**
@./.taskmaster/AGENT.md

## Clean Room Development Constraints

### RED TEAM Implementation Rules
- ❌ **NEVER reference blue_team/** directory or files
- ❌ **NO access to existing implementations** marked as _OLD
- ✅ **ONLY use**: Behavior specifications, interface definitions, TDD_GUIDE.md
- ✅ **Follow TDD religiously**: Research → Red → Green → Refactor → Validate
- ✅ **Maintain ≥85% test coverage**: Core packages require 100%

### Mandatory Validation
```bash
# Before marking any task complete:
make test-go cover-check-go test-ts
./scripts/tdd-guard.sh --wait
task-master set-status --id=X.Y --status=done
```

## AI Agent Operational Guidelines

### When Starting ANY Implementation Task:

1. **RESEARCH PHASE** (Mandatory):
   ```bash
   task-master set-status --id=X.Y --status=in-progress
   # Automatically triggers parallel research
   # Wait for research completion before proceeding
   ```

2. **Document Research Findings**:
   ```bash
   task-master update-subtask --id=X.Y --prompt="[research summary]"
   ```

3. **RED Phase** - Write comprehensive tests based on research
4. **GREEN Phase** - Implement using research insights
5. **REFACTOR Phase** - Apply discovered patterns
6. **VALIDATE Phase** - Verify against research criteria

### Knowledge Persistence

All research findings are:
- Logged to task history for future reference
- Used to build institutional knowledge
- Available for similar future tasks
- Part of project documentation

## Integration with Claude Code

### Hooks & Automation
- `.claude/hooks/task-in-progress-research.sh` - Auto-triggers research
- `.claude/RESEARCH_WORKFLOW.md` - Detailed workflow documentation
- Research findings automatically logged to TaskMaster

### Benefits of Research-First Approach
1. **Reduced Rework**: Discover issues before implementation
2. **Better Architecture**: Informed design decisions
3. **Security by Design**: Vulnerabilities identified early
4. **Performance Optimization**: Know bottlenecks upfront
5. **Knowledge Transfer**: Research logged for team learning

---

*This enhanced workflow is mandatory for all development tasks. No exceptions.*
