include makefiles/docker.mk
include makefiles/media.mk
include makefiles/user.mk
include makefiles/utility.mk 

# Makefile - Docker Installation Commands
.PHONY: help install-docker docker-info docker-test docker-cleanup

# Default environment
ENV ?= development
HOST ?= all

# Ansible options
ANSIBLE_OPTS ?= -i inventory/hosts.yml

help: ## Show this help message
	@echo 'Docker Installation Commands:'
	@echo ''
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Examples:'
	@echo '  make install-docker ENV=production'
	@echo '  make install-docker HOST=media-prod-01'
	@echo '  make docker-test ENV=staging'

test-connection: ## Test connection to host
	@echo "Testing ansible connection to host: $(HOST)"
	ansible $(ENV) $(ANSIBLE_OPTS) -m ping
	
# Full Stack Deployment
deploy-all: ## Deploy all stacks
	@echo "Deploying complete stack to $(ENV)..."
	$(MAKE) create-users ENV=$(ENV)
	$(MAKE) install-docker ENV=$(ENV)
	$(MAKE) deploy-media ENV=$(ENV)
	
