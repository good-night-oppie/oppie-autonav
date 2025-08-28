# Provider System for Claude-Gemini Bridge

## Overview

The provider system allows the Claude-Gemini Bridge to work with multiple AI providers beyond just Gemini. Each provider can support different authentication methods (OAuth, API keys) with automatic fallback mechanisms.

## Base Provider Interface

All providers must implement the following functions:

### Required Functions

```bash
# Authenticate with the provider
provider_authenticate "provider_name" "auth_data"

# Make an API call to the provider
provider_call "provider_name" "endpoint" "data"

# Check if provider is available
provider_health_check "provider_name"
```

### Provider Registration

```bash
# Register a new provider
register_provider "provider_name" "init_function"

# Example
register_provider "gemini-cli" "gemini_cli_init"
```

## Creating a New Provider

1. Create a new file: `hooks/providers/[provider-name]-provider.sh`
2. Source the base provider: `source "$(dirname "$0")/base-provider.sh"`
3. Implement the required functions
4. Register the provider in the init function

### Example Provider Implementation

```bash
#!/bin/bash
# ABOUTME: Example provider implementation

source "$(dirname "$0")/base-provider.sh"

# Initialize the provider
example_provider_init() {
    # Set default configuration
    set_provider_config "example" "auth_method" "api_key"
    set_provider_config "example" "api_endpoint" "https://api.example.com"
    echo "Example provider initialized"
}

# Implement authentication
example_provider_authenticate() {
    local auth_method=$(get_provider_auth_method "example")
    
    case "$auth_method" in
        "oauth")
            # OAuth flow implementation
            ;;
        "api_key")
            # API key authentication
            ;;
    esac
}

# Implement API calls
example_provider_call() {
    local endpoint="$1"
    local data="$2"
    
    # Make API call using curl or provider CLI
    curl -X POST "$endpoint" -d "$data"
}

# Implement health check
example_provider_health_check() {
    # Check if provider is reachable
    curl -s -o /dev/null -w "%{http_code}" "$(get_provider_config "example" "api_endpoint")/health"
}

# Register the provider
register_provider "example" "example_provider_init"
```

## Configuration

Provider configuration is stored in memory and can be persisted to disk if needed.

### Setting Configuration

```bash
set_provider_config "provider_name" "key" "value"

# Examples
set_provider_config "gemini-cli" "auth_method" "oauth"
set_provider_config "gemini-cli" "fallback_auth" "api_key"
```

### Getting Configuration

```bash
get_provider_config "provider_name" "key" "default_value"

# Examples
auth_method=$(get_provider_auth_method "gemini-cli")
fallback=$(get_provider_fallback_auth "gemini-cli")
```

## Authentication Methods

### OAuth Flow

1. Provider checks for existing OAuth tokens
2. If not found, initiates OAuth flow (browser-based or CLI)
3. Stores tokens securely
4. Refreshes tokens as needed

### API Key

1. Provider checks for API key in environment or config
2. Validates key with test API call
3. Uses key for all subsequent requests

### Fallback Mechanism

If primary authentication fails, the provider automatically falls back to the configured fallback method:

```bash
if ! provider_authenticate "gemini-cli" "oauth"; then
    local fallback=$(get_provider_fallback_auth "gemini-cli")
    provider_authenticate "gemini-cli" "$fallback"
fi
```

## Provider Lifecycle

1. **Registration**: Provider registers itself with the system
2. **Initialization**: Provider sets up default configuration
3. **Authentication**: Provider authenticates using configured method
4. **Operation**: Provider handles API calls
5. **Cleanup**: Provider cleans up resources if needed

## Testing Providers

Each provider should have corresponding tests in `test/unit/[provider-name]-provider_test.sh`

Example test structure:
```bash
describe "Provider Name"

test_provider_init() {
    # Test initialization
}

test_provider_auth() {
    # Test authentication methods
}

test_provider_calls() {
    # Test API calls
}

test_provider_error_handling() {
    # Test error scenarios
}
```