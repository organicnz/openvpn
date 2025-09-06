#!/bin/bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly PKI_DIR="/etc/openvpn/pki"
readonly BACKUP_DIR="/backups"
readonly DATE=$(date +%Y%m%d_%H%M%S)
readonly BACKUP_FILE="${BACKUP_DIR}/openvpn_pki_backup_${DATE}.tar.gz"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

create_backup() {
    if [[ ! -d "$PKI_DIR" ]]; then
        error "PKI directory not found: $PKI_DIR"
    fi
    
    log "Creating PKI backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    tar -czf "$BACKUP_FILE" -C "$(dirname "$PKI_DIR")" "$(basename "$PKI_DIR")"
    
    if [[ -f "$BACKUP_FILE" ]]; then
        log "✓ Backup created successfully: $BACKUP_FILE"
        log "Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"
    else
        error "Failed to create backup"
    fi
}

cleanup_old_backups() {
    log "Cleaning up old backups (keeping last 7 days)..."
    
    find "$BACKUP_DIR" -name "openvpn_pki_backup_*.tar.gz" -type f -mtime +7 -delete 2>/dev/null || true
    
    local remaining_backups
    remaining_backups=$(find "$BACKUP_DIR" -name "openvpn_pki_backup_*.tar.gz" -type f | wc -l)
    log "✓ Cleanup complete. Remaining backups: $remaining_backups"
}

verify_backup() {
    log "Verifying backup integrity..."
    
    if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
        log "✓ Backup integrity verified"
    else
        error "Backup verification failed"
    fi
}

main() {
    log "Starting certificate backup process"
    
    create_backup
    verify_backup
    cleanup_old_backups
    
    log "Certificate backup completed successfully"
}

trap 'error "Script interrupted"' INT TERM

main "$@"