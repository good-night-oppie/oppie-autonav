#!/bin/bash
# ABOUTME: Base provider interface for AI provider abstraction

# Provider registry - stores provider information
declare -A PROVIDERS
declare -A PROVIDER_INIT_FUNCTIONS
declare -A PROVIDER_CONFIG

# Initialize provider system
init_provider_system() {
    # Clear any existing providers
    PROVIDERS=()
    PROVIDER_INIT_FUNCTIONS=()
    PROVIDER_CONFIG=()
}

# Register a new provider
register_provider() {
    local provider_name="$1"
    local init_function="$2"
    
    if [ -z "$provider_name" ] || [ -z "$init_function" ]; then
        echo "Error: Provider name and init function are required" >&2
        return 1
    fi
    
    PROVIDERS["$provider_name"]=1
    PROVIDER_INIT_FUNCTIONS["$provider_name"]="$init_function"
    
    return 0
}

# Check if a provider is registered
is_provider_registered() {
    local provider_name="$1"
    
    if [ "${PROVIDERS[$provider_name]}" = "1" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Initialize a provider
initialize_provider() {
    local provider_name="$1"
    
    if [ -z "$provider_name" ]; then
        echo "Error: Provider name is required" >&2
        return 1
    fi
    
    if [ "${PROVIDERS[$provider_name]}" != "1" ]; then
        echo "Error: Provider '$provider_name' is not registered" >&2
        return 1
    fi
    
    local init_function="${PROVIDER_INIT_FUNCTIONS[$provider_name]}"
    
    if ! declare -f "$init_function" > /dev/null; then
        echo "Error: Init function '$init_function' not found" >&2
        return 1
    fi
    
    # Call the init function
    "$init_function"
}

# Set provider configuration
set_provider_config() {
    local provider_name="$1"
    local key="$2"
    local value="$3"
    
    if [ -z "$provider_name" ] || [ -z "$key" ]; then
        echo "Error: Provider name and key are required" >&2
        return 1
    fi
    
    PROVIDER_CONFIG["${provider_name}_${key}"]="$value"
    return 0
}

# Get provider configuration
get_provider_config() {
    local provider_name="$1"
    local key="$2"
    local default="${3:-}"
    
    local value="${PROVIDER_CONFIG[${provider_name}_${key}]}"
    
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Get provider auth method
get_provider_auth_method() {
    local provider_name="$1"
    get_provider_config "$provider_name" "auth_method" "api_key"
}

# Get provider fallback auth method
get_provider_fallback_auth() {
    local provider_name="$1"
    get_provider_config "$provider_name" "fallback_auth" ""
}

# Validate a provider
validate_provider() {
    local provider_name="$1"
    
    if [ -z "$provider_name" ]; then
        echo "false"
        return 1
    fi
    
    is_provider_registered "$provider_name"
}

# List all registered providers
list_providers() {
    local providers=""
    
    for provider in "${!PROVIDERS[@]}"; do
        if [ "${PROVIDERS[$provider]}" = "1" ]; then
            providers="${providers}${provider}\n"
        fi
    done
    
    echo -e "$providers" | sed '/^$/d' | sort
}

# Clear all providers
clear_providers() {
    init_provider_system
}

# Format provider response into standard format
format_provider_response() {
    local raw_response="$1"
    
    # For now, just extract text from JSON response
    # This can be enhanced based on provider-specific needs
    if echo "$raw_response" | grep -q '"text"'; then
        echo "$raw_response" | sed 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
    else
        echo "$raw_response"
    fi
}

# ============================================================================
# PROVIDER FACTORY PATTERN
# ============================================================================

# Get provider instance based on configuration
# Usage: get_provider "provider_name_or_type"
# Returns: Provider name that should be used
get_provider() {
    local requested_provider="$1"
    
    # Check if provider is registered
    if [ "$(is_provider_registered "$requested_provider")" = "true" ]; then
        echo "$requested_provider"
        return 0
    fi
    
    # Try to find a provider by type (oauth, api_key, etc)
    local provider_type="$requested_provider"
    for provider in "${!PROVIDERS[@]}"; do
        if [ "${PROVIDERS[$provider]}" = "1" ]; then
            local auth_method=$(get_provider_auth_method "$provider")
            if [ "$auth_method" = "$provider_type" ]; then
                echo "$provider"
                return 0
            fi
        fi
    done
    
    # No matching provider found
    echo ""
    return 1
}

# Create provider instance and initialize it
# Usage: create_provider_instance "provider_name" "config_file"
# Returns: 0 on success, 1 on failure
create_provider_instance() {
    local provider_name="$1"
    local config_file="${2:-}"
    
    if [ -z "$provider_name" ]; then
        echo "Error: Provider name is required" >&2
        return 1
    fi
    
    # Load provider script if it exists
    local provider_script="$(dirname "${BASH_SOURCE[0]}")/${provider_name}-provider.sh"
    if [ -f "$provider_script" ]; then
        source "$provider_script"
    fi
    
    # Initialize the provider
    if ! initialize_provider "$provider_name"; then
        echo "Error: Failed to initialize provider '$provider_name'" >&2
        return 1
    fi
    
    # Load configuration if provided
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        if declare -f "${provider_name}_load_config" > /dev/null; then
            "${provider_name}_load_config" "$config_file"
        fi
    fi
    
    return 0
}

# Execute provider method with automatic fallback
# Usage: execute_provider_method "provider_name" "method_name" [args...]
# Returns: 0 on success, 1 on failure
execute_provider_method() {
    local provider_name="$1"
    local method_name="$2"
    shift 2
    
    # Try primary provider
    local provider_function="provider_${method_name}"
    if declare -f "$provider_function" > /dev/null; then
        if "$provider_function" "$provider_name" "$@"; then
            return 0
        fi
    fi
    
    # Try fallback provider if configured
    local fallback_provider=$(get_provider_config "$provider_name" "fallback_provider" "")
    if [ -n "$fallback_provider" ] && [ "$fallback_provider" != "$provider_name" ]; then
        if "$provider_function" "$fallback_provider" "$@"; then
            return 0
        fi
    fi
    
    return 1
}

# Select best provider based on requirements
# Usage: select_best_provider "requirements_json"
# Returns: Best matching provider name
select_best_provider() {
    local requirements="${1:-{}}"
    local best_provider=""
    local best_score=0
    
    for provider in "${!PROVIDERS[@]}"; do
        if [ "${PROVIDERS[$provider]}" != "1" ]; then
            continue
        fi
        
        local score=0
        
        # Check if provider is healthy
        if provider_validate_auth "$provider" > /dev/null 2>&1; then
            score=$((score + 10))
        fi
        
        # Check capabilities match
        local capabilities=$(provider_get_capabilities "$provider" 2>/dev/null)
        if [ -n "$capabilities" ]; then
            score=$((score + 5))
            
            # Additional scoring based on capabilities
            # This can be enhanced based on specific requirements
            if echo "$capabilities" | grep -q '"streaming":true'; then
                score=$((score + 2))
            fi
            if echo "$capabilities" | grep -q '"max_tokens":[0-9]\{6,\}'; then
                score=$((score + 3))
            fi
        fi
        
        # Check rate limit status
        local rate_limit=$(provider_rate_limit_check "$provider" 2>/dev/null)
        if echo "$rate_limit" | grep -q '"status":"ok"'; then
            score=$((score + 5))
        fi
        
        if [ $score -gt $best_score ]; then
            best_score=$score
            best_provider="$provider"
        fi
    done
    
    echo "$best_provider"
}

# Provider interface functions that must be implemented by each provider

# ============================================================================
# REQUIRED METHODS - All providers must implement these
# ============================================================================

# Required: Authenticate with the provider
# Usage: ${provider_name}_authenticate "auth_data"
# Returns: 0 on success, 1 on failure
# Output: Authentication token or session info
provider_authenticate() {
    local provider_name="$1"
    shift
    
    local auth_function="${provider_name}_authenticate"
    if declare -f "$auth_function" > /dev/null; then
        "$auth_function" "$@"
    else
        echo "Error: Provider '$provider_name' must implement ${auth_function}" >&2
        return 1
    fi
}

# Required: Execute a request to the provider
# Usage: ${provider_name}_execute_request "endpoint" "data"
# Returns: 0 on success, 1 on failure
# Output: Response from provider
provider_execute_request() {
    local provider_name="$1"
    shift
    
    local exec_function="${provider_name}_execute_request"
    if declare -f "$exec_function" > /dev/null; then
        "$exec_function" "$@"
    else
        echo "Error: Provider '$provider_name' must implement ${exec_function}" >&2
        return 1
    fi
}

# Required: Validate authentication status
# Usage: ${provider_name}_validate_auth
# Returns: 0 if authenticated, 1 if not
# Output: "valid" or "invalid"
provider_validate_auth() {
    local provider_name="$1"
    
    local validate_function="${provider_name}_validate_auth"
    if declare -f "$validate_function" > /dev/null; then
        "$validate_function"
    else
        echo "Error: Provider '$provider_name' must implement ${validate_function}" >&2
        return 1
    fi
}

# Required: Get provider capabilities
# Usage: ${provider_name}_get_capabilities
# Returns: 0 on success
# Output: JSON string with provider capabilities
provider_get_capabilities() {
    local provider_name="$1"
    
    local capabilities_function="${provider_name}_get_capabilities"
    if declare -f "$capabilities_function" > /dev/null; then
        "$capabilities_function"
    else
        echo "Error: Provider '$provider_name' must implement ${capabilities_function}" >&2
        return 1
    fi
}

# ============================================================================
# OPTIONAL METHODS - Providers can implement these for additional functionality
# ============================================================================

# Optional: Refresh authentication token
# Usage: ${provider_name}_refresh_auth
# Returns: 0 on success, 1 on failure
# Output: New authentication token
provider_refresh_auth() {
    local provider_name="$1"
    
    local refresh_function="${provider_name}_refresh_auth"
    if declare -f "$refresh_function" > /dev/null; then
        "$refresh_function"
    else
        # Not an error - this is optional
        return 1
    fi
}

# Optional: Cache provider response
# Usage: ${provider_name}_cache_response "key" "response" "ttl"
# Returns: 0 on success, 1 on failure
provider_cache_response() {
    local provider_name="$1"
    shift
    
    local cache_function="${provider_name}_cache_response"
    if declare -f "$cache_function" > /dev/null; then
        "$cache_function" "$@"
    else
        # Not an error - this is optional
        return 1
    fi
}

# Optional: Check rate limit status
# Usage: ${provider_name}_rate_limit_check
# Returns: 0 if within limits, 1 if rate limited
# Output: JSON with rate limit info
provider_rate_limit_check() {
    local provider_name="$1"
    
    local rate_limit_function="${provider_name}_rate_limit_check"
    if declare -f "$rate_limit_function" > /dev/null; then
        "$rate_limit_function"
    else
        # Not an error - this is optional
        echo '{"status":"unknown"}'
        return 0
    fi
}

# Initialize the provider system on source
init_provider_system