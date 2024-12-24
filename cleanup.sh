#!/bin/bash

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Starting server cleanup for OpenVPN stack...${NC}"

# Function to safely remove files/directories within our project
safe_remove() {
    local path=$1
    if [ -e "$path" ]; then
        echo -e "Removing ${path}..."
        rm -rf "$path"
        echo -e "${GREEN}✓ Removed ${path}${NC}"
    else
        echo -e "${YELLOW}⚠ ${path} not found, skipping${NC}"
    fi
}

# Clean project-specific temporary files
echo -e "\n${YELLOW}Cleaning temporary files...${NC}"
rm -rf logs/* temp/* .history/* 2>/dev/null || true
find . -type f -name "*.log" -delete 2>/dev/null || true
echo -e "${GREEN}✓ Cleaned temporary files${NC}"

# Clean Docker resources specific to our stack
echo -e "\n${YELLOW}Cleaning Docker resources...${NC}"

# Stop and remove OpenVPN container if running
if docker ps -q -f name=openvpn >/dev/null 2>&1; then
    echo "Stopping OpenVPN container..."
    docker stop openvpn || true
    docker rm -f openvpn || true
fi

# Remove old OpenVPN network if exists
if docker network ls -q -f name=openvpn_network >/dev/null 2>&1; then
    echo "Removing old OpenVPN network..."
    docker network rm openvpn_network || true
fi

# Preserve OpenVPN data volume
echo -e "\n${YELLOW}Checking OpenVPN data volume...${NC}"
if ! docker volume ls -q -f name=openvpn_data >/dev/null 2>&1; then
    echo "Creating OpenVPN data volume..."
    docker volume create openvpn_data
else
    echo -e "${GREEN}✓ OpenVPN data volume exists${NC}"
fi

# Recreate OpenVPN container
echo -e "\n${YELLOW}Recreating OpenVPN container...${NC}"
docker-compose up -d

# Wait for container to start
echo "Waiting for OpenVPN container to start..."
sleep 5

# Verify container is running
if docker ps -q -f name=openvpn >/dev/null 2>&1; then
    echo -e "${GREEN}✓ OpenVPN container is running${NC}"
else
    echo -e "${RED}Error: OpenVPN container failed to start${NC}"
    docker logs openvpn
    exit 1
fi

# Final status
echo -e "\n${GREEN}Server cleanup completed!${NC}"
echo -e "\nOpenVPN stack status:"
docker ps -a -f name=openvpn
echo -e "\nOpenVPN volumes:"
docker volume ls -f name=openvpn_data
echo -e "\nOpenVPN networks:"
docker network ls -f name=openvpn_network 