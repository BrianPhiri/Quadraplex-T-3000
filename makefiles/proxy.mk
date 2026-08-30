# Proxy Stack (Traefik) Deployment Makefile
# Usage: make deploy-proxy TARGET=primary DOMAIN=example.com SUBDOMAIN=traefik
#
# Generic stack management (deploy/status/logs/restart/etc. for the media/utility/dns
# stacks) lives in base-stack.mk. This file only carries what's genuinely specific to
# the proxy (Traefik) stack, using a proxy- prefix so its targets never collide with
# base-stack.mk's bare-verb targets. Shared utilities (list-hosts, ping, validate-target,
# help) are intentionally not duplicated here — base-stack.mk's versions are generic
# enough to cover the proxy stack too.

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
# NOTE: namespaced as PROXY_* (rather than the generic ANSIBLE_CMD/EXTRA_VARS names
# base-stack.mk also uses) because both files are included in the same `make` run —
# reusing the same variable names would let whichever file is included last silently
# clobber the other's value for every recipe in both files.
PROXY_ANSIBLE_CMD := ansible-playbook -i $(INVENTORY)

# Add optional flags
ifdef VERBOSE
	PROXY_ANSIBLE_CMD += -$(VERBOSE)
endif
ifeq ($(CHECK),true)
	PROXY_ANSIBLE_CMD += --check --diff
endif

# Build extra vars
PROXY_EXTRA_VARS := target_hosts=$(TARGET) environment=$(ENV)
ifdef DOMAIN
	PROXY_EXTRA_VARS += my_domain=$(DOMAIN)
endif
ifdef SUBDOMAIN
	PROXY_EXTRA_VARS += subdomain=$(SUBDOMAIN)
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
	@$(PROXY_ANSIBLE_CMD) \
		--extra-vars "$(PROXY_EXTRA_VARS)" \
		$(PLAYBOOKS_DIR)/deploy-proxy.yml

.PHONY: proxy-dry-run
proxy-dry-run: ## Dry run proxy deployment (TARGET=host [DOMAIN=] [SUBDOMAIN=])
	@$(MAKE) deploy-proxy CHECK=true

#
# Proxy Management Targets
#

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
proxy-update: proxy-pull deploy-proxy ## Pull images and redeploy proxy (TARGET=host)

.PHONY: proxy-config
proxy-config: ## Show proxy configuration files
	@echo "$(GREEN)Proxy Configuration Files:$(RESET)"
	@echo ""
	@echo "$(BLUE)Base config:$(RESET) $(VARS_DIR)/proxy.yml"
	@[ -f "$(VARS_DIR)/proxy.yml" ] && cat $(VARS_DIR)/proxy.yml || echo "  File not found"
	@echo ""
	@echo "$(BLUE)Environment config:$(RESET) $(VARS_DIR)/environments/$(ENV).yml"
	@[ -f "$(VARS_DIR)/environments/$(ENV).yml" ] && cat $(VARS_DIR)/environments/$(ENV).yml || echo "  File not found (optional)"
