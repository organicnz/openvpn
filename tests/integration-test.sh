#!/bin/bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly TEST_DIR="$(dirname "$0")"
readonly PROJECT_ROOT="$(dirname "$TEST_DIR")"
readonly COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"

# Test configuration
readonly TIMEOUT_SECONDS=300
readonly RETRY_INTERVAL=5
readonly TEST_CLIENT_NAME="test-client-$(date +%s)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $*" >&2
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

error() {
    echo -e "${RED}✗${NC} $*"
    exit 1
}

wait_for_service() {
    local service_name="$1"
    local health_url="$2"
    local timeout="$3"
    
    log "Waiting for $service_name to be healthy..."
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if curl -f -s "$health_url" >/dev/null 2>&1; then
            success "$service_name is healthy"
            return 0
        fi
        
        sleep $RETRY_INTERVAL
        elapsed=$((elapsed + RETRY_INTERVAL))
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log "Still waiting for $service_name... (${elapsed}s elapsed)"
        fi
    done
    
    error "$service_name failed to become healthy within ${timeout}s"
}

test_docker_compose_syntax() {
    log "Testing Docker Compose syntax..."
    
    if docker-compose -f "$COMPOSE_FILE" config >/dev/null 2>&1; then
        success "Docker Compose syntax is valid"
    else
        error "Docker Compose syntax validation failed"
    fi
}

test_container_startup() {
    log "Testing container startup..."
    
    docker-compose -f "$COMPOSE_FILE" up -d
    
    # Wait for services to be ready
    wait_for_service "OpenVPN Admin" "http://localhost:8080/health" $TIMEOUT_SECONDS
    wait_for_service "OpenVPN Status" "http://localhost:8081" $TIMEOUT_SECONDS
    
    # Check container health
    local containers=("openvpn-server" "openvpn-admin-panel" "openvpn-status-page")
    for container in "${containers[@]}"; do
        if docker ps --filter "name=$container" --filter "status=running" | grep -q "$container"; then
            success "Container $container is running"
        else
            error "Container $container is not running"
        fi
    done
}

test_openvpn_configuration() {
    log "Testing OpenVPN configuration..."
    
    # Check if OpenVPN process is running
    if docker exec openvpn-server pgrep openvpn >/dev/null 2>&1; then
        success "OpenVPN process is running"
    else
        error "OpenVPN process is not running"
    fi
    
    # Check management interface
    if docker exec openvpn-server nc -z localhost 7505 >/dev/null 2>&1; then
        success "OpenVPN management interface is accessible"
    else
        warning "OpenVPN management interface may not be ready"
    fi
}

test_admin_panel() {
    log "Testing admin panel functionality..."
    
    # Test health endpoint
    local health_response
    health_response=$(curl -s http://localhost:8080/health)
    
    if echo "$health_response" | jq -e '.status == "healthy"' >/dev/null 2>&1; then
        success "Admin panel health check passed"
    else
        error "Admin panel health check failed"
    fi
    
    # Test login page
    if curl -f -s http://localhost:8080 | grep -q "OpenVPN Admin"; then
        success "Admin panel login page is accessible"
    else
        error "Admin panel login page is not accessible"
    fi
}

test_client_certificate_management() {
    log "Testing client certificate management..."
    
    # Create test client certificate
    if docker exec openvpn-server easyrsa build-client-full "$TEST_CLIENT_NAME" nopass >/dev/null 2>&1; then
        success "Client certificate creation successful"
    else
        error "Client certificate creation failed"
    fi
    
    # List clients to verify creation
    if docker exec openvpn-server ovpn_listclients | grep -q "$TEST_CLIENT_NAME"; then
        success "Client certificate is listed"
    else
        error "Client certificate is not listed"
    fi
    
    # Generate client configuration
    local client_config
    client_config=$(docker exec openvpn-server ovpn_getclient "$TEST_CLIENT_NAME")
    
    if echo "$client_config" | grep -q "BEGIN CERTIFICATE"; then
        success "Client configuration generated successfully"
    else
        error "Client configuration generation failed"
    fi
    
    # Clean up test certificate
    docker exec openvpn-server ovpn_revokeclient "$TEST_CLIENT_NAME" >/dev/null 2>&1 || true
    log "Test client certificate cleaned up"
}

test_backup_functionality() {
    log "Testing backup functionality..."
    
    if docker exec openvpn-server /usr/local/bin/backup-certs.sh >/dev/null 2>&1; then
        success "Certificate backup completed successfully"
    else
        error "Certificate backup failed"
    fi
    
    # Check if backup file was created
    local backup_count
    backup_count=$(ls -1 backups/openvpn_pki_backup_*.tar.gz 2>/dev/null | wc -l)
    
    if [[ $backup_count -gt 0 ]]; then
        success "Backup files created ($backup_count found)"
    else
        error "No backup files found"
    fi
}

test_security_headers() {
    log "Testing security headers..."
    
    local headers
    headers=$(curl -I -s http://localhost:8080)
    
    local required_headers=("X-Content-Type-Options" "X-Frame-Options" "X-XSS-Protection")
    for header in "${required_headers[@]}"; do
        if echo "$headers" | grep -qi "$header"; then
            success "Security header $header is present"
        else
            warning "Security header $header is missing"
        fi
    done
}

test_network_connectivity() {
    log "Testing network connectivity..."
    
    # Test UDP port
    if nc -u -z localhost 1194 >/dev/null 2>&1; then
        success "OpenVPN UDP port (1194) is accessible"
    else
        warning "OpenVPN UDP port (1194) may not be accessible"
    fi
    
    # Test management port from within container
    if docker exec openvpn-server nc -z localhost 7505 >/dev/null 2>&1; then
        success "Management port (7505) is accessible"
    else
        warning "Management port (7505) is not accessible"
    fi
}

cleanup() {
    log "Cleaning up test environment..."
    
    docker-compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true
    
    # Remove test backup files
    rm -f backups/openvpn_pki_backup_*.tar.gz 2>/dev/null || true
    
    success "Cleanup completed"
}

run_all_tests() {
    log "Starting OpenVPN integration tests..."
    
    test_docker_compose_syntax
    test_container_startup
    sleep 10 # Allow services to fully initialize
    test_openvpn_configuration
    test_admin_panel
    test_client_certificate_management
    test_backup_functionality
    test_security_headers
    test_network_connectivity
    
    success "All tests completed successfully!"
}

main() {
    trap cleanup EXIT
    
    cd "$PROJECT_ROOT"
    
    if [[ "${1:-}" == "--cleanup-only" ]]; then
        cleanup
        exit 0
    fi
    
    run_all_tests
}

main "$@"