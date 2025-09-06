#!/bin/bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SECURITY_DIR="$(dirname "$0")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

success() {
    log "✓ $*"
}

check_requirements() {
    log "Checking security requirements..."
    
    local required_commands=("docker" "openssl" "fail2ban-client" "ufw")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            success "Found $cmd"
        else
            log "WARNING: $cmd not found, some security features may not be available"
        fi
    done
}

setup_firewall() {
    log "Configuring firewall rules..."
    
    # Enable UFW if available
    if command -v ufw >/dev/null 2>&1; then
        # Reset UFW to defaults
        ufw --force reset
        
        # Default policies
        ufw default deny incoming
        ufw default allow outgoing
        
        # Allow SSH (customize port as needed)
        ufw allow 22/tcp comment "SSH"
        
        # Allow OpenVPN ports
        ufw allow 1194/udp comment "OpenVPN UDP"
        ufw allow 1195/tcp comment "OpenVPN TCP"
        
        # Allow admin interfaces (restrict to specific IPs in production)
        ufw allow from any to any port 8080 proto tcp comment "OpenVPN Admin"
        ufw allow from any to any port 8081 proto tcp comment "OpenVPN Status"
        
        # Allow monitoring (if enabled)
        ufw allow from 10.20.0.0/16 to any port 9090 proto tcp comment "Prometheus"
        ufw allow from 10.20.0.0/16 to any port 3000 proto tcp comment "Grafana"
        
        # Enable UFW
        ufw --force enable
        
        success "UFW firewall configured"
    else
        log "UFW not available, please configure firewall manually"
    fi
}

setup_fail2ban() {
    log "Configuring Fail2ban..."
    
    if command -v fail2ban-client >/dev/null 2>&1; then
        # Create OpenVPN jail configuration
        cat > /etc/fail2ban/jail.d/openvpn.conf << 'EOF'
[openvpn]
enabled = true
port = 1194,1195
protocol = udp,tcp
filter = openvpn
logpath = /var/log/openvpn/openvpn.log
maxretry = 3
bantime = 3600
findtime = 600

[openvpn-admin]
enabled = true
port = 8080
protocol = tcp
filter = nginx-http-auth
logpath = /var/log/nginx/access.log
maxretry = 5
bantime = 1800
findtime = 300
EOF

        # Create OpenVPN filter
        cat > /etc/fail2ban/filter.d/openvpn.conf << 'EOF'
[Definition]
failregex = ^.*TLS Error: TLS handshake failed.*<HOST>:\d+$
            ^.*VERIFY ERROR.*<HOST>:\d+$
            ^.*TLS Auth Error.*<HOST>:\d+$
ignoreregex =
EOF

        # Restart Fail2ban
        systemctl restart fail2ban
        success "Fail2ban configured for OpenVPN"
    else
        log "Fail2ban not available, manual intrusion detection recommended"
    fi
}

harden_docker() {
    log "Applying Docker security hardening..."
    
    # Create Docker daemon configuration with security settings
    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true,
    "seccomp-profile": "/etc/docker/seccomp-profile.json",
    "apparmor-profile": "docker-default"
}
EOF

    # Create minimal seccomp profile
    cat > /etc/docker/seccomp-profile.json << 'EOF'
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
    "syscalls": [
        {
            "names": [
                "accept", "access", "arch_prctl", "bind", "brk", "chdir", "chmod",
                "chown", "close", "connect", "dup", "dup2", "epoll_create", "epoll_ctl",
                "epoll_wait", "execve", "exit", "exit_group", "fchdir", "fchmod",
                "fchown", "fcntl", "fork", "fstat", "futex", "getcwd", "getdents",
                "getpid", "getppid", "getsockname", "getsockopt", "ioctl", "listen",
                "lseek", "madvise", "mkdir", "mmap", "mprotect", "munmap", "open",
                "openat", "pipe", "poll", "pread64", "pwrite64", "read", "readlink",
                "recvfrom", "recvmsg", "rename", "rmdir", "rt_sigaction", "rt_sigprocmask",
                "rt_sigreturn", "select", "sendmsg", "sendto", "setgid", "setgroups",
                "setsockopt", "setuid", "socket", "socketpair", "stat", "statfs",
                "sysinfo", "time", "uname", "unlink", "wait4", "write"
            ],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
EOF

    # Set proper permissions
    chmod 644 /etc/docker/daemon.json /etc/docker/seccomp-profile.json
    
    # Restart Docker daemon
    systemctl restart docker
    success "Docker security hardening applied"
}

setup_ssl_certificates() {
    log "Setting up SSL certificates for admin interface..."
    
    local ssl_dir="/opt/openvpn/ssl"
    mkdir -p "$ssl_dir"
    
    # Generate self-signed certificate for development
    # In production, use proper certificates from Let's Encrypt or CA
    openssl req -x509 -newkey rsa:4096 -keyout "$ssl_dir/private.key" \
        -out "$ssl_dir/certificate.crt" -days 365 -nodes \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=openvpn.local"
    
    chmod 600 "$ssl_dir/private.key"
    chmod 644 "$ssl_dir/certificate.crt"
    
    success "SSL certificates generated"
}

setup_log_rotation() {
    log "Configuring log rotation..."
    
    cat > /etc/logrotate.d/openvpn << 'EOF'
/var/log/openvpn/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    create 644 root root
}

/opt/openvpn/backups/openvpn_pki_backup_*.tar.gz {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    maxage 7
}
EOF

    success "Log rotation configured"
}

setup_system_hardening() {
    log "Applying system hardening..."
    
    # Disable unnecessary services
    local services_to_disable=("telnet" "rsh" "rlogin" "vsftpd")
    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            systemctl disable "$service"
            systemctl stop "$service"
            success "Disabled $service"
        fi
    done
    
    # Set secure kernel parameters
    cat > /etc/sysctl.d/99-openvpn-security.conf << 'EOF'
# Network security
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1

# IPv6 security
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Process security
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
EOF

    sysctl -p /etc/sysctl.d/99-openvpn-security.conf
    success "System hardening applied"
}

create_security_audit_script() {
    log "Creating security audit script..."
    
    cat > "$SECURITY_DIR/security-audit.sh" << 'EOF'
#!/bin/bash

set -euo pipefail

echo "OpenVPN Security Audit Report - $(date)"
echo "============================================"

# Check file permissions
echo ""
echo "File Permissions:"
find /opt/openvpn -type f -name "*.key" -exec ls -la {} \; 2>/dev/null || true
find /opt/openvpn/secrets -type f -exec ls -la {} \; 2>/dev/null || true

# Check running processes
echo ""
echo "OpenVPN Processes:"
ps aux | grep openvpn | grep -v grep || echo "No OpenVPN processes found"

# Check firewall status
echo ""
echo "Firewall Status:"
ufw status verbose 2>/dev/null || echo "UFW not available"

# Check fail2ban status
echo ""
echo "Fail2ban Status:"
fail2ban-client status 2>/dev/null || echo "Fail2ban not available"

# Check Docker security
echo ""
echo "Docker Security:"
docker info --format '{{.SecurityOptions}}' 2>/dev/null || echo "Docker not available"

# Check certificate expiration
echo ""
echo "Certificate Status:"
find /opt/openvpn -name "*.crt" -exec openssl x509 -in {} -noout -subject -dates \; 2>/dev/null || true

echo ""
echo "Audit completed at $(date)"
EOF

    chmod +x "$SECURITY_DIR/security-audit.sh"
    success "Security audit script created"
}

main() {
    log "Starting OpenVPN security hardening..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
    
    check_requirements
    setup_firewall
    setup_fail2ban
    harden_docker
    setup_ssl_certificates
    setup_log_rotation
    setup_system_hardening
    create_security_audit_script
    
    log "✓ Security hardening completed successfully"
    log ""
    log "Next steps:"
    log "1. Review firewall rules: ufw status"
    log "2. Test Fail2ban: fail2ban-client status"
    log "3. Run security audit: $SECURITY_DIR/security-audit.sh"
    log "4. Configure proper SSL certificates for production"
    log "5. Review and adjust security settings for your environment"
}

main "$@"