# ADR-001: Universal Installer Strategy for oppie-autonav

**Date**: 2025-09-06  
**Status**: Accepted  
**Context**: Migration analysis from oppie-thunder to oppie-autonav  
**Decision Makers**: Development Team  

## Executive Summary

After comprehensive analysis of oppie-thunder's CI/CD system and oppie-autonav's architecture, we've determined that oppie-autonav should remain a **universal, project-agnostic automation tool** rather than inheriting project-specific workflows. The focus should be on enhancing its intelligent installation and auto-configuration capabilities.

## Context

### The Challenge
- oppie-thunder has sophisticated CI/CD monitoring, TDD workflows, and GitHub Actions
- Initial request was to migrate these components to oppie-autonav
- Need to determine what should be migrated vs. what should be reimagined

### Key Findings
1. **oppie-autonav's Purpose**: Already designed as a universal automation suite for ANY project
2. **Current Architecture**: Has a menu-driven installer with multiple modes
3. **oppie-thunder's CI/CD**: Highly specific to Go/Wails architecture

## Decision Framework: 3-Lens Analysis

### Graham Lens (Product-Market Fit) 🏆
**Question**: Will complex GitHub Actions create user delight or confusion?

**Analysis**:
- Users want one-command install that "just works"
- Current menu-driven installer is good but could be smarter
- Clear value prop: Automates PR reviews and CI monitoring

**Verdict**: Current approach good, but needs **intelligence not complexity**

### Hassabis Lens (AI Evolution) 🧠
**Question**: Should the system learn and adapt to different projects?

**Analysis**:
- System should detect project type automatically
- Could learn from usage patterns across projects
- Intelligence in auto-configuration creates competitive moat

**Verdict**: Add **project detection intelligence**

### Musk Lens (Execution Minimalism) 🚀
**Question**: What's the minimum viable mechanism for 80% value?

**Analysis**:
- Single command `curl | bash` style installer
- Auto-detect instead of asking questions
- Zero-config for common cases

**Verdict**: **Simplify to single-command with smart defaults**

## Decision

### What We Will NOT Do ❌
1. **NOT migrate oppie-thunder's GitHub Actions** - Too project-specific
2. **NOT create cookie-cutter templates** - Inflexible
3. **NOT build complex installation wizards** - Too much friction

### What We WILL Do ✅
1. **Enhance installer with project type detection**
2. **Create adaptive CI/CD templates** that adjust to detected stack
3. **Build one-liner installer** for zero-friction adoption
4. **Add npx/pip/cargo support** for language-specific distribution

## Implementation Strategy

### Phase 1: Smart Project Detection
```bash
detect_project_type() {
    # Node.js project
    [ -f package.json ] && echo "node"
    # Python project  
    [ -f requirements.txt ] || [ -f pyproject.toml ] && echo "python"
    # Go project
    [ -f go.mod ] && echo "go"
    # Rust project
    [ -f Cargo.toml ] && echo "rust"
}
```

### Phase 2: Adaptive Configuration
- Generate appropriate hooks based on project type
- Install relevant GitHub Actions templates
- Configure language-specific tools

### Phase 3: Distribution Channels
```bash
# Universal installer
curl -sSL https://oppie.xyz/install | bash

# Language-specific
npx oppie-autonav init      # Node.js
pip install oppie-autonav    # Python
cargo install oppie-autonav  # Rust
go install oppie-autonav     # Go
```

## Migration Summary

### ✅ Already Migrated (Keep)
- Monitor daemon binary and service
- Git push monitoring scripts
- PR monitoring documentation

### ❌ Not Migrating (Project-Specific)
- oppie-thunder's `.github/workflows/`
- TDD scripts with hardcoded paths
- Makefile targets
- Task-master integrations

### 🆕 New Enhancements (Build)
- Intelligent project type detection
- Adaptive workflow generation
- CDN-hosted one-liner installer
- Language-specific distribution channels

## Metrics for Success

1. **Installation Time**: < 30 seconds from zero to working
2. **User Actions Required**: 1 command for 80% of cases
3. **Project Type Coverage**: Support 90% of popular stacks
4. **Configuration Accuracy**: 95% correct auto-detection

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Auto-detection failures | Fallback to manual selection |
| Too many project types | Focus on top 5 initially |
| Breaking changes | Semantic versioning |
| Complexity creep | Regular minimalism reviews |

## References

- oppie-autonav README: Project goals and architecture
- oppie-thunder CLAUDE.md: CI/CD implementation details
- 3-Lens Decision Model: `.claude/PRINCIPLES.md`

## Conclusion

By focusing on **intelligence over complexity**, oppie-autonav can achieve its goal of being a universal automation tool that works with ANY project. The key insight is that we don't need to migrate project-specific workflows; instead, we need to build a system smart enough to generate appropriate workflows for each project type.

This approach follows the minimalism principle: achieve breakthrough capability (universal compatibility) with minimal complexity (one command, zero config).

---

**Next Review Date**: Q2 2025  
**Review Triggers**: 
- User adoption metrics available
- New project type requests
- Competitive landscape changes