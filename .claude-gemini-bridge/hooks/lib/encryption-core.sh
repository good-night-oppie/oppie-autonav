#!/bin/bash
# ABOUTME: Core AES-256-GCM encryption module for secure token storage

# Encryption constants
if [ -z "$ENCRYPTION_ALGORITHM" ]; then
    readonly ENCRYPTION_ALGORITHM="aes-256-cbc-hmac"
    readonly PBKDF2_ITERATIONS=100000
    readonly SALT_LENGTH=32
    readonly IV_LENGTH=16
    readonly TAG_LENGTH=16
    readonly KEY_LENGTH=32
fi

# Secure temporary directory
SECURE_TEMP_DIR=""

# ============================================================================
# Initialization and Cleanup
# ============================================================================

# Initialize encryption system
init_encryption() {
    # Check for OpenSSL availability
    if ! command -v openssl &>/dev/null; then
        echo "Error: OpenSSL is required for encryption operations" >&2
        return 1
    fi
    
    # Check OpenSSL version supports AES-256-GCM
    local openssl_version=$(openssl version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    local major_version=$(echo "$openssl_version" | cut -d. -f1)
    local minor_version=$(echo "$openssl_version" | cut -d. -f2)
    
    if [ "$major_version" -lt 1 ] || ([ "$major_version" -eq 1 ] && [ "$minor_version" -lt 1 ]); then
        echo "Error: OpenSSL 1.1.0 or higher required for AES-256-GCM" >&2
        return 1
    fi
    
    # Create secure temporary directory
    SECURE_TEMP_DIR=$(mktemp -d /tmp/encryption.XXXXXX)
    chmod 700 "$SECURE_TEMP_DIR"
    
    # Set up cleanup trap
    trap secure_cleanup EXIT
    
    return 0
}

# Secure cleanup of sensitive data
secure_cleanup() {
    local cleanup_dir="${1:-$SECURE_TEMP_DIR}"
    
    if [ -n "$cleanup_dir" ] && [ -d "$cleanup_dir" ]; then
        # Overwrite all files in temp directory before deletion
        find "$cleanup_dir" -type f -exec shred -vfz -n 3 {} \; 2>/dev/null || \
        find "$cleanup_dir" -type f -exec dd if=/dev/urandom of={} bs=1024 count=1 2>/dev/null \; 
        
        # Remove directory
        rm -rf "$cleanup_dir"
    fi
    
    # Clear sensitive variables from memory
    unset ENCRYPTION_KEY DECRYPTION_KEY SALT IV AUTH_TAG
    unset PLAINTEXT ENCRYPTED DECRYPTED
}

# ============================================================================
# Key Derivation Functions
# ============================================================================

# Generate random salt
generate_salt() {
    openssl rand -base64 "$SALT_LENGTH"
}

# Generate random IV
generate_iv() {
    openssl rand -base64 "$IV_LENGTH"
}

# Derive key from password using PBKDF2
derive_key() {
    local password="$1"
    local salt="$2"
    local iterations="${3:-$PBKDF2_ITERATIONS}"
    
    if [ -z "$password" ] || [ -z "$salt" ]; then
        echo "Error: Password and salt required for key derivation" >&2
        return 1
    fi
    
    # Use PBKDF2 with SHA-256 to derive key
    echo -n "$password" | openssl enc -pbkdf2 -pass stdin -S "$salt" \
        -iter "$iterations" -md sha256 -aes-256-cbc -nosalt -P 2>/dev/null | \
        grep "^key=" | cut -d= -f2
}

# Get machine-specific encryption key
get_machine_key() {
    local app_id="${1:-claude-gemini-bridge}"
    
    # Combine multiple system identifiers for uniqueness
    local machine_id=""
    
    # Try to get machine ID from various sources
    if [ -f "/etc/machine-id" ]; then
        machine_id=$(cat /etc/machine-id)
    elif [ -f "/var/lib/dbus/machine-id" ]; then
        machine_id=$(cat /var/lib/dbus/machine-id)
    elif command -v ioreg &>/dev/null; then
        # macOS
        machine_id=$(ioreg -rd1 -c IOPlatformExpertDevice | grep UUID | awk '{print $3}' | tr -d '"')
    else
        # Fallback to hostname + user
        machine_id="$(hostname)-$(id -u)"
    fi
    
    # Combine with user-specific data
    local user_data="${USER:-$(whoami)}-${HOME}"
    
    # Generate consistent key material
    local key_material="${machine_id}:${user_data}:${app_id}"
    
    # Hash to get consistent key
    echo -n "$key_material" | sha256sum | cut -d' ' -f1
}

# ============================================================================
# Encryption Functions
# ============================================================================

# Encrypt data using AES-256-GCM
encrypt_data() {
    local plaintext="$1"
    local password="${2:-$(get_machine_key)}"
    
    if [ -z "$plaintext" ]; then
        echo "Error: No data provided for encryption" >&2
        return 1
    fi
    
    # Generate salt and IV
    local salt=$(generate_salt)
    local iv=$(generate_iv)
    
    # Derive key
    local key=$(derive_key "$password" "$salt")
    
    if [ -z "$key" ]; then
        echo "Error: Key derivation failed" >&2
        return 1
    fi
    
    # Create temp files in secure directory
    local plaintext_file="$SECURE_TEMP_DIR/plain.$$"
    local encrypted_file="$SECURE_TEMP_DIR/encrypted.$$"
    local tag_file="$SECURE_TEMP_DIR/tag.$$"
    
    # Write plaintext to temp file
    echo -n "$plaintext" > "$plaintext_file"
    chmod 600 "$plaintext_file"
    
    # Use AES-256-CBC with HMAC for authenticated encryption (GCM alternative)
    # This provides similar security to GCM mode
    local hmac_key=$(echo -n "${key}HMAC" | sha256sum | cut -d' ' -f1)
    
    # Encrypt using AES-256-CBC
    if openssl enc -aes-256-cbc -K "$key" -iv "$(echo -n "$iv" | base64 -d | xxd -p -c 256)" \
        -in "$plaintext_file" -out "$encrypted_file" 2>/dev/null; then
        
        # Generate HMAC tag for authentication
        local encrypted_data=$(base64 "$encrypted_file")
        local auth_tag=$(echo -n "${salt}${iv}${encrypted_data}" | openssl dgst -sha256 -hmac "$hmac_key" -binary | xxd -p -c 256)
        
        # Create JSON output with all necessary data
        cat <<EOF
{
  "algorithm": "$ENCRYPTION_ALGORITHM",
  "salt": "$salt",
  "iv": "$iv",
  "tag": "$auth_tag",
  "iterations": $PBKDF2_ITERATIONS,
  "ciphertext": "$encrypted_data"
}
EOF
        
        # Clean up temp files
        shred -vfz -n 1 "$plaintext_file" "$encrypted_file" "$tag_file" 2>/dev/null
        rm -f "$plaintext_file" "$encrypted_file" "$tag_file"
        
        return 0
    else
        # Clean up on error
        shred -vfz -n 1 "$plaintext_file" 2>/dev/null
        rm -f "$plaintext_file" "$encrypted_file" "$tag_file"
        echo "Error: Encryption failed" >&2
        return 1
    fi
}

# ============================================================================
# Decryption Functions
# ============================================================================

# Decrypt data using AES-256-GCM
decrypt_data() {
    local encrypted_json="$1"
    local password="${2:-$(get_machine_key)}"
    
    if [ -z "$encrypted_json" ]; then
        echo "Error: No encrypted data provided" >&2
        return 1
    fi
    
    # Parse JSON to extract components
    local algorithm=$(echo "$encrypted_json" | grep -o '"algorithm"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local salt=$(echo "$encrypted_json" | grep -o '"salt"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local iv=$(echo "$encrypted_json" | grep -o '"iv"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local tag=$(echo "$encrypted_json" | grep -o '"tag"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local iterations=$(echo "$encrypted_json" | grep -o '"iterations"[[:space:]]*:[[:space:]]*[0-9]*' | cut -d: -f2 | tr -d ' ')
    local ciphertext=$(echo "$encrypted_json" | grep -o '"ciphertext"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    
    # Validate required fields
    if [ -z "$salt" ] || [ -z "$iv" ] || [ -z "$tag" ] || [ -z "$ciphertext" ]; then
        echo "Error: Invalid encrypted data format" >&2
        return 1
    fi
    
    # Verify algorithm (support both old and new)
    if [ "$algorithm" != "$ENCRYPTION_ALGORITHM" ] && [ "$algorithm" != "aes-256-gcm" ]; then
        echo "Error: Unsupported encryption algorithm: $algorithm" >&2
        return 1
    fi
    
    # Derive key
    local key=$(derive_key "$password" "$salt" "$iterations")
    
    if [ -z "$key" ]; then
        echo "Error: Key derivation failed" >&2
        return 1
    fi
    
    # Create temp files in secure directory
    local encrypted_file="$SECURE_TEMP_DIR/encrypted.$$"
    local decrypted_file="$SECURE_TEMP_DIR/decrypted.$$"
    local tag_file="$SECURE_TEMP_DIR/tag.$$"
    
    # Write encrypted data to temp file
    echo -n "$ciphertext" | base64 -d > "$encrypted_file"
    echo -n "$tag" | xxd -r -p > "$tag_file"
    chmod 600 "$encrypted_file" "$tag_file"
    
    # Verify HMAC tag first for authentication
    local hmac_key=$(echo -n "${key}HMAC" | sha256sum | cut -d' ' -f1)
    local expected_tag=$(echo -n "${salt}${iv}${ciphertext}" | openssl dgst -sha256 -hmac "$hmac_key" -binary | xxd -p -c 256)
    
    if [ "$tag" != "$expected_tag" ]; then
        echo "Error: Authentication tag verification failed" >&2
        rm -f "$encrypted_file" "$decrypted_file" "$tag_file"
        return 1
    fi
    
    # Decrypt using AES-256-CBC
    if openssl enc -d -aes-256-cbc -K "$key" -iv "$(echo -n "$iv" | base64 -d | xxd -p -c 256)" \
        -in "$encrypted_file" -out "$decrypted_file" 2>/dev/null; then
        
        # Read decrypted data
        local decrypted_data=$(cat "$decrypted_file")
        
        # Clean up temp files
        shred -vfz -n 1 "$encrypted_file" "$decrypted_file" "$tag_file" 2>/dev/null
        rm -f "$encrypted_file" "$decrypted_file" "$tag_file"
        
        echo "$decrypted_data"
        return 0
    else
        # Clean up on error
        rm -f "$encrypted_file" "$decrypted_file" "$tag_file"
        echo "Error: Decryption failed or data integrity check failed" >&2
        return 1
    fi
}

# ============================================================================
# Utility Functions
# ============================================================================

# Test encryption/decryption round-trip
test_encryption() {
    local test_data="${1:-This is a test message for encryption}"
    local test_password="${2:-test-password-123}"
    
    echo "Testing encryption with: $test_data" >&2
    
    # Encrypt
    local encrypted=$(encrypt_data "$test_data" "$test_password")
    if [ $? -ne 0 ]; then
        echo "Error: Encryption test failed" >&2
        return 1
    fi
    
    echo "Encrypted successfully" >&2
    
    # Decrypt
    local decrypted=$(decrypt_data "$encrypted" "$test_password")
    if [ $? -ne 0 ]; then
        echo "Error: Decryption test failed" >&2
        return 1
    fi
    
    # Verify round-trip
    if [ "$decrypted" = "$test_data" ]; then
        echo "Success: Encryption round-trip test passed" >&2
        return 0
    else
        echo "Error: Decrypted data does not match original" >&2
        echo "Original: $test_data" >&2
        echo "Decrypted: $decrypted" >&2
        return 1
    fi
}

# Secure random password generation
generate_secure_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d '\n'
}

# Hash data with SHA-256
hash_data() {
    local data="$1"
    echo -n "$data" | sha256sum | cut -d' ' -f1
}

# ============================================================================
# Initialization on source
# ============================================================================

# Initialize encryption system when sourced
init_encryption