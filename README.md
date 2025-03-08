# OpenVPN Server Setup

This repository contains the configuration for an OpenVPN server with a simple admin panel using Docker Compose.

## Prerequisites

- Docker and Docker Compose
- Git
- SSH access to the deployment server

## Environment Variables

Create a `.env` file with the following variables:
```env
OPENVPN_ADMIN_USERNAME=admin
OPENVPN_ADMIN_PASSWORD=your_secure_password
DOCKER_USERNAME=your_docker_username  # Optional
DOCKER_TOKEN=your_docker_token        # Optional
GH_TOKEN=your_github_token            # Optional
```

## GitHub Secrets

The following secrets need to be set in your GitHub repository:

- `AZURE_SSH_KEY`: SSH private key for deployment
- `SERVER_HOST`: Hostname or IP of the deployment server
- `SERVER_USER`: Username for SSH connection to the deployment server
- `OPENVPN_ADMIN_USERNAME`: Admin panel username
- `OPENVPN_ADMIN_PASSWORD`: Admin panel password
- `DOCKER_USERNAME`: Docker Hub username (optional)
- `DOCKER_TOKEN`: Docker Hub access token (optional)
- `GH_TOKEN`: GitHub token (optional)

## CI/CD Pipeline

The repository uses GitHub Actions for continuous integration and deployment. The workflow "Deploy OpenVPN" runs on every push to the main branch and includes:

### Deployment Phase:
1. Checks out the code
2. Creates necessary configuration files
3. Deploys to the server
4. Pulls required Docker images
5. Starts the services

### Testing Phase:
After successful deployment, the workflow automatically tests:
1. Container status
2. Port availability
3. OpenVPN initialization

## Manual Deployment

```bash
# Clone the repository
git clone https://github.com/organicnz/openvpn.git
cd openvpn

# Create .env file
cp .env.example .env
# Edit .env with your values

# Start the services
docker-compose up -d

# Check status
docker-compose ps
```

## Ports

The following ports are used:
- 1194: OpenVPN (UDP/TCP)
- 8080: Admin Panel Web Interface
- 8081: OpenVPN Status Page
- 3005-3009: Additional port forwarding range

## Accessing the Admin Interfaces

- Admin Panel: http://your-server-ip:8080
- Status Page: http://your-server-ip:8081

## Client Management

To create a new client certificate:
```bash
docker-compose exec openvpn easyrsa build-client-full CLIENT_NAME nopass
docker-compose exec openvpn ovpn_getclient CLIENT_NAME > CLIENT_NAME.ovpn
```

To revoke a client certificate:
```bash
docker-compose exec openvpn ovpn_revokeclient CLIENT_NAME
```

## Maintenance

To update the services:
```bash
docker-compose pull
docker-compose up -d
```

To view logs:
```bash
docker-compose logs -f
```

## Troubleshooting

If you encounter issues:

1. Check container logs:
```bash
docker-compose logs openvpn
docker-compose logs openvpn-admin
docker-compose logs openvpn-status
```

2. Verify port availability:
```bash
nc -zv localhost 1194
nc -zv localhost 8080
```

3. Check OpenVPN status:
```bash
docker-compose exec openvpn cat /tmp/openvpn-status.log
```

4. Test OpenVPN management interface:
```bash
echo "status" | nc localhost 7505
``` 