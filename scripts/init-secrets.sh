#!/bin/bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SECRETS_DIR="secrets"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

create_secrets_directory() {
    if [[ ! -d "$SECRETS_DIR" ]]; then
        mkdir -p "$SECRETS_DIR"
        chmod 700 "$SECRETS_DIR"
        log "✓ Created secrets directory"
    fi
}

create_secret_file() {
    local secret_name="$1"
    local secret_file="${SECRETS_DIR}/${secret_name}.txt"
    
    if [[ -f "$secret_file" ]]; then
        log "Secret file already exists: $secret_file"
        return 0
    fi
    
    local secret_value
    case "$secret_name" in
        "admin_username")
            read -p "Enter admin username [admin]: " secret_value
            secret_value="${secret_value:-admin}"
            ;;
        "admin_password"|"ca_password")
            secret_value=$(generate_password)
            log "Generated secure password for $secret_name"
            ;;
        *)
            error "Unknown secret type: $secret_name"
            ;;
    esac
    
    echo -n "$secret_value" > "$secret_file"
    chmod 600 "$secret_file"
    
    log "✓ Created secret file: $secret_file"
    
    if [[ "$secret_name" == "admin_password" ]]; then
        log "Admin password: $secret_value"
        log "IMPORTANT: Save this password securely!"
    fi
}

update_gitignore() {
    if ! grep -q "secrets/" .gitignore 2>/dev/null; then
        echo "secrets/" >> .gitignore
        log "✓ Added secrets/ to .gitignore"
    fi
}

main() {
    log "Initializing OpenVPN secrets..."
    
    create_secrets_directory
    update_gitignore
    
    create_secret_file "admin_username"
    create_secret_file "admin_password"
    create_secret_file "ca_password"
    
    log "✓ Secret initialization completed"
    log ""
    log "Next steps:"
    log "1. Review generated passwords above"
    log "2. Use docker-compose.prod.yml for production deployment"
    log "3. Ensure secrets/ directory is never committed to git"
}

main "$@"