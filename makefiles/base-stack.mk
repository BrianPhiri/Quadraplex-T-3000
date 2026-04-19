# Ansible Stack Deployment Makefile - Environment/Profile Based
# Usage: make deploy STACK=media ENV=production TARGET=media_host

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
TAGS ?=
SKIP_TAGS ?=
SERIAL ?= 1
CHECK ?= false
VERBOSE ?=
DOMAIN ?=
SUBDOMAIN ?=

# Color output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

# Available stacks (auto-discovered from vars/stacks directory)
AVAILABLE_STACKS := $(patsubst $(STACKS_DIR)/%/,%,$(sort $(dir $(wildcard $(STACKS_DIR)/*/))))

# Build ansible-playbook command
ANSIBLE_CMD := ansible-playbook -i $(INVENTORY)

# Add optional flags
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

# Extra vars
EXTRA_VARS := stack_type=$(STACK) environment=$(ENV) deploy_serial=$(SERIAL)
ifdef TARGET
	EXTRA_VARS += target_hosts=$(TARGET)
endif
ifdef DOMAIN
	EXTRA_VARS += my_domain=$(DOMAIN)
endif
ifdef SUBDOMAIN
	EXTRA_VARS += subdomain=$(SUBDOMAIN)
endif

#
# Main Deployment Targets
#

.PHONY: deploy
deploy: validate-stack validate-target ## Deploy a stack (STACK=name ENV=prod TARGET=host)
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@echo "$(GREEN)Deploying Stack$(RESET)"
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@echo "$(BLUE)Stack:$(RESET)       $(STACK)"
	@echo "$(BLUE)Environment:$(RESET) $(ENV)"
	@echo "$(BLUE)Target:$(RESET)      $(TARGET)"
	@echo "$(BLUE)Serial:$(RESET)      $(SERIAL)"
	@[ -n "$(TAGS)" ] && echo "$(BLUE)Tags:$(RESET)        $(TAGS)" || true
	@echo "$(GREEN)═══════════════════════════════════════$(RESET)"
	@$(ANSIBLE_CMD) \
		--extra-vars "$(EXTRA_VARS)" \
		$(PLAYBOOKS_DIR)/deploy-stack.yml

.PHONY: dry-run
dry-run: ## Dry run deployment (STACK=name ENV=prod TARGET=host)
	@$(MAKE) deploy CHECK=true

.PHONY: deploy-all
deploy-all: validate-stack ## Deploy stack to all hosts in target group
	@echo "$(YELLOW)Warning: Deploying to ALL hosts in target group$(RESET)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(MAKE) deploy; \
	else \
		echo "$(RED)Deployment cancelled$(RESET)"; \
	fi

#
# Stack Management Targets
#

.PHONY: status
status: validate-target require-stack-path ## Check stack status (STACK=name TARGET=host)
	@echo "$(BLUE)Checking status of $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose ps 2>/dev/null || docker-compose ps"

.PHONY: logs
logs: validate-target require-stack-path ## View stack logs (STACK=name TARGET=host [SERVICE=svc TAIL=50])
	@echo "$(BLUE)Fetching logs for $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose logs --tail=$(or $(TAIL),50) $(SERVICE) 2>/dev/null || docker-compose logs --tail=$(or $(TAIL),50) $(SERVICE)"

.PHONY: restart
restart: validate-target require-stack-path ## Restart stack (STACK=name TARGET=host [SERVICE=svc])
	@echo "$(YELLOW)Restarting $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose restart $(SERVICE) 2>/dev/null || docker-compose restart $(SERVICE)"

.PHONY: stop
stop: validate-target require-stack-path ## Stop stack (STACK=name TARGET=host)
	@echo "$(YELLOW)Stopping $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose stop 2>/dev/null || docker-compose stop"

.PHONY: start
start: validate-target require-stack-path ## Start stack (STACK=name TARGET=host)
	@echo "$(GREEN)Starting $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose start 2>/dev/null || docker-compose start"

.PHONY: down
down: validate-target require-stack-path ## Stop and remove stack (STACK=name TARGET=host)
	@echo "$(RED)Warning: This will stop and remove all containers for $(STACK)$(RESET)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		ansible $(TARGET) -i $(INVENTORY) -m shell \
			-a "cd $(STACK_PATH) && docker compose down 2>/dev/null || docker-compose down"; \
	else \
		echo "$(RED)Operation cancelled$(RESET)"; \
	fi

.PHONY: pull
pull: validate-target require-stack-path ## Pull latest images (STACK=name TARGET=host)
	@echo "$(BLUE)Pulling images for $(STACK) on $(TARGET)...$(RESET)"
	@ansible $(TARGET) -i $(INVENTORY) -m shell \
		-a "cd $(STACK_PATH) && docker compose pull 2>/dev/null || docker-compose pull"

.PHONY: update
update: pull deploy ## Pull images and redeploy (STACK=name ENV=prod TARGET=host)

#
# Utility Targets
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

.PHONY: show-config
show-config: validate-stack ## Show stack configuration (STACK=name ENV=prod)
	@echo "$(GREEN)Configuration for $(STACK) ($(ENV)):$(RESET)"
	@echo ""
	@echo "$(BLUE)Base config:$(RESET) $(STACKS_DIR)/$(STACK)/base.yml"
	@[ -f "$(STACKS_DIR)/$(STACK)/base.yml" ] && cat $(STACKS_DIR)/$(STACK)/base.yml || echo "  File not found"
	@echo ""
	@echo "$(BLUE)Environment config:$(RESET) $(STACKS_DIR)/$(STACK)/$(ENV).yml"
	@[ -f "$(STACKS_DIR)/$(STACK)/$(ENV).yml" ] && cat $(STACKS_DIR)/$(STACK)/$(ENV).yml || echo "  File not found"

.PHONY: ping
ping: ## Ping hosts (TARGET=host_pattern)
	@ansible $(or $(TARGET),all) -i $(INVENTORY) -m ping

.PHONY: facts
facts: validate-target ## Gather facts from target (TARGET=host)
	@ansible $(TARGET) -i $(INVENTORY) -m setup

.PHONY: check-syntax
check-syntax: ## Check playbook syntax
	@echo "$(BLUE)Checking playbook syntax...$(RESET)"
	@ansible-playbook -i $(INVENTORY) --syntax-check $(PLAYBOOKS_DIR)/deploy-stack.yml
	@echo "$(GREEN)✓ Syntax OK$(RESET)"

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
# Validation Helpers
#

.PHONY: validate-stack
validate-stack:
	@if [ -z "$(STACK)" ]; then \
		echo "$(RED)Error: STACK parameter required$(RESET)"; \
		echo "Usage: make deploy STACK=media ENV=production TARGET=host"; \
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
		echo "Usage: make status STACK=media TARGET=media_host"; \
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
# Help
#

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)╔════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(GREEN)║         Ansible Stack Management (Profile-Based)       ║$(RESET)"
	@echo "$(GREEN)╚════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""
	@echo "$(BLUE)Quick Start:$(RESET)"
	@echo "  make deploy STACK=media ENV=production TARGET=media_host"
	@echo "  make status STACK=media TARGET=media_host"
	@echo "  make logs STACK=media TARGET=media_host SERVICE=sonarr"
	@echo ""
	@echo "$(BLUE)Available Commands:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Parameters:$(RESET)"
	@echo "  STACK      Stack name (required for most commands)"
	@echo "  ENV        Environment: production, staging (default: production)"
	@echo "  TARGET     Target host(s) or group (required for operations)"
	@echo "  TAGS       Ansible tags to run (comma-separated)"
	@echo "  SKIP_TAGS  Ansible tags to skip (comma-separated)"
	@echo "  SERIAL     Deploy to N hosts at a time (default: 1)"
	@echo "  SERVICE    Specific service for logs/restart"
	@echo "  TAIL       Number of log lines (default: 50)"
	@echo "  VERBOSE    Ansible verbosity: v, vv, vvv, or vvvv"
	@echo "  CHECK      Set to 'true' for dry-run mode"
	@echo ""
	@echo "$(BLUE)Examples:$(RESET)"
	@echo "  # Deploy media stack to production"
	@echo "  make deploy STACK=media ENV=production TARGET=media_host"
	@echo ""
	@echo "  # Deploy to staging environment"
	@echo "  make deploy STACK=automation ENV=staging TARGET=test_server"
	@echo ""
	@echo "  # Dry run deployment"
	@echo "  make dry-run STACK=media ENV=production TARGET=media_host"
	@echo ""
	@echo "  # Deploy with specific tags"
	@echo "  make deploy STACK=media TARGET=media_host TAGS=config,network"
	@echo ""
	@echo "  # View service logs"
	@echo "  make logs STACK=media TARGET=media_host SERVICE=sonarr TAIL=100"
	@echo ""
	@echo "  # Restart specific service"
	@echo "  make restart STACK=media TARGET=media_host SERVICE=radarr"
	@echo ""
	@echo "  # Update stack (pull + deploy)"
	@echo "  make update STACK=media ENV=production TARGET=media_host"

.DEFAULT_GOAL := help
