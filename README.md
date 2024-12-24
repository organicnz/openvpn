# OpenVPN Server Setup

This repository contains the configuration for a Pritunl VPN server using Docker Compose.

## Prerequisites

- Docker and Docker Compose
- Git
- SSH access to the deployment server

## Environment Variables

Create a `.env` file with the following variables:
```env
MONGO_USER=your_mongo_user
MONGO_PASSWORD=your_mongo_password
PRITUNL_ADMIN_USERNAME=your_pritunl_admin
PRITUNL_ADMIN_PASSWORD=your_pritunl_password
DOCKER_USERNAME=your_docker_username  # Optional
DOCKER_TOKEN=your_docker_token        # Optional
```

## GitHub Secrets

The following secrets need to be set in your GitHub repository:

- `AZURE_SSH_KEY`: SSH private key for deployment
- `MONGO_USER`: MongoDB username
- `MONGO_PASSWORD`: MongoDB password
- `PRITUNL_ADMIN_USERNAME`: Pritunl admin username
- `PRITUNL_ADMIN_PASSWORD`: Pritunl admin password
- `DOCKER_USERNAME`: Docker Hub username (optional)
- `DOCKER_TOKEN`: Docker Hub access token (optional)

## CI/CD Pipeline

The repository uses GitHub Actions for continuous integration and deployment. The workflow "Deploy and Test" runs on every push to the main branch and includes:

### Deployment Phase:
1. Checks out the code
2. Creates necessary configuration files
3. Deploys to the Azure VM
4. Pulls required Docker images
5. Starts the services

### Testing Phase:
After successful deployment, the workflow automatically tests:
1. MongoDB connectivity
2. Pritunl API accessibility
3. Required port availability (80, 443, 16648, 3005-3009)

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
- 80: HTTP
- 443: HTTPS
- 16648: OpenVPN (UDP/TCP)
- 3005-3009: Additional ports

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
docker-compose logs pritunl
docker-compose logs pritunl-mongodb
```

2. Verify port availability:
```bash
nc -zv localhost 443
nc -zv localhost 16648
```

3. Check MongoDB connectivity:
```bash
docker exec pritunl-mongodb mongosh --eval "db.adminCommand('ping')"
```

4. Test Pritunl API:
```bash
curl -k https://localhost:443
``` 