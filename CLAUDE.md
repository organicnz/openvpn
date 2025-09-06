# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Docker-based OpenVPN server deployment with the following components:

- **OpenVPN Server**: Main VPN service with UDP (1194) and TCP (1195) support
- **Admin Panel**: Web interface on port 8080 for OpenVPN management
- **Status Page**: Monitoring interface on port 8081 for connection status
- **Network**: Internal Docker network (10.20.0.0/16) with VPN client subnet (10.20.0.0/24)

## Common Commands

### Development and Deployment
- `docker-compose up -d`: Start all services in detached mode
- `docker-compose down`: Stop and remove all containers
- `docker-compose logs openvpn`: View OpenVPN server logs
- `docker-compose pull`: Update container images

### OpenVPN Management
- `docker-compose exec openvpn ovpn_genconfig -u udp://vpn.example.com`: Generate initial configuration
- `docker-compose exec openvpn ovpn_initpki`: Initialize PKI (first time only)
- `docker-compose exec openvpn easyrsa build-client-full CLIENT_NAME nopass`: Create client certificate
- `docker-compose exec openvpn ovpn_getclient CLIENT_NAME > CLIENT_NAME.ovpn`: Export client config
- `docker-compose exec openvpn ovpn_listclients`: List all client certificates
- `docker-compose exec openvpn ovpn_revokeclient CLIENT_NAME`: Revoke client certificate

### CI/CD Pipeline
The deployment is fully automated via GitHub Actions workflow in `.github/workflows/deploy.yml`:
- Triggered on push to main or manually via `workflow_dispatch`
- Sequential jobs: verify-env → deploy → test → monitor → client-management
- Uses GitHub Secrets for credentials (SERVER_HOST, SERVER_USER, AZURE_SSH_KEY, etc.)

## Key Configuration Files

### Docker Compose Structure
- `docker-compose.yml`: Uses YAML anchors for DRY configuration
- Environment variables defined with `x-openvpn-environment` anchor
- Security defaults applied via `x-security` and `x-defaults` anchors
- Resource limits and logging configured for all services

### OpenVPN Configuration
- `setup.sh`: Custom entrypoint script that creates environment file and starts OpenVPN
- `client_configs/base.conf`: Template for client configurations with security-hardened settings
- PKI and certificates stored in `openvpn_data` Docker volume

### Environment Variables
Key variables in `.env` (use `.env.example` as template):
- `OPENVPN_ADMIN_USERNAME/PASSWORD`: Admin panel credentials
- `VPN_DOMAIN`: Server domain for client configurations
- `OVPN_*` variables: OpenVPN-specific settings (optional overrides)

## Security Architecture

- **Encryption**: AES-256-GCM cipher with TLS 1.2+ minimum
- **Authentication**: Client certificates with optional duplicate-cn support
- **Network**: Isolated Docker network with controlled port exposure
- **Access Control**: Client-to-client communication enabled, management interface on localhost only
- **Logging**: Structured logging with rotation and monitoring via cron jobs

## Project Rules (.cursor/rules/openvpn-rules.mdc)

Important constraints from Cursor IDE rules:
- Never commit secrets - use GitHub Secrets exclusively
- Use specific Docker image tags, never `latest`
- All deployment via GitHub Actions workflow, no manual scripts
- Container restart policy: `unless-stopped`
- Fixed network subnet: 10.20.0.0/16
- Port forwarding restricted to 3005-3009 range
- Client certificate rotation every 90 days recommended

## Network Configuration

- **VPN Subnet**: 10.20.0.0/24 (clients)
- **Docker Network**: 10.20.0.0/16 (containers)
- **Port Mapping**: UDP 1194, TCP 1195, Admin 8080, Status 8081
- **DNS**: 8.8.8.8, 8.8.4.4 pushed to clients
- **Routing**: Full tunnel with client-to-client enabled

## Monitoring and Maintenance

- Automated health checks every 30 seconds
- Container restart on failure via `unless-stopped` policy
- Cron jobs for log rotation and service monitoring
- Status page provides real-time connection information
- Persistent data in `openvpn_data` Docker volume