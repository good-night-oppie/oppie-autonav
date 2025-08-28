# Library Functions for Claude-Gemini Bridge

## OAuth Handler (`oauth-handler.sh`)

The OAuth handler provides secure token management for OAuth-based authentication with AI providers.

### Features

- Secure token storage with proper file permissions (600)
- Token refresh with automatic expiry checking
- Multi-provider token management
- OAuth flow initiation with browser support
- Authorization code exchange
- Token validation and expiry checking

### Usage

```bash
# Source the OAuth handler
source "hooks/lib/oauth-handler.sh"

# Store tokens
store_oauth_token "gemini-cli" "access-token-123" "refresh-token-456" 3600

# Get access token
access_token=$(get_oauth_token "gemini-cli")

# Check if token is expired
if is_token_expired "gemini-cli"; then
    # Refresh the token
    new_token=$(refresh_oauth_token "gemini-cli" "gemini_refresh_function")
fi

# Get valid token (auto-refresh if needed)
token=$(get_valid_oauth_token "gemini-cli" "gemini_refresh_function")

# Initiate OAuth flow
state=$(initiate_oauth_flow "https://accounts.google.com/o/oauth2/v2/auth" \
    "client-id" "http://localhost:8080/callback" "https://www.googleapis.com/auth/generative-ai")

# Handle OAuth callback
auth_code=$(handle_oauth_callback "code=4/0AX4XfWh...&state=random-state")

# Exchange code for tokens
tokens=$(exchange_code_for_token "$auth_code" "client-id" "client-secret")

# List all stored tokens
list_oauth_tokens

# Delete a token
delete_oauth_token "gemini-cli"
```

### Token Storage

Tokens are stored in `~/.claude-gemini-bridge/oauth/` by default. Each provider has its own token file:

```
~/.claude-gemini-bridge/oauth/
├── gemini-cli.token
├── openai.token
└── anthropic.token
```

Token files are JSON formatted:
```json
{
    "access_token": "ya29.a0AfH...",
    "refresh_token": "1//0eH...",
    "expires_at": 1701234567,
    "provider": "gemini-cli"
}
```

### Security

- Token directory has 700 permissions (owner read/write/execute only)
- Token files have 600 permissions (owner read/write only)
- Tokens are never logged or displayed in debug output
- Refresh tokens are stored separately from access tokens

### Environment Variables

- `OAUTH_TOKEN_DIR`: Override default token storage directory

### Error Handling

All functions return appropriate error codes and messages:
- Missing required parameters
- Token not found
- Expired tokens
- Failed refresh attempts
- Invalid token formats

## Other Library Functions

### Debug Helpers (`debug-helpers.sh`)
Provides logging and debugging utilities.

### JSON Parser (`json-parser.sh`)
Simple JSON parsing for shell scripts.

### Path Converter (`path-converter.sh`)
Converts Claude's `@` notation to absolute paths.

### Gemini Wrapper (`gemini-wrapper.sh`)
Wrapper for Gemini CLI integration.