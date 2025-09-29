# Media Stack Deployment
deploy-media: ## Deploy media stack (Jellyfin, *arr, etc.)
	@echo "Deploying media stack to $(ENV)..."
	ansible-playbook $(ANSIBLE_OPTS) \
		-l $(ENV) \
		playbooks/deploy-media.yml

#Media stack 
media-status: ## Check media stack status
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/media-stack/docker-compose.yml ps"

media-logs: ## View utilities stack logs
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/media-stack/docker-compose.yml logs --tail=50"

media-restart: ## Restart utilities stack
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/media-stack/docker-compose.yml restart"

media-stop: ## Stop utilities stack
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/media-stack/docker-compose.yml stop"

media-start: ## Start utilities stack
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/media-stack/docker-compose.yml start"

