# proxy Stack Deployment
deploy-proxy: ## Deploy proxy stack (Traefik)
	@echo "Deploying proxy stack to $(ENV)..."
	ansible-playbook $(ANSIBLE_OPTS) \
		-l $(ENV) \
		playbooks/deploy-proxy.yml

#proxy stack 
proxy-status: ## Check proxy stack status
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/proxy-stack/docker-compose.yml ps"

proxy-logs: ## View utilities stack logs
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/proxy-stack/docker-compose.yml logs --tail=50"

proxy-restart: ## Restart utilities stack
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/proxy-stack/docker-compose.yml restart"

proxy-stop: ## Stop utilities stack
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/proxy-stack/docker-compose.yml stop"

proxy-start: ## Start utilities stack
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/proxy-stack/docker-compose.yml start"

