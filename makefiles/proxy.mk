# Proxy Stack (Traefik) Deployment Makefile
# Usage: make deploy-proxy TARGET=primary DOMAIN=example.com SUBDOMAIN=traefik

# Configuration
ANSIBLE_DIR := .
INVENTORY := $(ANSIBLE_DIR)/inventory/hosts.yml
PLAYBOOKS_DIR := $(ANSIBLE_DIR)/playbooks
VARS_DIR := $(ANSIBLE_DIR)/vars

# Default values
ENV ?= production
TARGET ?=
DOMAIN ?=
SUBDOMAIN ?=
VERBOSE ?=
CHECK ?= false
TAIL ?= 50
SERVICE ?=

# Color output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

# Proxy stack path
PROXY_STACK_PATH := /opt/proxy-stack

# Build ansible-playbook command
ANSIBLE_CMD := ansible-playbook -i $(INVENTORY)

# Add optional flags
ifdef VERBOSE
	ANSIBLE_CMD += -$(VERBOSE)
endif
ifeq ($(CHECK),true)
	ANSIBLE_CMD += --check --diff
endif

# Build extra vars
EXTRA_VARS := target_hosts=$(TARGET) environment=$(ENV)
ifdef DOMAIN
	EXTRA_VARS += my_domain=$(DOMAIN)
endif
ifdef SUBDOMAIN
	EXTRA_VARS += subdomain=$(SUBDOMAIN)
endif

#
# Proxy Deployment Targets
#

.PHONY: deploy-proxy
deploy-proxy: validate-target ## Deploy proxy stack (TARGET=host [DOMAIN=example.com] [SUBDOMAIN=traefik])
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@echo "$(GREEN)Deploying Proxy Stack (Traefik)$(RESET)"
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@echo "$(BLUE)Environment:$(RESET) $(ENV)"
	@echo "$(BLUE)Target:$(RESET)      $(TARGET)"
	@[ -n "$(DOMAIN)" ] && echo "$(BLUE)Domain:$(RESET)      $(DOMAIN)" || echo "$(BLUE)Domain:$(RESET)      (using default from vars)"
	@[ -n "$(SUBDOMAIN)" ] && echo "$(BLUE)Subdomain:$(RESET)   $(SUBDOMAIN)" || echo "$(BLUE)Subdomain:$(RESET)   (using default from vars)"
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@$(ANSIBLE_CMD) \
		--extra-vars "$(EXTRA_VARS)" \
		$(PLAYBOOKS_DIR)/deploy-proxy.yml

.PHONY: dry-run
dry-run: ## Dry run proxy deployment (TARGET=host [DOMAIN=] [SUBDOMAIN=])
	@$(MAKE) deploy-proxy CHECK=true

#
# Proxy Management Targets
#

.PHONY: status
status: validate-target ## Check proxy stack status (TARGET=host)
	@echo "$(BLUE)Checking proxy stack status on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose ps 2>/dev/null || docker-compose ps"

.PHONY: logs
logs: validate-target ## View proxy stack logs (TARGET=host [SERVICE=traefik] [TAIL=50])
	@echo "$(BLUE)Fetching proxy logs from $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose logs --tail=$(TAIL) $(SERVICE) 2>/dev/null || docker-compose logs --tail=$(TAIL) $(SERVICE)"

.PHONY: restart
restart: validate-target ## Restart proxy stack (TARGET=host [SERVICE=traefik])
	@echo "$(YELLOW)Restarting proxy stack on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose restart $(SERVICE) 2>/dev/null || docker-compose restart $(SERVICE)"

.PHONY: stop
stop: validate-target ## Stop proxy stack (TARGET=host)
	@echo "$(YELLOW)Stopping proxy stack on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose stop 2>/dev/null || docker-compose stop"

.PHONY: start
start: validate-target ## Start proxy stack (TARGET=host)
	@echo "$(GREEN)Starting proxy stack on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose start 2>/dev/null || docker-compose start"

.PHONY: down
down: validate-target ## Stop and remove proxy stack (TARGET=host)
	@echo "$(RED)Warning: This will stop and remove all proxy containers$(RESET)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		ansible $(TARGET) -i $(INVENTORY) -m shell \
			-a "cd $(PROXY_STACK_PATH) && docker compose down 2>/dev/null || docker-compose down"; \
	else \
		echo "$(RED)Operation cancelled$(RESET)"; \
	fi

.PHONY: pull
pull: validate-target ## Pull latest proxy images (TARGET=host)
	@echo "$(BLUE)Pulling proxy images on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose pull 2>/dev/null || docker-compose pull"

.PHONY: update
update: pull deploy-proxy ## Pull images and redeploy proxy (TARGET=host)

#
# Utility Targets
#

.PHONY: list-hosts
list-hosts: ## List all inventory hosts and groups
	@echo "$(GREEN)Inventory Hosts:$(RESET)"
	@ansible-inventory -i $(INVENTORY) --graph

.PHONY: ping
ping: ## Ping target host (TARGET=host)
	@if [ -z "$(TARGET)" ]; then \
		echo "$(YELLOW)No TARGET specified, pinging all hosts$(RESET)"; \
		ansible all -i $(INVENTORY) -m ping; \
	else \
		ansible $(TARGET) -i $(INVENTORY) -m ping; \
	fi

.PHONY: show-config
show-config: ## Show proxy configuration files
	@echo "$(GREEN)Proxy Configuration Files:$(RESET)"
	@echo ""
	@echo "$(BLUE)Base config:$(RESET) $(VARS_DIR)/proxy.yml"
	@[ -f "$(VARS_DIR)/proxy.yml" ] && cat $(VARS_DIR)/proxy.yml || echo "  File not found"
	@echo ""
	@echo "$(BLUE)Environment config:$(RESET) $(VARS_DIR)/environments/$(ENV).yml"
	@[ -f "$(VARS_DIR)/environments/$(ENV).yml" ] && cat $(VARS_DIR)/environments/$(ENV).yml || echo "  File not found (optional)"

.PHONY: check-syntax
check-syntax: ## Check playbook syntax
	@echo "$(BLUE)Checking playbook syntax...$(RESET)"
	@ansible-playbook -i $(INVENTORY) --syntax-check $(PLAYBOOKS_DIR)/deploy-proxy.yml
	@echo "$(GREEN)✓ Syntax OK$(RESET)"

.PHONY: validate-target
validate-target:
	@if [ -z "$(TARGET)" ]; then \
		echo "$(RED)Error: TARGET parameter required$(RESET)"; \
		echo "Usage: make deploy-proxy TARGET=primary"; \
		echo ""; \
		echo "Run 'make list-hosts' to see available hosts"; \
		exit 1; \
	fi

#
# Help
#

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)╔════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(GREEN)║           Proxy Stack (Traefik) Management             ║$(RESET)"
	@echo "$(GREEN)╚════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(BLUE)Quick Start:$(RESET)"
	@echo "  make deploy-proxy TARGET=primary"
	@echo "  make deploy-proxy TARGET=primary DOMAIN=example.com SUBDOMAIN=traefik"
	@echo "  make status TARGET=primary"
	@echo "  make logs TARGET=primary TAIL=100"
	@echo ""
	@echo "$(BLUE)Available Commands:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Parameters:$(RESET)"
	@echo "  TARGET     Target host (required, e.g., primary, monitor)"
	@echo "  ENV        Environment name (default: production)"
	@echo "  DOMAIN     Base domain for proxy (optional, e.g., example.com)"
	@echo "  SUBDOMAIN  Subdomain for Traefik dashboard (optional, e.g., traefik)"
	@echo "  SERVICE    Specific service for logs/restart (default: all services)"
	@echo "  TAIL       Number of log lines (default: 50)"
	@echo "  VERBOSE    Ansible verbosity: v, vv, vvv, or vvvv"
	@echo "  CHECK      Set to 'true' for dry-run mode"
	@echo ""
	@echo "$(BLUE)Examples:$(RESET)"
	@echo ""
	@echo "  $(YELLOW)# Deploy proxy with custom domain$(RESET)"
	@echo "  make deploy-proxy TARGET=primary DOMAIN=example.com SUBDOMAIN=traefik"
	@echo ""
	@echo "  $(YELLOW)# Deploy proxy using defaults from vars$(RESET)"
	@echo "  make deploy-proxy TARGET=primary"
	@echo ""
	@echo "  $(YELLOW)# Dry run deployment$(RESET)"
	@echo "  make dry-run TARGET=primary DOMAIN=example.com"
	@echo ""
	@echo "  $(YELLOW)# Check proxy status$(RESET)"
	@echo "  make status TARGET=primary"
	@echo ""
	@echo "  $(YELLOW)# View proxy logs (last 100 lines)$(RESET)"
	@echo "  make logs TARGET=primary TAIL=100"
	@echo ""
	@echo "  $(YELLOW)# View logs for specific service$(RESET)"
	@echo "  make logs TARGET=primary SERVICE=traefik TAIL=200"
	@echo ""
	@echo "  $(YELLOW)# Restart entire proxy stack$(RESET)"
	@echo "  make restart TARGET=primary"
	@echo ""
	@echo "  $(YELLOW)# Restart specific service$(RESET)"
	@echo "  make restart TARGET=primary SERVICE=traefik"
	@echo ""
	@echo "  $(YELLOW)# Update proxy (pull latest images and redeploy)$(RESET)"
	@echo "  make update TARGET=primary"
	@echo ""
	@echo "  $(YELLOW)# Pull latest images without deploying$(RESET)"
	@echo "  make pull TARGET=primary"
	@echo ""
	@echo "  $(YELLOW)# Stop proxy stack$(RESET)"
	@echo "  make stop TARGET=primary"
	@echo ""
	@echo "  $(YELLOW)# Start proxy stack$(RESET)"
	@echo "  make start TARGET=primary"
	@echo ""
	@echo "$(BLUE)Configuration:$(RESET)"
	@echo "  - Base vars: vars/proxy.yml"
	@echo "  - Environment vars: vars/environments/$(ENV).yml"
	@echo "  - Stack path: $(PROXY_STACK_PATH)"
	@echo ""

.DEFAULT_GOAL := help
