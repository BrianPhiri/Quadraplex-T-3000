install-docker: ## Install Docker on target hosts
	@echo "Installing Docker on $(ENV) environment..."
	ansible-playbook $(ANSIBLE_OPTS) \
		-l $(ENV) \
		-e target_hosts=$(ENV) \
		playbooks/install-docker-only.yml

install-docker-host: ## Install Docker on specific host
	@echo "Installing Docker on host: $(HOST)"
	ansible-playbook $(ANSIBLE_OPTS) \
		-l $(HOST) \
		-e target_hosts=$(HOST) \
		playbooks/install-docker.yml

install-docker-parallel: ## Install Docker on multiple hosts in parallel
	@echo "Installing Docker on $(ENV) in parallel..."
	ansible-playbook $(ANSIBLE_OPTS) \ 
		-l $(ENV) \
		-e target_hosts=$(ENV) \
		-e install_serial=0 \
		playbooks/install-docker.yml

docker-info: ## Show Docker system information
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker system info"

docker-version: ## Show Docker version on all hosts
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker --version && docker-compose --version"

docker-test: ## Test Docker installation
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker run --rm hello-world"

docker-status: ## Check Docker service status
	ansible $(ENV) $(ANSIBLE_OPTS) -a "systemctl status docker"

docker-logs: ## View Docker service logs
	ansible $(ENV) $(ANSIBLE_OPTS) -a "journalctl -u docker --no-pager -n 50"

docker-restart: ## Restart Docker service
	ansible $(ENV) $(ANSIBLE_OPTS) -a "systemctl restart docker" --become

docker-cleanup: ## Clean up Docker system
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker system prune -f"

docker-disk-usage: ## Show Docker disk usage
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker system df"

# Validation commands
docker-validate: ## Validate Docker installation
	@echo "Validating Docker installation on $(ENV)..."
	ansible-playbook $(ANSIBLE_OPTS) \
		-l $(ENV) \
		--tags validate,test \
		playbooks/install-docker.yml

# Advanced commands
docker-daemon-reload: ## Reload Docker daemon configuration
	ansible $(ENV) $(ANSIBLE_OPTS) --become -a "systemctl daemon-reload && systemctl restart docker"

docker-users-check: ## Check which users are in docker group
	ansible $(ENV) $(ANSIBLE_OPTS) -a "getent group docker"

# Troubleshooting
docker-debug: ## Run Docker installation in debug mode
	ansible-playbook $(ANSIBLE_OPTS) \
		-l $(ENV) \
		-e target_hosts=$(ENV) \
		-vvv \
		playbooks/install-docker.yml

# Rollback (removes Docker)
docker-remove: ## Remove Docker installation (DESTRUCTIVE)
	@echo "WARNING: This will remove Docker and all containers!"
	@read -p "Are you sure? [y/N]: " confirm && [ "$$confirm" = "y" ]
	ansible $(ENV) $(ANSIBLE_OPTS) --become -a "apt-get remove -y docker-ce docker-ce-cli containerd.io"
	ansible $(ENV) $(ANSIBLE_OPTS) --become -a "rm -rf /var/lib/docker /etc/docker"

