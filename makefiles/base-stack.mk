# Stack definitions (stack_name:path:playbook)
STACKS := \
	core:/opt/core-stack:deploy-core.yml \
	media:/opt/media-stack:deploy-media.yml \

define make-deploy-target
deploy-$(1): ## Deploy $(1) stack
	@echo "Deploying $(1) stack to $$(ENV)..."
	ansible-playbook $$(ANSIBLE_OPTS) -l $$(ENV) playbooks/$(3)
endef

define make-mgmt-targets
$(1)-status: ## Check $(1) stack status
	ansible $$(ENV) $$(ANSIBLE_OPTS) -a "docker-compose -f $(2)/docker-compose.yml ps"
$(1)-logs: ## View $(1) stack logs (use TAIL=N to change lines)
	ansible $$(ENV) $$(ANSIBLE_OPTS) -a "docker-compose -f $(2)/docker-compose.yml logs --tail=$${TAIL:-50}"
$(1)-restart: ## Restart $(1) stack
	ansible $$(ENV) $$(ANSIBLE_OPTS) -a "docker-compose -f $(2)/docker-compose.yml restart"
$(1)-stop: ## Stop $(1) stack
	ansible $$(ENV) $$(ANSIBLE_OPTS) -a "docker-compose -f $(2)/docker-compose.yml stop"
$(1)-start: ## Start $(1) stack
	ansible $$(ENV) $$(ANSIBLE_OPTS) -a "docker-compose -f $(2)/docker-compose.yml start"
$(1)-pull: ## Pull latest images for $(1) stack
	ansible $$(ENV) $$(ANSIBLE_OPTS) -a "docker-compose -f $(2)/docker-compose.yml pull"
endef

# Generate all targets
$(foreach stack,$(STACKS),\
	$(eval STACK_NAME := $(word 1,$(subst :, ,$(stack)))) \
	$(eval STACK_PATH := $(word 2,$(subst :, ,$(stack)))) \
	$(eval STACK_PLAYBOOK := $(word 3,$(subst :, ,$(stack)))) \
	$(eval $(call make-deploy-target,$(STACK_NAME),$(STACK_PATH),$(STACK_PLAYBOOK))) \
	$(eval $(call make-mgmt-targets,$(STACK_NAME),$(STACK_PATH))) \
)
help: ## Show this help message
	@echo "Available stacks: $(foreach s,$(STACKS),$(word 1,$(subst :, ,$(s))) )"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
.PHONY: help $(foreach s,$(STACKS),deploy-$(word 1,$(subst :, ,$(s))) $(word 1,$(subst :, ,$(s)))-status $(word 1,$(subst :, ,$(s)))-logs $(word 1,$(subst :, ,$(s)))-restart $(word 1,$(subst :, ,$(s)))-stop $(word 1,$(subst :, ,$(s)))-start)
