# Utility Stack Deployment
deploy-utility: ## Deploy utility stack (Portainer)
	@echo "Deploying utility stack to $(ENV)..."
	ansible-playbook $(ANSIBLE_OPTS) \
		-l $(ENV) \
		playbooks/deploy-utility.yml

#Utility stack 
utility-status: ## Check utilities stack status
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/utility-stack/docker-compose.yml ps"

utility-logs: ## View utilities stack logs
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/utility-stack/docker-compose.yml logs --tail=50"

utility-restart: ## Restart utilities stack
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/utility-stack/docker-compose.yml restart"

utility-stop: ## Stop utilities stack
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/utility-stack/docker-compose.yml stop"

utility-start: ## Start utilities stack
	ansible $(ENV) $(ANSIBLE_OPTS) -a "docker-compose -f /opt/utility-stack/docker-compose.yml start"

