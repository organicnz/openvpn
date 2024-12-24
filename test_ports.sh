#!/bin/bash

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Constants
readonly TCP_TIMEOUT=5
readonly UDP_TIMEOUT=3
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2
readonly LOG_FILE="/var/log/openvpn/port_tests.log"
readonly VPN_NETWORK="10.8.0.0/16"
readonly VPN_GATEWAY="10.8.0.1"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging function
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "${LOG_FILE}"
}

# Network validation function
validate_network() {
    local host=$1
    log "INFO" "Validating network configuration..."
    
    # Check Docker network
    echo -e "\n${BLUE}Checking Docker network configuration:${NC}"
    if ! docker network inspect openvpn_network >/dev/null 2>&1; then
        log "ERROR" "OpenVPN network not found"
        return 1
    fi
    
    # Verify network settings
    local network_config
    network_config=$(docker network inspect openvpn_network --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    if [[ "${network_config}" != "${VPN_NETWORK}" ]]; then
        log "ERROR" "Network subnet mismatch: ${network_config} != ${VPN_NETWORK}"
        return 1
    fi
    
    # Check gateway
    local gateway
    gateway=$(docker network inspect openvpn_network --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
    if [[ "${gateway}" != "${VPN_GATEWAY}" ]]; then
        log "ERROR" "Network gateway mismatch: ${gateway} != ${VPN_GATEWAY}"
        return 1
    fi
    
    # Check container network settings
    echo -e "\n${BLUE}Checking container network settings:${NC}"
    if ! docker inspect openvpn >/dev/null 2>&1; then
        log "ERROR" "OpenVPN container not found"
        return 1
    fi
    
    local container_ip
    container_ip=$(docker inspect openvpn --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
    if [[ "${container_ip}" != "${VPN_GATEWAY}" ]]; then
        log "ERROR" "Container IP mismatch: ${container_ip} != ${VPN_GATEWAY}"
        return 1
    fi
    
    log "INFO" "Network validation passed"
    return 0
}

# Network troubleshooting function
troubleshoot_network() {
    local host=$1
    log "INFO" "Running network troubleshooting..."
    
    echo -e "\n${BLUE}Network Interface Status:${NC}"
    ip addr show | grep -E "^[0-9]|inet"
    
    echo -e "\n${BLUE}Routing Table:${NC}"
    ip route
    
    echo -e "\n${BLUE}Docker Networks:${NC}"
    docker network ls
    
    echo -e "\n${BLUE}OpenVPN Network Details:${NC}"
    docker network inspect openvpn_network
    
    echo -e "\n${BLUE}Container Network Details:${NC}"
    docker inspect openvpn --format '{{json .NetworkSettings.Networks}}' | python3 -m json.tool
    
    echo -e "\n${BLUE}Network Namespace Details:${NC}"
    container_pid=$(docker inspect -f '{{.State.Pid}}' openvpn)
    if [[ -n "${container_pid}" ]] && [[ "${container_pid}" != "0" ]]; then
        sudo nsenter -t "${container_pid}" -n ip addr show
        sudo nsenter -t "${container_pid}" -n ip route
    fi
    
    echo -e "\n${BLUE}Connection Tracking:${NC}"
    sudo conntrack -L | grep -E "1194|3005|3006|3007|3008|3009"
    
    echo -e "\n${BLUE}Network Statistics:${NC}"
    ss -s
    
    echo -e "\n${BLUE}Interface Statistics:${NC}"
    netstat -i
    
    log "INFO" "Network troubleshooting completed"
}

# Test TCP port with retries
test_tcp_port() {
    local host=$1
    local port=$2
    local retry=0
    local success=false
    
    while (( retry < MAX_RETRIES )) && ! $success; do
        log "INFO" "Testing TCP port ${port} (attempt $((retry + 1))/${MAX_RETRIES})"
        
        if timeout ${TCP_TIMEOUT} bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; then
            success=true
            echo -e "${GREEN}✓ Port ${port}/tcp is open${NC}"
            log "INFO" "Port ${port}/tcp is open"
            return 0
        else
            ((retry++))
            if (( retry < MAX_RETRIES )); then
                log "WARNING" "TCP test failed, retrying in ${RETRY_DELAY}s..."
                sleep "${RETRY_DELAY}"
            fi
        fi
    done
    
    echo -e "${RED}✗ Port ${port}/tcp is closed or filtered${NC}"
    log "ERROR" "Port ${port}/tcp is closed or filtered after ${MAX_RETRIES} attempts"
    return 1
}

# Test UDP port with retries
test_udp_port() {
    local host=$1
    local port=$2
    local retry=0
    local success=false
    
    while (( retry < MAX_RETRIES )) && ! $success; do
        log "INFO" "Testing UDP port ${port} (attempt $((retry + 1))/${MAX_RETRIES})"
        
        if nc -zu -w "${UDP_TIMEOUT}" "${host}" "${port}" 2>/dev/null; then
            success=true
            echo -e "${GREEN}✓ Port ${port}/udp is open${NC}"
            log "INFO" "Port ${port}/udp is open"
            return 0
        else
            ((retry++))
            if (( retry < MAX_RETRIES )); then
                log "WARNING" "UDP test failed, retrying in ${RETRY_DELAY}s..."
                sleep "${RETRY_DELAY}"
            fi
        fi
    done
    
    echo -e "${RED}✗ Port ${port}/udp is closed or filtered${NC}"
    log "ERROR" "Port ${port}/udp is closed or filtered after ${MAX_RETRIES} attempts"
    return 1
}

# Show detailed port information
show_port_info() {
    local port=$1
    
    echo -e "\n${YELLOW}Detailed information for port ${port}:${NC}"
    log "INFO" "Getting detailed information for port ${port}"
    
    # Check if port is listening
    echo "Local listeners:"
    ss -ln | grep ":${port}" || echo "No local listeners found"
    
    # Check established connections
    echo -e "\nEstablished connections:"
    ss -tn | grep ":${port}" || echo "No established connections found"
    
    # Check firewall rules
    echo -e "\nFirewall rules:"
    sudo iptables -L -n -v | grep "${port}" || echo "No matching firewall rules found"
    
    # Check process using the port
    echo -e "\nProcess using the port:"
    sudo lsof -i ":${port}" || echo "No process found using this port"
    
    # Check Docker port bindings
    echo -e "\nDocker port bindings:"
    docker port openvpn | grep "${port}" || echo "No Docker bindings found"
}

# Test VPN connection
test_vpn_connection() {
    local host=$1
    local success=false
    
    echo -e "\n${YELLOW}Testing VPN connection...${NC}"
    log "INFO" "Testing VPN connection to ${host}"
    
    # Validate network configuration
    if ! validate_network "${host}"; then
        echo -e "${RED}✗ Network validation failed${NC}"
        troubleshoot_network "${host}"
        return 1
    fi
    
    # Test OpenVPN port
    if test_udp_port "${host}" 1194 && test_tcp_port "${host}" 1194; then
        echo -e "${GREEN}✓ OpenVPN ports are accessible${NC}"
        success=true
    else
        echo -e "${RED}✗ OpenVPN ports are not accessible${NC}"
        show_port_info 1194
        success=false
    fi
    
    # Test management port
    if test_tcp_port "localhost" 7505; then
        echo -e "${GREEN}✓ Management interface is accessible${NC}"
    else
        echo -e "${RED}✗ Management interface is not accessible${NC}"
        show_port_info 7505
        success=false
    fi
    
    # Test forwarded ports
    echo -e "\n${YELLOW}Testing forwarded ports...${NC}"
    local failed_ports=()
    
    for port in {3005..3009}; do
        if ! test_tcp_port "${host}" "${port}"; then
            failed_ports+=("${port}")
        fi
    done
    
    if (( ${#failed_ports[@]} > 0 )); then
        echo -e "${RED}✗ Some forwarded ports are not accessible: ${failed_ports[*]}${NC}"
        for port in "${failed_ports[@]}"; do
            show_port_info "${port}"
        done
        success=false
    else
        echo -e "${GREEN}✓ All forwarded ports are accessible${NC}"
    fi
    
    if $success; then
        log "INFO" "VPN connection test passed"
        return 0
    else
        log "ERROR" "VPN connection test failed"
        return 1
    fi
}

# Main execution
main() {
    local host="${1:-localhost}"
    
    # Create log directory if it doesn't exist
    sudo mkdir -p "$(dirname "${LOG_FILE}")"
    sudo touch "${LOG_FILE}"
    sudo chown "$(id -u):$(id -g)" "${LOG_FILE}"
    
    echo -e "${YELLOW}Starting port tests...${NC}"
    log "INFO" "Starting port tests for host: ${host}"
    
    if test_vpn_connection "${host}"; then
        echo -e "\n${GREEN}All tests passed successfully!${NC}"
        log "INFO" "All tests passed successfully"
        exit 0
    else
        echo -e "\n${RED}Some tests failed. Check the logs for details.${NC}"
        log "ERROR" "Some tests failed"
        exit 1
    fi
}

# Run main function with provided arguments
main "$@" 