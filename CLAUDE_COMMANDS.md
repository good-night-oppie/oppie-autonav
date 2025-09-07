# Claude Code Commands Reference

## CLI Commands (from terminal)

```bash
# Basic usage
claude                           # Start interactive session
claude -p "prompt"              # Print response and exit
claude -c                       # Continue most recent conversation
claude -r [sessionId]           # Resume a conversation

# Options
--debug                         # Enable debug mode
--verbose                       # Override verbose mode
--print                         # Print response and exit
--output-format <format>        # Output format: text, json, stream-json
--input-format <format>         # Input format: text, stream-json
--dangerously-skip-permissions  # Bypass permission checks (sandbox only)
--allowedTools <tools...>       # Allow specific tools
--disallowedTools <tools...>    # Deny specific tools
--mcp-config <configs...>       # Load MCP servers
--append-system-prompt <prompt> # Append to system prompt
--permission-mode <mode>        # acceptEdits, bypassPermissions, default, plan
--model <model>                 # Choose model (sonnet, opus, etc)
--fallback-model <model>        # Fallback when overloaded
--settings <file-or-json>       # Load settings
--add-dir <directories...>      # Additional directories for tool access
--ide                           # Auto-connect to IDE
--strict-mcp-config             # Only use specified MCP servers
--session-id <uuid>             # Use specific session ID

# Management commands
claude config                   # Manage configuration
claude mcp                      # Configure MCP servers
claude migrate-installer        # Migrate from global to local
claude setup-token              # Set up auth token
claude doctor                   # Check health
claude update                   # Check/install updates
claude install [target]         # Install native build
```

## Interactive Session Commands (within Claude)

### Session Management
- `/clear` - Clear context and start fresh
- `/exit` or `/quit` - Exit the session
- `/resume [sessionId]` - Resume a previous conversation
- `/continue` - Continue most recent conversation

### Context & Information
- `/help` - Show available commands
- `/context` - Show current context information
- `/session` - Display session details
- `/tools` - List available tools

### Task Management
- `/todo` - View and manage todo list
- `/spawn` - Create parallel tasks
- `/task` - Task management commands

### Project & Files
- `/load` - Load project context
- `/index` - Index project for better understanding
- `/project` - Project-specific commands
- `/workspace` - Workspace management

### Development Workflow
- `/build` - Build project
- `/test` - Run tests
- `/analyze` - Analyze code
- `/implement` - Implement features
- `/improve` - Improve code quality
- `/troubleshoot` - Debug issues
- `/explain` - Explain code/concepts
- `/document` - Generate documentation
- `/cleanup` - Clean up code
- `/estimate` - Estimate effort
- `/git` - Git operations
- `/design` - Design features

### MCP & Integrations
- `/mcp` - MCP server management
- `/ide` - IDE integration commands

### Settings & Configuration
- `/settings` - Adjust session settings
- `/permissions` - Manage tool permissions
- `/config` - Configuration management

### Special Modes
- `/plan` - Enter planning mode
- `/execute` - Execute planned actions
- `/wave` - Wave orchestration mode
- `/introspect` - Introspection mode

## Tool Permission Formats

```bash
# Examples of tool permissions
"Edit"                          # Allow all Edit operations
"Bash(git:*)"                   # Allow all git commands
"Bash(npm run *)"               # Allow npm run commands
"Read(*.js)"                    # Allow reading JS files
"Write(/tmp/*)"                 # Allow writing to /tmp
"mcp__task-master-ai__*"        # Allow all TaskMaster MCP tools
```

## Common Workflows

### Start new feature
```bash
claude -p "implement authentication feature"
# or interactively:
claude
> /load
> /implement authentication system
```

### Resume work
```bash
claude -c                       # Continue last session
claude -r                       # Select session to resume
```

### Quick fixes
```bash
claude -p "fix the bug in auth.js line 45"
```

### Planning mode
```bash
claude --permission-mode plan
> /plan implement OAuth2
> /execute
```

### With MCP servers
```bash
claude --mcp-config .mcp.json
> /mcp list                    # List active servers
> /mcp restart task-master-ai  # Restart a server
```

## TaskMaster Integration

When TaskMaster MCP is active, additional commands become available:
- `/project:tm/init` - Initialize TaskMaster
- `/project:tm/parse-prd` - Parse PRD document
- `/project:tm/next` - Get next task
- `/project:tm/list` - List tasks
- `/project:tm/status` - Show status
- `/project:tm/expand` - Expand tasks

## Environment Variables

```bash
# API Keys
export ANTHROPIC_API_KEY=sk-...
export OPENAI_API_KEY=sk-...
export PERPLEXITY_API_KEY=pplx-...

# Claude settings
export CLAUDE_LOG_LEVEL=debug
export CLAUDE_HOME=~/.claude
```

## Configuration Files

- `~/.claude/settings.json` - Global settings
- `.claude/settings.json` - Project settings
- `.mcp.json` - MCP server configuration
- `.env` - Environment variables
- `CLAUDE.md` - Project context (auto-loaded)

---

_Generated from Claude Code help system_