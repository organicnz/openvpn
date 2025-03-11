# OpenVPN Docker Deployment

This repository contains a Docker Compose setup for deploying and managing an OpenVPN server with an admin panel and status page.

## Features

- OpenVPN server with both UDP and TCP support
- Client-to-client networking capability
- IPv6 forwarding support
- Administrative web panel
- Status monitoring page
- Persistent storage for configurations and certificates
- Automated health checks

## Prerequisites

- Docker and Docker Compose installed
- Basic understanding of networking and OpenVPN
- Port forwarding configured on your router/firewall (for external access)

## Quick Start

1. Clone this repository:
   ```
   git clone https://github.com/organicnz/openvpn.git
   cd openvpn
   ```

2. Start the services:
   ```
   docker-compose up -d
   ```

3. Initialize the PKI (first time only):
   ```
   docker-compose exec openvpn ovpn_genconfig -u udp://vpn.example.com
   docker-compose exec openvpn ovpn_initpki
   ```

4. Generate a client certificate:
   ```
   docker-compose exec openvpn easyrsa build-client-full CLIENT_NAME nopass
   docker-compose exec openvpn ovpn_getclient CLIENT_NAME > CLIENT_NAME.ovpn
   ```

## Configuration

### Environment Variables

You can customize the deployment by setting these environment variables:

- `OPENVPN_ADMIN_USERNAME`: Username for the admin panel (default: admin)
- `OPENVPN_ADMIN_PASSWORD`: Password for the admin panel (default: admin)

### Network Configuration

The OpenVPN server is configured with the following network:
- Server network: 10.20.0.0/24
- Docker internal network: 10.20.0.0/16

## Service Access

- OpenVPN Server: UDP port 1194, TCP port 1195
- Admin Panel: http://your-server-ip:8080
- Status Page: http://your-server-ip:8081

## Maintenance

### Backing Up Configurations

All OpenVPN configurations, certificates and keys are stored in the `openvpn_data` Docker volume. 
You can create a backup with:

```
docker run --rm -v openvpn_data:/data -v $(pwd):/backup alpine tar -czvf /backup/openvpn-backup.tar.gz /data
```

### Restoring a Backup

```
docker run --rm -v openvpn_data:/data -v $(pwd):/backup alpine sh -c "rm -rf /data/* && tar -xzvf /backup/openvpn-backup.tar.gz -C /"
```

## Troubleshooting

### Container Health Check Failures

If the container fails health checks, you can check logs with:

```
docker-compose logs openvpn
```

Common issues:
- Missing configuration file: Make sure to run the initialization steps
- Permission issues: Check file permissions in the mounted volumes
- Network conflicts: Ensure there are no conflicts with the 10.20.0.0/24 subnet

## License

This project is open-source and available under the MIT License. 