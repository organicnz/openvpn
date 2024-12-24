#!/bin/bash

# Set strict error handling
set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Function to safely remove a file/directory
safe_remove() {
    local path=$1
    if [ -e "$path" ]; then
        echo -e "${YELLOW}Removing ${path}...${NC}"
        rm -rf "$path"
        echo -e "${GREEN}✓ Removed ${path}${NC}"
    fi
}

# Function to check if a Docker volume exists
check_volume() {
    local volume=$1
    docker volume inspect "$volume" >/dev/null 2>&1
}

# Clean up temporary files and directories
echo -e "\n${YELLOW}Cleaning up temporary files...${NC}"

# Clean .history directory
safe_remove ".history"

# Clean node_modules and yarn.lock in frontend directory
if [ -d "frontend" ]; then
    echo -e "\n${YELLOW}Cleaning frontend dependencies...${NC}"
    safe_remove "frontend/node_modules"
    safe_remove "frontend/yarn.lock"
fi

# Clean any temporary files
safe_remove "temp"
safe_remove "*.tmp"
safe_remove "*.log"
safe_remove ".DS_Store"

# Preserve Docker volumes
echo -e "\n${YELLOW}Checking Docker volumes...${NC}"
if check_volume "openvpn_data"; then
    echo -e "${GREEN}✓ Preserving openvpn_data volume${NC}"
else
    echo -e "${RED}Warning: openvpn_data volume not found${NC}"
fi

echo -e "\n${GREEN}Cleanup completed successfully!${NC}" 