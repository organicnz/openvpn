#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Print section header
print_header() {
    echo -e "\n${BLUE}$1${NC}"
    echo "----------------------------------------"
}

# Print success/failure
print_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        return 1
    fi
}

# System Information
print_header "🔍 System Information"
uname -a
print_status "System info check"

# Network Tools Version
print_header "Network Tools Version"

# Netcat version
if command -v nc >/dev/null 2>&1; then
    nc_version=$(nc -h 2>&1 | head -n1)
    echo -e "netcat: ${GREEN}${nc_version:-version unknown}${NC}"
else
    echo -e "netcat: ${RED}not installed${NC}"
fi

# Curl version
if command -v curl >/dev/null 2>&1; then
    curl_version=$(curl --version | head -n1)
    echo -e "curl: ${GREEN}${curl_version:-version unknown}${NC}"
else
    echo -e "curl: ${RED}not installed${NC}"
fi

# Dig version
if command -v dig >/dev/null 2>&1; then
    dig_version=$(dig -h | grep "DiG" | head -n1)
    echo -e "dig: ${GREEN}${dig_version:-version unknown}${NC}"
else
    echo -e "dig: ${RED}not installed${NC}"
fi

# Docker version
print_header "Docker Information"
if command -v docker >/dev/null 2>&1; then
    docker_version=$(docker --version | cut -d',' -f1)
    echo -e "Docker: ${GREEN}${docker_version}${NC}"
    
    # Check Docker service
    if systemctl is-active --quiet docker; then
        echo -e "Docker service: ${GREEN}running${NC}"
    else
        echo -e "Docker service: ${RED}not running${NC}"
    fi
else
    echo -e "Docker: ${RED}not installed${NC}"
fi

# Network Connectivity
print_header "Network Connectivity"
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "Internet connection: ${GREEN}available${NC}"
else
    echo -e "Internet connection: ${RED}not available${NC}"
fi

# System Resources
print_header "System Resources"
echo "Memory Usage:"
free -h | grep -E "Mem|Swap"

echo -e "\nDisk Usage:"
df -h / | tail -n 1

echo -e "\nCPU Load:"
uptime | cut -d':' -f4-

# Required Ports
print_header "Required Ports"
for port in 1194 443 16648; do
    if nc -zv localhost $port >/dev/null 2>&1; then
        echo -e "Port $port: ${GREEN}open${NC}"
    else
        echo -e "Port $port: ${RED}closed${NC}"
    fi
done

# Environment Variables
print_header "Environment Variables"
required_vars=("DOCKER_USERNAME" "DOCKER_TOKEN" "MONGO_USER" "MONGO_PASSWORD")
for var in "${required_vars[@]}"; do
    if [ -n "${!var}" ]; then
        echo -e "$var: ${GREEN}set${NC}"
    else
        echo -e "$var: ${RED}not set${NC}"
    fi
done

# Network validation
print_header "Network Validation"

# Check Docker network
if docker network inspect openvpn_network >/dev/null 2>&1; then
    echo -e "OpenVPN network: ${GREEN}exists${NC}"
    
    # Check network configuration
    network_config=$(docker network inspect openvpn_network --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    if [[ "${network_config}" == "10.8.0.0/16" ]]; then
        echo -e "Network subnet: ${GREEN}${network_config}${NC}"
    else
        echo -e "Network subnet: ${RED}${network_config} (expected: 10.8.0.0/16)${NC}"
    fi
    
    # Check gateway
    gateway=$(docker network inspect openvpn_network --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
    if [[ "${gateway}" == "10.8.0.1" ]]; then
        echo -e "Network gateway: ${GREEN}${gateway}${NC}"
    else
        echo -e "Network gateway: ${RED}${gateway} (expected: 10.8.0.1)${NC}"
    fi
    
    # Check container network settings
    if docker inspect openvpn >/dev/null 2>&1; then
        echo -e "OpenVPN container: ${GREEN}exists${NC}"
        
        container_ip=$(docker inspect openvpn --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
        if [[ "${container_ip}" == "10.8.0.1" ]]; then
            echo -e "Container IP: ${GREEN}${container_ip}${NC}"
        else
            echo -e "Container IP: ${RED}${container_ip} (expected: 10.8.0.1)${NC}"
        fi
    else
        echo -e "OpenVPN container: ${RED}not found${NC}"
    fi
else
    echo -e "OpenVPN network: ${RED}not found${NC}"
fi

# Check network interfaces
print_header "Network Interfaces"
echo "Docker interfaces:"
ip -br link show type bridge

echo -e "\nTun/Tap interfaces:"
ip -br link show type tun

echo -e "\nNetwork namespaces:"
if command -v lsns >/dev/null 2>&1; then
    lsns -t net
else
    ls -l /var/run/netns 2>/dev/null || echo "No network namespaces found"
fi

# Check routing
print_header "Routing Table"
ip route show | grep -E "^default|^10.8.0.0"

# Check iptables
print_header "IPTables Rules"
echo "NAT rules:"
sudo iptables -t nat -L -n -v 2>/dev/null | grep -E "MASQUERADE|DNAT" || echo "No NAT rules found"

echo -e "\nForward rules:"
sudo iptables -L FORWARD -n -v 2>/dev/null | grep -E "ACCEPT|REJECT" || echo "No forward rules found"

# Check port availability
print_header "Port Availability"

check_port() {
    local port=$1
    local pid
    local container_id
    
    # Check if port is in use by a process
    pid=$(sudo lsof -t -i :"$port" 2>/dev/null)
    if [ -n "$pid" ]; then
        echo -e "Port $port: ${RED}in use by process $pid$(ps -p "$pid" -o comm= 2>/dev/null)${NC}"
        return 1
    fi
    
    # Check if port is in use by a container
    container_id=$(docker container ls -q --filter "publish=$port" 2>/dev/null)
    if [ -n "$container_id" ]; then
        echo -e "Port $port: ${RED}in use by container $(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null)${NC}"
        return 1
    fi
    
    echo -e "Port $port: ${GREEN}available${NC}"
    return 0
}

# Check OpenVPN ports
for port in 1194 3005 3006 3007 3008 3009; do
    check_port "$port"
done

# Check Docker network ports
print_header "Docker Network Ports"
echo "Published ports:"
docker ps --format "{{.Ports}}" | grep -v '^$' || echo "No published ports found"

echo -e "\nPort bindings:"
docker container ls --format "{{.Names}}: {{.Ports}}" | grep -v '^$' || echo "No port bindings found" 