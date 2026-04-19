# Unified Ansible Deployment Makefile
# Manages both Proxy (Traefik) and Application Stacks
# Usage: 
#   make proxy-deploy TARGET=primary DOMAIN=example.com
#   make stack-deploy STACK=media ENV=production TARGET=media_host

# Configuration
ANSIBLE_DIR := .
INVENTORY := $(ANSIBLE_DIR)/inventory/hosts.yml
PLAYBOOKS_DIR := $(ANSIBLE_DIR)/playbooks
VARS_DIR := $(ANSIBLE_DIR)/vars
STACKS_DIR := $(VARS_DIR)/stacks

# Default values
STACK ?=
ENV ?= production
TARGET ?=
DOMAIN ?=
SUBDOMAIN ?=
TAGS ?=
SKIP_TAGS ?=
SERIAL ?= 1
CHECK ?= false
VERBOSE ?=
TAIL ?= 50
SERVICE ?=

# Color output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

# Paths
PROXY_STACK_PATH := /opt/proxy-stack
AVAILABLE_STACKS := $(patsubst $(STACKS_DIR)/%/,%,$(sort $(dir $(wildcard $(STACKS_DIR)/*/))))

# Build ansible-playbook command
ANSIBLE_CMD := ansible-playbook -i $(INVENTORY)

ifdef TAGS
	ANSIBLE_CMD += --tags "$(TAGS)"
endif
ifdef SKIP_TAGS
	ANSIBLE_CMD += --skip-tags "$(SKIP_TAGS)"
endif
ifdef VERBOSE
	ANSIBLE_CMD += -$(VERBOSE)
endif
ifeq ($(CHECK),true)
	ANSIBLE_CMD += --check --diff
endif

#
# PROXY STACK TARGETS (Traefik)
#

.PHONY: proxy-deploy
proxy-deploy: validate-target ## Deploy proxy stack (TARGET=host [DOMAIN=example.com] [SUBDOMAIN=traefik])
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@echo "$(GREEN)Deploying Proxy Stack (Traefik)$(RESET)"
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@echo "$(BLUE)Environment:$(RESET) $(ENV)"
	@echo "$(BLUE)Target:$(RESET)      $(TARGET)"
	@[ -n "$(DOMAIN)" ] && echo "$(BLUE)Domain:$(RESET)      $(DOMAIN)" || echo "$(BLUE)Domain:$(RESET)      (using default from vars)"
	@[ -n "$(SUBDOMAIN)" ] && echo "$(BLUE)Subdomain:$(RESET)   $(SUBDOMAIN)" || echo "$(BLUE)Subdomain:$(RESET)   (using default from vars)"
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@$(ANSIBLE_CMD) \
		--extra-vars "target_hosts=$(TARGET) environment=$(ENV) $(if $(DOMAIN),my_domain=$(DOMAIN)) $(if $(SUBDOMAIN),subdomain=$(SUBDOMAIN))" \
		$(PLAYBOOKS_DIR)/deploy-proxy.yml

.PHONY: proxy-dry-run
proxy-dry-run: ## Dry run proxy deployment (TARGET=host [DOMAIN=] [SUBDOMAIN=])
	@$(MAKE) proxy-deploy CHECK=true

.PHONY: proxy-status
proxy-status: validate-target ## Check proxy stack status (TARGET=host)
	@echo "$(BLUE)Checking proxy stack status on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose ps 2>/dev/null || docker-compose ps"

.PHONY: proxy-logs
proxy-logs: validate-target ## View proxy stack logs (TARGET=host [SERVICE=traefik] [TAIL=50])
	@echo "$(BLUE)Fetching proxy logs from $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose logs --tail=$(TAIL) $(SERVICE) 2>/dev/null || docker-compose logs --tail=$(TAIL) $(SERVICE)"

.PHONY: proxy-restart
proxy-restart: validate-target ## Restart proxy stack (TARGET=host [SERVICE=traefik])
	@echo "$(YELLOW)Restarting proxy stack on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose restart $(SERVICE) 2>/dev/null || docker-compose restart $(SERVICE)"

.PHONY: proxy-stop
proxy-stop: validate-target ## Stop proxy stack (TARGET=host)
	@echo "$(YELLOW)Stopping proxy stack on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose stop 2>/dev/null || docker-compose stop"

.PHONY: proxy-start
proxy-start: validate-target ## Start proxy stack (TARGET=host)
	@echo "$(GREEN)Starting proxy stack on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose start 2>/dev/null || docker-compose start"

.PHONY: proxy-down
proxy-down: validate-target ## Stop and remove proxy stack (TARGET=host)
	@echo "$(RED)Warning: This will stop and remove all proxy containers$(RESET)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		ansible $(TARGET) -i $(INVENTORY) -m shell \
			-a "cd $(PROXY_STACK_PATH) && docker compose down 2>/dev/null || docker-compose down"; \
	else \
		echo "$(RED)Operation cancelled$(RESET)"; \
	fi

.PHONY: proxy-pull
proxy-pull: validate-target ## Pull latest proxy images (TARGET=host)
	@echo "$(BLUE)Pulling proxy images on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(PROXY_STACK_PATH) && docker compose pull 2>/dev/null || docker-compose pull"

.PHONY: proxy-update
proxy-update: proxy-pull proxy-deploy ## Pull images and redeploy proxy (TARGET=host)

.PHONY: proxy-config
proxy-config: ## Show proxy configuration files
	@echo "$(GREEN)Proxy Configuration Files:$(RESET)"
	@echo ""
	@echo "$(BLUE)Base config:$(RESET) $(VARS_DIR)/proxy.yml"
	@[ -f "$(VARS_DIR)/proxy.yml" ] && cat $(VARS_DIR)/proxy.yml || echo "  File not found"
	@echo ""
	@echo "$(BLUE)Environment config:$(RESET) $(VARS_DIR)/environments/$(ENV).yml"
	@[ -f "$(VARS_DIR)/environments/$(ENV).yml" ] && cat $(VARS_DIR)/environments/$(ENV).yml || echo "  File not found (optional)"

#
# APPLICATION STACK TARGETS
#

.PHONY: stack-deploy
stack-deploy: validate-stack validate-target ## Deploy application stack (STACK=name ENV=prod TARGET=host)
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@echo "$(GREEN)Deploying Application Stack$(RESET)"
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@echo "$(BLUE)Stack:$(RESET)       $(STACK)"
	@echo "$(BLUE)Environment:$(RESET) $(ENV)"
	@echo "$(BLUE)Target:$(RESET)      $(TARGET)"
	@echo "$(BLUE)Serial:$(RESET)      $(SERIAL)"
	@[ -n "$(TAGS)" ] && echo "$(BLUE)Tags:$(RESET)        $(TAGS)" || true
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@$(ANSIBLE_CMD) \
		--extra-vars "stack_type=$(STACK) environment=$(ENV) deploy_serial=$(SERIAL) $(if $(TARGET),target_hosts=$(TARGET)) $(if $(DOMAIN),my_domain=$(DOMAIN)) $(if $(SUBDOMAIN),subdomain=$(SUBDOMAIN))" \
		$(PLAYBOOKS_DIR)/deploy-stack.yml

.PHONY: stack-dry-run
stack-dry-run: ## Dry run stack deployment (STACK=name ENV=prod TARGET=host)
	@$(MAKE) stack-deploy CHECK=true

.PHONY: stack-deploy-all
stack-deploy-all: validate-stack ## Deploy stack to all hosts in target group
	@echo "$(YELLOW)Warning: Deploying to ALL hosts in target group$(RESET)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(MAKE) stack-deploy; \
	else \
		echo "$(RED)Deployment cancelled$(RESET)"; \
	fi

.PHONY: stack-status
stack-status: validate-target require-stack-path ## Check stack status (STACK=name TARGET=host)
	@echo "$(BLUE)Checking status of $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose ps 2>/dev/null || docker-compose ps"

.PHONY: stack-logs
stack-logs: validate-target require-stack-path ## View stack logs (STACK=name TARGET=host [SERVICE=svc TAIL=50])
	@echo "$(BLUE)Fetching logs for $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose logs --tail=$(TAIL) $(SERVICE) 2>/dev/null || docker-compose logs --tail=$(TAIL) $(SERVICE)"

.PHONY: stack-restart
stack-restart: validate-target require-stack-path ## Restart stack (STACK=name TARGET=host [SERVICE=svc])
	@echo "$(YELLOW)Restarting $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose restart $(SERVICE) 2>/dev/null || docker-compose restart $(SERVICE)"

.PHONY: stack-stop
stack-stop: validate-target require-stack-path ## Stop stack (STACK=name TARGET=host)
	@echo "$(YELLOW)Stopping $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose stop 2>/dev/null || docker-compose stop"

.PHONY: stack-start
stack-start: validate-target require-stack-path ## Start stack (STACK=name TARGET=host)
	@echo "$(GREEN)Starting $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose start 2>/dev/null || docker-compose start"

.PHONY: stack-down
stack-down: validate-target require-stack-path ## Stop and remove stack (STACK=name TARGET=host)
	@echo "$(RED)Warning: This will stop and remove all containers for $(STACK)$(RESET)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		ansible $(TARGET) -i $(INVENTORY) -m shell \
			-a "cd $(STACK_PATH) && docker compose down 2>/dev/null || docker-compose down"; \
	else \
		echo "$(RED)Operation cancelled$(RESET)"; \
	fi

.PHONY: stack-pull
stack-pull: validate-target require-stack-path ## Pull latest images (STACK=name TARGET=host)
	@echo "$(BLUE)Pulling images for $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose pull 2>/dev/null || docker-compose pull"

.PHONY: stack-update
stack-update: stack-pull stack-deploy ## Pull images and redeploy (STACK=name ENV=prod TARGET=host)

.PHONY: stack-config
stack-config: validate-stack ## Show stack configuration (STACK=name ENV=prod)
	@echo "$(GREEN)Configuration for $(STACK) ($(ENV)):$(RESET)"
	@echo ""
	@echo "$(BLUE)Base config:$(RESET) $(STACKS_DIR)/$(STACK)/base.yml"
	@[ -f "$(STACKS_DIR)/$(STACK)/base.yml" ] && cat $(STACKS_DIR)/$(STACK)/base.yml || echo "  File not found"
	@echo ""
	@echo "$(BLUE)Environment config:$(RESET) $(STACKS_DIR)/$(STACK)/$(ENV).yml"
	@[ -f "$(STACKS_DIR)/$(STACK)/$(ENV).yml" ] && cat $(STACKS_DIR)/$(STACK)/$(ENV).yml || echo "  File not found"

#
# UTILITY TARGETS
#

.PHONY: list-stacks
list-stacks: ## List all available stacks with their environments
	@echo "$(GREEN)Available Stacks:$(RESET)"
	@for stack in $(AVAILABLE_STACKS); do \
		echo "$(BLUE)$$stack$(RESET)"; \
		if [ -d "$(STACKS_DIR)/$$stack" ]; then \
			for env_file in $(STACKS_DIR)/$$stack/*.yml; do \
				env=$$(basename $$env_file .yml); \
				echo "  └─ $$env"; \
			done; \
		fi; \
	done

.PHONY: list-hosts
list-hosts: ## List all inventory hosts and groups
	@echo "$(GREEN)Inventory Hosts:$(RESET)"
	@ansible-inventory -i $(INVENTORY) --graph

.PHONY: ping
ping: ## Ping hosts (TARGET=host_pattern)
	@ansible $(or $(TARGET),all) -i $(INVENTORY) -m ping

.PHONY: facts
facts: validate-target ## Gather facts from target (TARGET=host)
	@ansible $(TARGET) -i $(INVENTORY) -m setup

.PHONY: check-syntax
check-syntax: ## Check all playbook syntax
	@echo "$(BLUE)Checking proxy playbook syntax...$(RESET)"
	@ansible-playbook -i $(INVENTORY) --syntax-check $(PLAYBOOKS_DIR)/deploy-proxy.yml
	@echo "$(BLUE)Checking stack playbook syntax...$(RESET)"
	@ansible-playbook -i $(INVENTORY) --syntax-check $(PLAYBOOKS_DIR)/deploy-stack.yml
	@echo "$(GREEN)✓ All syntax checks passed$(RESET)"

.PHONY: init-stack
init-stack: ## Initialize new stack structure (STACK=name)
	@if [ -z "$(STACK)" ]; then \
		echo "$(RED)Error: STACK parameter required$(RESET)"; \
		echo "Usage: make init-stack STACK=mystack"; \
		exit 1; \
	fi
	@echo "$(GREEN)Creating stack structure for: $(STACK)$(RESET)"
	@mkdir -p $(STACKS_DIR)/$(STACK)
	@echo "---\n# Base configuration for $(STACK) stack\n$(STACK)_stack_base_path: \"/opt/$(STACK)\"\n\n$(STACK)_stack:\n  base_path: \"{{ $(STACK)_stack_base_path }}\"\n  # Add your base configuration here\n\n$(STACK)_services:\n  # Add your services here" > $(STACKS_DIR)/$(STACK)/base.yml
	@echo "---\n# Production environment overrides" > $(STACKS_DIR)/$(STACK)/production.yml
	@echo "---\n# Staging environment overrides" > $(STACKS_DIR)/$(STACK)/staging.yml
	@echo "$(GREEN)✓ Stack structure created at: $(STACKS_DIR)/$(STACK)$(RESET)"
	@echo "  - base.yml"
	@echo "  - production.yml"
	@echo "  - staging.yml"

#
# VALIDATION HELPERS
#

.PHONY: validate-stack
validate-stack:
	@if [ -z "$(STACK)" ]; then \
		echo "$(RED)Error: STACK parameter required$(RESET)"; \
		echo "Usage: make stack-deploy STACK=media ENV=production TARGET=host"; \
		echo ""; \
		echo "Available stacks:"; \
		for stack in $(AVAILABLE_STACKS); do echo "  - $$stack"; done; \
		exit 1; \
	fi
	@if [ ! -d "$(STACKS_DIR)/$(STACK)" ]; then \
		echo "$(RED)Error: Stack '$(STACK)' not found$(RESET)"; \
		echo "Expected directory: $(STACKS_DIR)/$(STACK)"; \
		echo ""; \
		echo "Available stacks:"; \
		for stack in $(AVAILABLE_STACKS); do echo "  - $$stack"; done; \
		exit 1; \
	fi
	@if [ ! -f "$(STACKS_DIR)/$(STACK)/base.yml" ]; then \
		echo "$(RED)Error: base.yml not found for stack '$(STACK)'$(RESET)"; \
		exit 1; \
	fi
	@if [ ! -f "$(STACKS_DIR)/$(STACK)/$(ENV).yml" ]; then \
		echo "$(YELLOW)Warning: $(ENV).yml not found for stack '$(STACK)', using only base.yml$(RESET)"; \
	fi

.PHONY: validate-target
validate-target:
	@if [ -z "$(TARGET)" ]; then \
		echo "$(RED)Error: TARGET parameter required$(RESET)"; \
		echo ""; \
		echo "Run 'make list-hosts' to see available hosts"; \
		exit 1; \
	fi

.PHONY: require-stack-path
require-stack-path:
	@if [ -z "$(STACK)" ]; then \
		echo "$(RED)Error: STACK parameter required$(RESET)"; \
		exit 1; \
	fi
	$(eval STACK_PATH := $(shell grep -h "$(STACK)_stack_base_path:" $(STACKS_DIR)/$(STACK)/*.yml 2>/dev/null | head -1 | cut -d'"' -f2))
	@if [ -z "$(STACK_PATH)" ]; then \
		echo "$(RED)Error: Could not determine stack path from vars$(RESET)"; \
		echo "Make sure $(STACK)_stack_base_path is defined in your stack vars"; \
		exit 1; \
	fi

#
# HELP
#

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)╔════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(GREEN)║       Unified Ansible Deployment Management            ║$(RESET)"
	@echo "$(GREEN)╚════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(BLUE)═══ PROXY STACK (Traefik) ═══$(RESET)"
	@echo ""
	@echo "$(YELLOW)Deployment:$(RESET)"
	@echo "  make proxy-deploy TARGET=primary [DOMAIN=example.com] [SUBDOMAIN=traefik]"
	@echo "  make proxy-dry-run TARGET=primary"
	@echo ""
	@echo "$(YELLOW)Management:$(RESET)"
	@echo "  make proxy-status TARGET=primary"
	@echo "  make proxy-logs TARGET=primary [SERVICE=traefik] [TAIL=100]"
	@echo "  make proxy-restart TARGET=primary [SERVICE=traefik]"
	@echo "  make proxy-update TARGET=primary"
	@echo "  make proxy-config"
	@echo ""
	@echo "$(BLUE)═══ APPLICATION STACKS ═══$(RESET)"
	@echo ""
	@echo "$(YELLOW)Deployment:$(RESET)"
	@echo "  make stack-deploy STACK=media ENV=production TARGET=media_host"
	@echo "  make stack-dry-run STACK=media ENV=production TARGET=media_host"
	@echo "  make stack-deploy-all STACK=media ENV=production"
	@echo ""
	@echo "$(YELLOW)Management:$(RESET)"
	@echo "  make stack-status STACK=media TARGET=media_host"
	@echo "  make stack-logs STACK=media TARGET=media_host [SERVICE=sonarr] [TAIL=100]"
	@echo "  make stack-restart STACK=media TARGET=media_host [SERVICE=radarr]"
	@echo "  make stack-update STACK=media ENV=production TARGET=media_host"
	@echo "  make stack-config STACK=media ENV=production"
	@echo ""
	@echo "$(BLUE)═══ UTILITIES ═══$(RESET)"
	@echo ""
	@echo "$(YELLOW)Discovery:$(RESET)"
	@echo "  make list-stacks              # List all available stacks"
	@echo "  make list-hosts               # List inventory hosts"
	@echo "  make ping [TARGET=host]       # Ping hosts"
	@echo ""
	@echo "$(YELLOW)Management:$(RESET)"
	@echo "  make init-stack STACK=name    # Initialize new stack structure"
	@echo "  make check-syntax             # Check playbook syntax"
	@echo "  make facts TARGET=host        # Gather facts from target"
	@echo ""
	@echo "$(BLUE)═══ ALL COMMANDS ═══$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-25s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Common Parameters:$(RESET)"
	@echo "  TARGET     Target host or group (required for most operations)"
	@echo "  ENV        Environment: production, staging (default: production)"
	@echo "  STACK      Stack name (for stack-* commands)"
	@echo "  DOMAIN     Base domain (optional)"
	@echo "  SUBDOMAIN  Subdomain (optional)"
	@echo "  SERVICE    Specific service name (for logs/restart)"
	@echo "  TAIL       Number of log lines (default: 50)"
	@echo "  TAGS       Ansible tags to run (comma-separated)"
	@echo "  SKIP_TAGS  Ansible tags to skip (comma-separated)"
	@echo "  VERBOSE    Ansible verbosity: v, vv, vvv, or vvvv"
	@echo "  CHECK      Set to 'true' for dry-run mode"
	@echo ""

.DEFAULT_GOAL := help
