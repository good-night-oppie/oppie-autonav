#!/bin/bash
# ABOUTME: Secure token storage manager with encrypted file-based storage

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "$SCRIPT_DIR/encryption-core.sh"

# Storage configuration
TOKEN_STORAGE_DIR="${TOKEN_STORAGE_DIR:-$HOME/.claude-gemini-bridge/auth}"
TOKEN_FILE="${TOKEN_FILE:-$TOKEN_STORAGE_DIR/encrypted_tokens.dat}"
TOKEN_BACKUP_FILE="${TOKEN_BACKUP_FILE:-$TOKEN_STORAGE_DIR/encrypted_tokens.bak}"
TOKEN_LOCK_FILE="${TOKEN_LOCK_FILE:-$TOKEN_STORAGE_DIR/.tokens.lock}"
TOKEN_METADATA_FILE="${TOKEN_METADATA_FILE:-$TOKEN_STORAGE_DIR/token_metadata.json}"

# Security settings
if [ -z "$FILE_PERMS" ]; then
    readonly FILE_PERMS="600"
    readonly DIR_PERMS="700"
    readonly LOCK_TIMEOUT=30
    readonly MAX_LOCK_WAIT=60
    # Token expiry buffer (5 minutes)
    readonly EXPIRY_BUFFER=300
fi

# ============================================================================
# Initialization and Setup
# ============================================================================

# Initialize token storage system
init_token_storage() {
    # Create storage directory with secure permissions
    if [ ! -d "$TOKEN_STORAGE_DIR" ]; then
        mkdir -p "$TOKEN_STORAGE_DIR"
        chmod "$DIR_PERMS" "$TOKEN_STORAGE_DIR"
        
        # Verify permissions were set correctly
        local actual_perms=$(stat -c %a "$TOKEN_STORAGE_DIR" 2>/dev/null || stat -f %A "$TOKEN_STORAGE_DIR" 2>/dev/null)
        if [[ "$actual_perms" != *"700"* ]] && [[ "$actual_perms" != "700" ]]; then
            echo "Warning: Failed to set secure permissions on token directory" >&2
        fi
    fi
    
    # Initialize encryption system
    if ! init_encryption; then
        echo "Error: Failed to initialize encryption system" >&2
        return 1
    fi
    
    return 0
}

# ============================================================================
# Lock Management
# ============================================================================

# Acquire lock for token operations
acquire_lock() {
    local timeout="${1:-$LOCK_TIMEOUT}"
    local wait_time=0
    
    # Try to acquire lock with timeout
    while [ $wait_time -lt "$MAX_LOCK_WAIT" ]; do
        if mkdir "$TOKEN_LOCK_FILE" 2>/dev/null; then
            # Write PID to lock file
            echo $$ > "$TOKEN_LOCK_FILE/pid"
            
            # Set cleanup trap
            trap release_lock EXIT
            return 0
        fi
        
        # Check if lock is stale
        if [ -f "$TOKEN_LOCK_FILE/pid" ]; then
            local lock_pid=$(cat "$TOKEN_LOCK_FILE/pid" 2>/dev/null)
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Lock is stale, remove it
                echo "Removing stale lock from PID $lock_pid" >&2
                rm -rf "$TOKEN_LOCK_FILE"
                continue
            fi
        fi
        
        # Wait and retry
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    echo "Error: Failed to acquire lock after $MAX_LOCK_WAIT seconds" >&2
    return 1
}

# Release lock
release_lock() {
    if [ -d "$TOKEN_LOCK_FILE" ]; then
        local lock_pid=$(cat "$TOKEN_LOCK_FILE/pid" 2>/dev/null)
        if [ "$lock_pid" = "$$" ]; then
            rm -rf "$TOKEN_LOCK_FILE"
        fi
    fi
}

# ============================================================================
# Token Storage Functions
# ============================================================================

# Store token securely
store_token() {
    local provider="$1"
    local token_type="$2"
    local token_value="$3"
    local expires_at="${4:-}"
    local refresh_token="${5:-}"
    local scope="${6:-}"
    
    if [ -z "$provider" ] || [ -z "$token_type" ] || [ -z "$token_value" ]; then
        echo "Error: Provider, token type, and token value required" >&2
        return 1
    fi
    
    # Initialize storage if needed
    init_token_storage || return 1
    
    # Acquire lock
    if ! acquire_lock; then
        echo "Error: Could not acquire lock for token storage" >&2
        return 1
    fi
    
    # Create token data structure
    local token_data=$(cat <<EOF
{
  "provider": "$provider",
  "type": "$token_type",
  "token": "$token_value",
  "refresh_token": "$refresh_token",
  "expires_at": "$expires_at",
  "scope": "$scope",
  "stored_at": "$(date -Iseconds)",
  "stored_by": "$USER",
  "machine_id": "$(get_machine_key)"
}
EOF
)
    
    # Load existing tokens if file exists
    local all_tokens="{}"
    if [ -f "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
        local encrypted_data=$(cat "$TOKEN_FILE")
        local decrypted=$(decrypt_data "$encrypted_data" 2>/dev/null)
        if [ -n "$decrypted" ]; then
            all_tokens="$decrypted"
        fi
    fi
    
    # Add/update token for provider
    local updated_tokens
    if command -v jq &>/dev/null; then
        updated_tokens=$(echo "$all_tokens" | jq ".\"$provider\" = $token_data")
    else
        # Fallback: simple replacement (less reliable)
        updated_tokens="{\"$provider\": $token_data}"
    fi
    
    # Create backup of existing file
    if [ -f "$TOKEN_FILE" ]; then
        cp -p "$TOKEN_FILE" "$TOKEN_BACKUP_FILE"
    fi
    
    # Encrypt and save tokens
    local encrypted=$(encrypt_data "$updated_tokens")
    if [ $? -ne 0 ]; then
        echo "Error: Failed to encrypt token data" >&2
        release_lock
        return 1
    fi
    
    # Atomic write using temp file
    local temp_file="$TOKEN_FILE.tmp.$$"
    echo "$encrypted" > "$temp_file"
    chmod "$FILE_PERMS" "$temp_file"
    
    # Verify permissions before moving
    local actual_perms=$(stat -c %a "$temp_file" 2>/dev/null || stat -f %A "$temp_file" 2>/dev/null)
    if [[ "$actual_perms" != *"600"* ]] && [[ "$actual_perms" != "600" ]]; then
        echo "Warning: Failed to set secure permissions on token file" >&2
    fi
    
    # Atomic move
    mv -f "$temp_file" "$TOKEN_FILE"
    
    # Update metadata
    update_token_metadata "$provider" "$token_type" "$expires_at"
    
    release_lock
    return 0
}

# Retrieve token
retrieve_token() {
    local provider="$1"
    local token_field="${2:-token}"
    
    if [ -z "$provider" ]; then
        echo "Error: Provider required" >&2
        return 1
    fi
    
    # Check if token file exists
    if [ ! -f "$TOKEN_FILE" ] || [ ! -s "$TOKEN_FILE" ]; then
        echo "Error: No tokens stored" >&2
        return 1
    fi
    
    # Acquire lock for reading
    if ! acquire_lock 5; then
        echo "Error: Could not acquire lock for token retrieval" >&2
        return 1
    fi
    
    # Decrypt tokens
    local encrypted_data=$(cat "$TOKEN_FILE")
    local decrypted=$(decrypt_data "$encrypted_data" 2>/dev/null)
    
    if [ -z "$decrypted" ]; then
        echo "Error: Failed to decrypt token data" >&2
        release_lock
        return 1
    fi
    
    # Extract token for provider
    local token_data
    if command -v jq &>/dev/null; then
        token_data=$(echo "$decrypted" | jq -r ".\"$provider\".\"$token_field\" // empty")
    else
        # Fallback: grep extraction
        token_data=$(echo "$decrypted" | grep -o "\"$provider\".*\"$token_field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | \
                     grep -o "\"$token_field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4)
    fi
    
    release_lock
    
    if [ -z "$token_data" ]; then
        echo "Error: No token found for provider: $provider" >&2
        return 1
    fi
    
    echo "$token_data"
    return 0
}

# Delete token
delete_token() {
    local provider="$1"
    
    if [ -z "$provider" ]; then
        echo "Error: Provider required" >&2
        return 1
    fi
    
    # Check if token file exists
    if [ ! -f "$TOKEN_FILE" ]; then
        return 0  # Nothing to delete
    fi
    
    # Acquire lock
    if ! acquire_lock; then
        echo "Error: Could not acquire lock for token deletion" >&2
        return 1
    fi
    
    # Decrypt tokens
    local encrypted_data=$(cat "$TOKEN_FILE")
    local decrypted=$(decrypt_data "$encrypted_data" 2>/dev/null)
    
    if [ -z "$decrypted" ]; then
        echo "Error: Failed to decrypt token data" >&2
        release_lock
        return 1
    fi
    
    # Remove token for provider
    local updated_tokens
    if command -v jq &>/dev/null; then
        updated_tokens=$(echo "$decrypted" | jq "del(.\"$provider\")")
    else
        # Fallback: skip this provider (less reliable)
        echo "Warning: jq not available, token deletion may be incomplete" >&2
        updated_tokens="{}"
    fi
    
    # Create backup before deletion
    cp -p "$TOKEN_FILE" "$TOKEN_BACKUP_FILE"
    
    # If no tokens left, remove file
    if [ "$updated_tokens" = "{}" ] || [ "$updated_tokens" = "null" ]; then
        shred -vfz -n 3 "$TOKEN_FILE" 2>/dev/null || rm -f "$TOKEN_FILE"
    else
        # Re-encrypt and save
        local encrypted=$(encrypt_data "$updated_tokens")
        if [ $? -eq 0 ]; then
            echo "$encrypted" > "$TOKEN_FILE"
            chmod "$FILE_PERMS" "$TOKEN_FILE"
        fi
    fi
    
    # Update metadata
    remove_token_metadata "$provider"
    
    release_lock
    return 0
}

# ============================================================================
# Token Metadata Management
# ============================================================================

# Update token metadata
update_token_metadata() {
    local provider="$1"
    local token_type="$2"
    local expires_at="$3"
    
    local metadata="{}"
    if [ -f "$TOKEN_METADATA_FILE" ]; then
        metadata=$(cat "$TOKEN_METADATA_FILE" 2>/dev/null || echo "{}")
    fi
    
    # Update metadata
    if command -v jq &>/dev/null; then
        metadata=$(echo "$metadata" | jq ".\"$provider\" = {
            \"type\": \"$token_type\",
            \"expires_at\": \"$expires_at\",
            \"last_updated\": \"$(date -Iseconds)\"
        }")
    else
        # Simple format without jq
        metadata="{\"$provider\": {\"type\": \"$token_type\", \"expires_at\": \"$expires_at\", \"last_updated\": \"$(date -Iseconds)\"}}"
    fi
    
    echo "$metadata" > "$TOKEN_METADATA_FILE"
    chmod "$FILE_PERMS" "$TOKEN_METADATA_FILE"
}

# Remove token metadata
remove_token_metadata() {
    local provider="$1"
    
    if [ ! -f "$TOKEN_METADATA_FILE" ]; then
        return 0
    fi
    
    local metadata=$(cat "$TOKEN_METADATA_FILE")
    
    if command -v jq &>/dev/null; then
        metadata=$(echo "$metadata" | jq "del(.\"$provider\")")
        echo "$metadata" > "$TOKEN_METADATA_FILE"
    fi
}

# Check token expiration
is_token_expired() {
    local provider="$1"
    local buffer="${2:-$EXPIRY_BUFFER}"
    
    # Get token expiration from metadata
    if [ ! -f "$TOKEN_METADATA_FILE" ]; then
        return 0  # Assume expired if no metadata
    fi
    
    local expires_at
    if command -v jq &>/dev/null; then
        expires_at=$(cat "$TOKEN_METADATA_FILE" | jq -r ".\"$provider\".expires_at // empty")
    else
        expires_at=$(cat "$TOKEN_METADATA_FILE" | grep -o "\"$provider\".*expires_at.*\"[^\"]*\"" | \
                     grep -o "\"expires_at\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4)
    fi
    
    if [ -z "$expires_at" ]; then
        return 0  # No expiration info, assume valid
    fi
    
    # Convert to timestamp
    local expiry_timestamp=$(date -d "$expires_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$expires_at" +%s 2>/dev/null)
    local current_timestamp=$(date +%s)
    local buffered_timestamp=$((current_timestamp + buffer))
    
    if [ "$buffered_timestamp" -ge "$expiry_timestamp" ]; then
        return 0  # Token is expired or will expire within buffer
    else
        return 1  # Token is still valid
    fi
}

# ============================================================================
# Utility Functions
# ============================================================================

# List all stored token providers
list_token_providers() {
    if [ ! -f "$TOKEN_FILE" ] || [ ! -s "$TOKEN_FILE" ]; then
        return 0
    fi
    
    # Decrypt tokens
    local encrypted_data=$(cat "$TOKEN_FILE")
    local decrypted=$(decrypt_data "$encrypted_data" 2>/dev/null)
    
    if [ -z "$decrypted" ]; then
        echo "Error: Failed to decrypt token data" >&2
        return 1
    fi
    
    # List providers
    if command -v jq &>/dev/null; then
        echo "$decrypted" | jq -r 'keys[]'
    else
        echo "$decrypted" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*{' | cut -d'"' -f2
    fi
}

# Validate token storage integrity
validate_token_storage() {
    # Check directory permissions
    if [ -d "$TOKEN_STORAGE_DIR" ]; then
        local dir_perms=$(stat -c %a "$TOKEN_STORAGE_DIR" 2>/dev/null || stat -f %A "$TOKEN_STORAGE_DIR" 2>/dev/null)
        if [[ "$dir_perms" != *"700"* ]] && [[ "$dir_perms" != "700" ]]; then
            echo "Warning: Token directory has insecure permissions: $dir_perms" >&2
        fi
    fi
    
    # Check file permissions
    if [ -f "$TOKEN_FILE" ]; then
        local file_perms=$(stat -c %a "$TOKEN_FILE" 2>/dev/null || stat -f %A "$TOKEN_FILE" 2>/dev/null)
        if [[ "$file_perms" != *"600"* ]] && [[ "$file_perms" != "600" ]]; then
            echo "Warning: Token file has insecure permissions: $file_perms" >&2
            return 1
        fi
        
        # Try to decrypt
        local encrypted_data=$(cat "$TOKEN_FILE")
        if ! decrypt_data "$encrypted_data" >/dev/null 2>&1; then
            echo "Error: Token file is corrupted or tampered" >&2
            return 1
        fi
    fi
    
    echo "Token storage validation passed" >&2
    return 0
}

# Secure deletion of token files
secure_delete_tokens() {
    if [ -f "$TOKEN_FILE" ]; then
        shred -vfz -n 3 "$TOKEN_FILE" 2>/dev/null || \
        dd if=/dev/urandom of="$TOKEN_FILE" bs=1024 count=10 2>/dev/null
        rm -f "$TOKEN_FILE"
    fi
    
    if [ -f "$TOKEN_BACKUP_FILE" ]; then
        shred -vfz -n 3 "$TOKEN_BACKUP_FILE" 2>/dev/null || \
        dd if=/dev/urandom of="$TOKEN_BACKUP_FILE" bs=1024 count=10 2>/dev/null
        rm -f "$TOKEN_BACKUP_FILE"
    fi
    
    if [ -f "$TOKEN_METADATA_FILE" ]; then
        rm -f "$TOKEN_METADATA_FILE"
    fi
}

# ============================================================================
# Initialization on source
# ============================================================================

# Initialize token storage when sourced
init_token_storage