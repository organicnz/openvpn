#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Docker is not running. Starting Docker...${NC}"
        sudo systemctl start docker || {
            echo -e "${RED}Failed to start Docker${NC}"
            exit 1
        }
    fi
}

# Function to initialize OpenVPN PKI
init_pki() {
    echo -e "${BLUE}Initializing OpenVPN PKI...${NC}"
    docker run --rm -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn ovpn_genconfig \
        -u udp://newvps.westus.cloudapp.azure.com:1194 \
        -s 10.8.0.0/24 \
        -d "8.8.8.8,8.8.4.4" \
        -p "route 10.8.0.0 255.255.255.0" \
        -p "route-gateway 10.8.0.1" \
        -p "port-share localhost 3005-3009" \
        -p "client-to-client" \
        -p "duplicate-cn" \
        -p "compress lz4-v2" \
        -p "push \"compress lz4-v2\"" \
        -p "push \"dhcp-option DNS 8.8.8.8\"" \
        -p "push \"dhcp-option DNS 8.8.4.4\""

    echo -e "${BLUE}Initializing PKI...${NC}"
    docker run --rm -v $PWD/openvpn_data:/etc/openvpn -it kylemanna/openvpn ovpn_initpki
}

# Function to generate client certificate
generate_client() {
    local client_name=$1
    if [ -z "$client_name" ]; then
        echo -e "${RED}Please provide a client name${NC}"
        return 1
    fi

    echo -e "${BLUE}Generating certificate for client: $client_name${NC}"
    docker run --rm -v $PWD/openvpn_data:/etc/openvpn -it kylemanna/openvpn easyrsa build-client-full "$client_name" nopass

    echo -e "${BLUE}Generating client configuration...${NC}"
    docker run --rm -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn ovpn_getclient "$client_name" > "$client_name.ovpn"

    # Add client-specific configuration
    cat client_configs/CLIENT_TEMPLATE >> "$client_name.ovpn"
    
    echo -e "${GREEN}Client configuration generated: $client_name.ovpn${NC}"
}

# Function to revoke client certificate
revoke_client() {
    local client_name=$1
    if [ -z "$client_name" ]; then
        echo -e "${RED}Please provide a client name${NC}"
        return 1
    }

    echo -e "${BLUE}Revoking certificate for client: $client_name${NC}"
    docker run --rm -v $PWD/openvpn_data:/etc/openvpn -it kylemanna/openvpn ovpn_revokeclient "$client_name"
}

# Function to list clients
list_clients() {
    echo -e "${BLUE}Listing clients...${NC}"
    docker run --rm -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn ovpn_listclients
}

# Function to show usage
show_usage() {
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 init              - Initialize OpenVPN PKI"
    echo "  $0 client add NAME   - Generate client certificate"
    echo "  $0 client revoke NAME - Revoke client certificate"
    echo "  $0 client list      - List all clients"
}

# Main script
check_docker

case "${1:-help}" in
    init)
        init_pki
        ;;
    client)
        case "$2" in
            add)
                generate_client "$3"
                ;;
            revoke)
                revoke_client "$3"
                ;;
            list)
                list_clients
                ;;
            *)
                show_usage
                ;;
        esac
        ;;
    *)
        show_usage
        ;;
esac 