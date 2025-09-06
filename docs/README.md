# OpenVPN Docker Deployment

Production-ready OpenVPN server deployment using Docker Compose with security best practices, monitoring, and automated CI/CD.

## Features

- **OpenVPN Server**: UDP/TCP support with modern security configurations
- **Web Management**: Admin panel and status monitoring dashboard
- **Security First**: Resource limits, read-only containers, minimal privileges
- **Health Monitoring**: Built-in health checks and automated recovery
- **CI/CD Ready**: GitHub Actions deployment pipeline
- **IPv6 Support**: Full IPv6 forwarding and tunneling

## Quick Start

1. **Clone and configure**:
   ```bash
   git clone <repository-url>
   cd openvpn
   cp .env.example .env
   # Edit .env with your configuration
   ```

2. **Start services**:
   ```bash
   docker-compose -f context/docker-compose.yml up -d
   ```

3. **Initialize OpenVPN** (first time only):
   ```bash
   # Generate configuration
   docker run --rm -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn \
     ovpn_genconfig -u udp://your-domain.com:1194 -s 10.20.0.0/24
   
   # Initialize PKI
   docker run --rm -i -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn \
     ovpn_initpki nopass
   ```

4. **Create client certificate**:
   ```bash
   docker run --rm -i -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn \
     easyrsa build-client-full client1 nopass
   
   docker run --rm -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn \
     ovpn_getclient client1 > client1.ovpn
   ```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VPN_DOMAIN` | `vpn.example.com` | Your VPN server domain/IP |
| `OVPN_SERVER` | `10.20.0.0/24` | VPN client subnet |
| `OPENVPN_UDP_PORT` | `1194` | UDP port for OpenVPN |
| `OPENVPN_TCP_PORT` | `1195` | TCP port for OpenVPN |
| `ADMIN_PORT` | `8080` | Web admin panel port |
| `STATUS_PORT` | `8081` | Status dashboard port |

### Security Configuration

- **Resource Limits**: Memory and CPU limits for all containers
- **Read-only Filesystems**: Where possible to prevent tampering
- **No New Privileges**: Security hardening for containers
- **Minimal User Permissions**: Non-root execution where feasible

## Service Access

- **OpenVPN Server**: 
  - UDP: `your-server:1194`
  - TCP: `your-server:1195`
- **Admin Panel**: `http://your-server:8080`
- **Status Dashboard**: `http://your-server:8081`

## Client Management

### Web Interface
Access the admin panel at `http://your-server:8080` for GUI-based client management.

### Command Line

```bash
# List clients
docker run --rm -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn ovpn_listclients

# Create client
docker run --rm -i -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn \
  easyrsa build-client-full CLIENT_NAME nopass

# Get client config
docker run --rm -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn \
  ovpn_getclient CLIENT_NAME > CLIENT_NAME.ovpn

# Revoke client
docker run --rm -v $PWD/openvpn_data:/etc/openvpn kylemanna/openvpn \
  ovpn_revokeclient CLIENT_NAME
```

## Production Deployment

### Prerequisites
- Docker and Docker Compose
- Firewall configuration for OpenVPN ports
- SSL certificate for web interfaces (recommended)
- Backup strategy for `openvpn_data` volume

### Security Checklist
- [ ] Change default admin credentials
- [ ] Configure firewall rules
- [ ] Set up SSL/TLS for web interfaces
- [ ] Implement regular backups
- [ ] Monitor logs for security events
- [ ] Update Docker images regularly

### CI/CD Deployment

GitHub Actions workflow is included for automated deployment:

1. Configure repository secrets:
   - `SERVER_HOST`, `SERVER_USER`, `AZURE_SSH_KEY`
   - `OPENVPN_ADMIN_USERNAME`, `OPENVPN_ADMIN_PASSWORD`
   - `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `DOCKER_TOKEN`

2. Push to `main` branch triggers automatic deployment

## Backup & Recovery

### Create Backup
```bash
docker run --rm -v openvpn_data:/data -v $(pwd):/backup alpine \
  tar -czf /backup/openvpn-backup-$(date +%Y%m%d).tar.gz -C /data .
```

### Restore Backup
```bash
docker run --rm -v openvpn_data:/data -v $(pwd):/backup alpine \
  sh -c "rm -rf /data/* && tar -xzf /backup/openvpn-backup-YYYYMMDD.tar.gz -C /data"
```

## Monitoring

Built-in monitoring includes:
- Container health checks
- Automated service recovery
- Log rotation and management
- Resource usage monitoring

### Log Access
```bash
# OpenVPN logs
docker logs openvpn-server

# All services
docker-compose -f context/docker-compose.yml logs -f
```

## Troubleshooting

### Common Issues

1. **Container fails to start**:
   ```bash
   docker logs openvpn-server
   # Check for configuration errors
   ```

2. **Client connection issues**:
   - Verify firewall rules for UDP/TCP ports
   - Check client configuration matches server settings
   - Ensure PKI is properly initialized

3. **Performance issues**:
   - Monitor resource usage: `docker stats`
   - Adjust resource limits in docker-compose.yml
   - Check network MTU settings

### Health Checks
The deployment includes automated health monitoring. Failed containers are automatically restarted.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   OpenVPN       │    │   Admin Panel    │    │  Status Page    │
│   Server        │    │   (Alpine+PHP)   │    │   (Node.js)     │
│   UDP:1194      │    │   HTTP:8080      │    │   HTTP:8081     │
│   TCP:1195      │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  │
                    ┌─────────────────────────┐
                    │   Docker Network        │
                    │   openvpn_net          │
                    │   10.20.0.0/16         │
                    └─────────────────────────┘
```

## License

This project is open-source and available under the MIT License.