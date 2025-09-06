#!/bin/bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly ENV_FILE="/etc/openvpn/ovpn_env.sh"
readonly CONFIG_DIR="/etc/openvpn"
readonly CCD_DIR="$CONFIG_DIR/ccd"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

check_requirements() {
    log "Checking system requirements..."
    
    if [[ ! -d "$CONFIG_DIR" ]]; then
        error "OpenVPN configuration directory not found: $CONFIG_DIR"
    fi
    
    if [[ -z "${HOSTNAME:-}" ]]; then
        error "HOSTNAME environment variable not set"
    fi
    
    log "✓ System requirements satisfied"
}

create_environment_file() {
    if [[ -f "$ENV_FILE" ]]; then
        log "Environment file already exists: $ENV_FILE"
        return 0
    fi
    
    log "Creating environment file: $ENV_FILE"
    
    cat > "$ENV_FILE" << EOF
export OVPN_AUTH=
export OVPN_CIPHER=AES-256-GCM
export OVPN_CLIENT_TO_CLIENT=${OVPN_CLIENT_TO_CLIENT:-1}
export OVPN_CN="${HOSTNAME}"
export OVPN_COMP_LZO=0
export OVPN_DEFROUTE=1
export OVPN_DEVICE=tun
export OVPN_DEVICEN=0
export OVPN_DISABLE_PUSH_BLOCK_DNS=0
export OVPN_DNS=1
export OVPN_DNS_SERVERS=("${OVPN_DNS:-8.8.8.8}" "${OVPN_DNS:-8.8.4.4}")
export OVPN_ENV="$ENV_FILE"
export OVPN_EXTRA_CLIENT_CONFIG=()
export OVPN_EXTRA_SERVER_CONFIG=()
export OVPN_FRAGMENT=
export OVPN_MTU=
export OVPN_NAT=1
export OVPN_OTP_AUTH=
export OVPN_PORT=${OVPN_PORT:-1194}
export OVPN_PROTO=both
export OVPN_PUSH=()
export OVPN_ROUTES=([0]="${OVPN_SERVER:-10.20.0.0/24}")
export OVPN_SERVER="${OVPN_SERVER:-10.20.0.0/24}"
export OVPN_SERVER_URL="udp://${HOSTNAME}:${OVPN_PORT:-1194}"
export OVPN_SERVER_URL_TCP="tcp://${HOSTNAME}:${OVPN_TCP_PORT:-1195}"
export OVPN_TLS_CIPHER=TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384
export OVPN_TLS_VERSION_MIN=1.2
export OVPN_DUPLICATE_CN=${OVPN_DUPLICATE_CN:-1}
EOF

    chmod 644 "$ENV_FILE"
    log "✓ Environment file created successfully"
}

setup_directories() {
    log "Setting up required directories..."
    
    mkdir -p "$CCD_DIR"
    chown root:root "$CCD_DIR"
    chmod 755 "$CCD_DIR"
    
    log "✓ Directories configured"
}

generate_configuration() {
    if [[ -f "$CONFIG_DIR/openvpn.conf" ]]; then
        log "OpenVPN configuration already exists"
        return 0
    fi
    
    log "Generating OpenVPN configuration from template..."
    
    # Check if we have a custom template
    local template_file="/etc/openvpn/server_configs/openvpn.conf.template"
    if [[ -f "$template_file" ]]; then
        log "Using custom configuration template"
        
        # Substitute environment variables in template
        envsubst < "$template_file" > "$CONFIG_DIR/openvpn.conf"
        
        log "✓ Configuration generated from custom template"
    else
        log "Using default ovpn_genconfig method"
        
        local server_url="udp://${HOSTNAME}:${OVPN_PORT:-1194}"
        local server_subnet="${OVPN_SERVER:-10.20.0.0/24}"
        local dns_servers="${OVPN_DNS:-8.8.8.8,8.8.4.4}"
        
        # Generate configuration using ovpn_genconfig
        ovpn_genconfig \
            -u "$server_url" \
            -s "$server_subnet" \
            -d "$dns_servers" \
            -p "client-to-client" \
            -p "duplicate-cn" \
            -p "compress lz4-v2" \
            -p "push \"compress lz4-v2\"" \
            -p "push \"dhcp-option DNS ${dns_servers%,*}\"" \
            -p "push \"dhcp-option DNS ${dns_servers#*,}\""
        
        log "✓ Configuration generated using default method"
    fi
}

validate_configuration() {
    log "Validating OpenVPN configuration..."
    
    if [[ ! -f "$CONFIG_DIR/openvpn.conf" ]]; then
        log "OpenVPN configuration missing, generating..."
        generate_configuration
    fi
    
    if [[ ! -d "$CONFIG_DIR/pki" ]]; then
        error "PKI directory not found. Run ovpn_initpki first or use automated initialization."
    fi
    
    log "✓ Configuration validation passed"
}

setup_backup_cron() {
    log "Setting up certificate backup..."
    
    # Create backup directory
    mkdir -p /backups
    
    # Setup daily backup at 2 AM
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup-certs.sh") | crontab -
    
    log "✓ Backup scheduled for daily execution at 2 AM"
}

start_openvpn() {
    log "Starting OpenVPN server..."
    
    local openvpn_args=(
        "--config" "$CONFIG_DIR/openvpn.conf"
        "--client-config-dir" "$CCD_DIR"
    )
    
    if [[ "${DEBUG:-0}" == "1" ]]; then
        openvpn_args+=("--verb" "6")
        log "Debug mode enabled"
    fi
    
    exec openvpn "${openvpn_args[@]}"
}

main() {
    log "Starting OpenVPN setup script"
    
    check_requirements
    create_environment_file
    setup_directories
    generate_configuration
    validate_configuration
    setup_backup_cron
    start_openvpn
}

trap 'error "Script interrupted"' INT TERM

main "$@"