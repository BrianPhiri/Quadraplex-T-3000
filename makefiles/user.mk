create-users:
	@echo "Creating host users on $(ENV) environment..."
	ansible-playbook $(ANSIBLE_OPTS) \
		-l $(ENV) \
		-e target_hosts=$(HOST) \
		playbooks/create-users.yml


