# OpenVPN Docker Deployment Makefile

.PHONY: help build test deploy clean security audit

# Configuration
COMPOSE_FILE ?= docker-compose.yml
REGISTRY ?= ghcr.io
IMAGE_NAME ?= openvpn-admin
TAG ?= latest

# Colors
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m

help: ## Show this help message
	@echo "OpenVPN Docker Deployment"
	@echo "========================="
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*##"; printf "\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Production Operations
init: ## Initialize production secrets
	@echo "$(GREEN)Initializing production secrets...$(NC)"
	@./scripts/init-secrets.sh
	@cp .env.example .env
	@echo "$(GREEN)✓ Production secrets initialized$(NC)"
	@echo "$(YELLOW)Remember to update .env with your production values$(NC)"

build: ## Build production images
	@echo "$(GREEN)Building production images...$(NC)"
	@docker-compose -f $(COMPOSE_FILE) build --no-cache
	@echo "$(GREEN)✓ Build completed$(NC)"

deploy: ## Deploy production environment
	@echo "$(GREEN)Deploying production environment...$(NC)"
	@docker-compose -f $(COMPOSE_FILE) up -d
	@echo "$(GREEN)✓ Production environment deployed$(NC)"
	@echo "Admin Panel: http://localhost:8080"
	@echo "Status Page: http://localhost:8081"
	@echo "Grafana: http://localhost:3000"
	@echo "Prometheus: http://localhost:9090"

stop: ## Stop all services
	@echo "$(YELLOW)Stopping all services...$(NC)"
	@docker-compose -f $(COMPOSE_FILE) down
	@echo "$(GREEN)✓ Services stopped$(NC)"

logs: ## View logs from all services
	@docker-compose -f $(COMPOSE_FILE) logs -f

##@ Testing
test: ## Run integration tests
	@echo "$(GREEN)Running integration tests...$(NC)"
	@./tests/integration-test.sh
	@echo "$(GREEN)✓ Tests completed$(NC)"

lint: ## Run code linting
	@echo "$(GREEN)Running code linting...$(NC)"
	@find . -name "*.sh" -exec shellcheck {} \;
	@docker run --rm -i hadolint/hadolint < admin/Dockerfile
	@yamllint docker-compose.yml docker-compose.prod.yml
	@echo "$(GREEN)✓ Linting completed$(NC)"

security-scan: ## Run security scanning
	@echo "$(GREEN)Running security scans...$(NC)"
	@trivy image $(IMAGE_NAME):$(TAG)
	@docker run --rm -v "$(PWD):/src" clair-scanner:latest
	@echo "$(GREEN)✓ Security scan completed$(NC)"

##@ Container Management
push: ## Push images to registry
	@echo "$(GREEN)Pushing images to registry...$(NC)"
	@docker tag $(IMAGE_NAME):$(TAG) $(REGISTRY)/$(IMAGE_NAME):$(TAG)
	@docker push $(REGISTRY)/$(IMAGE_NAME):$(TAG)
	@echo "$(GREEN)✓ Images pushed to registry$(NC)"

restart: ## Restart all services
	@echo "$(GREEN)Restarting all services...$(NC)"
	@docker-compose -f $(COMPOSE_FILE) restart
	@echo "$(GREEN)✓ Services restarted$(NC)"

rollback: ## Rollback to previous deployment
	@echo "$(YELLOW)Rolling back deployment...$(NC)"
	@if [ -f docker-compose.yml.backup ]; then \
		cp docker-compose.yml.backup docker-compose.yml && \
		docker-compose -f $(COMPOSE_FILE) up -d --remove-orphans; \
		echo "$(GREEN)✓ Rollback completed$(NC)"; \
	else \
		echo "$(RED)✗ No backup found for rollback$(NC)"; \
	fi

##@ Security
security: ## Apply security hardening
	@echo "$(GREEN)Applying security hardening...$(NC)"
	@sudo ./security/security-hardening.sh
	@echo "$(GREEN)✓ Security hardening applied$(NC)"

audit: ## Run security audit
	@echo "$(GREEN)Running security audit...$(NC)"
	@./security/security-audit.sh
	@echo "$(GREEN)✓ Security audit completed$(NC)"

##@ Maintenance
backup: ## Create certificate backup
	@echo "$(GREEN)Creating certificate backup...$(NC)"
	@docker exec openvpn-server /usr/local/bin/backup-certs.sh
	@echo "$(GREEN)✓ Backup completed$(NC)"

clean: ## Clean up containers, images, and volumes
	@echo "$(YELLOW)Cleaning up resources...$(NC)"
	@docker-compose -f $(COMPOSE_FILE) down -v --remove-orphans
	@docker system prune -af
	@echo "$(GREEN)✓ Cleanup completed$(NC)"

update: ## Update to latest images
	@echo "$(GREEN)Updating to latest images...$(NC)"
	@docker-compose -f $(COMPOSE_FILE) pull
	@echo "$(GREEN)✓ Update completed$(NC)"

##@ Client Management
client-create: ## Create a new client certificate (CLIENT_NAME=name)
	@if [ -z "$(CLIENT_NAME)" ]; then \
		echo "$(RED)Error: CLIENT_NAME is required$(NC)"; \
		echo "Usage: make client-create CLIENT_NAME=myclient"; \
		exit 1; \
	fi
	@echo "$(GREEN)Creating client certificate: $(CLIENT_NAME)$(NC)"
	@docker exec openvpn-server easyrsa build-client-full $(CLIENT_NAME) nopass
	@docker exec openvpn-server ovpn_getclient $(CLIENT_NAME) > $(CLIENT_NAME).ovpn
	@echo "$(GREEN)✓ Client certificate created: $(CLIENT_NAME).ovpn$(NC)"

client-list: ## List all client certificates
	@echo "$(GREEN)Listing client certificates...$(NC)"
	@docker exec openvpn-server ovpn_listclients

client-revoke: ## Revoke a client certificate (CLIENT_NAME=name)
	@if [ -z "$(CLIENT_NAME)" ]; then \
		echo "$(RED)Error: CLIENT_NAME is required$(NC)"; \
		echo "Usage: make client-revoke CLIENT_NAME=myclient"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Revoking client certificate: $(CLIENT_NAME)$(NC)"
	@docker exec openvpn-server ovpn_revokeclient $(CLIENT_NAME)
	@echo "$(GREEN)✓ Client certificate revoked: $(CLIENT_NAME)$(NC)"

##@ Monitoring
status: ## Show service status
	@echo "$(GREEN)Service Status:$(NC)"
	@docker-compose -f $(COMPOSE_FILE) ps
	@echo ""
	@echo "$(GREEN)Health Checks:$(NC)"
	@curl -s http://localhost:8080/health | jq . || echo "Admin panel not responding"
	@curl -s http://localhost:8081 >/dev/null && echo "Status page: OK" || echo "Status page: Not responding"

monitor: ## Open monitoring dashboard
	@echo "$(GREEN)Opening monitoring dashboard...$(NC)"
	@open http://localhost:3000 2>/dev/null || echo "Grafana: http://localhost:3000"
	@open http://localhost:9090 2>/dev/null || echo "Prometheus: http://localhost:9090"

##@ Documentation
docs: ## Generate documentation
	@echo "$(GREEN)Generating documentation...$(NC)"
	@echo "# OpenVPN Deployment Documentation" > docs/README.md
	@echo "Generated on: $(shell date)" >> docs/README.md
	@echo "" >> docs/README.md
	@echo "## Architecture" >> docs/README.md
	@docker-compose -f $(COMPOSE_FILE) config --services | sed 's/^/- /' >> docs/README.md
	@echo "$(GREEN)✓ Documentation generated$(NC)"