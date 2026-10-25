# Host hardening: key-only SSH, docker group cleanup, automatic updates, SMART monitoring.
.PHONY: hardening hardening-check

hardening: ## Apply host hardening (TARGET=host)
	ansible-playbook playbooks/hardening.yml $(ANSIBLE_OPTS) --limit $(TARGET)

hardening-check: ## Dry-run host hardening, show diffs (TARGET=host)
	ansible-playbook playbooks/hardening.yml $(ANSIBLE_OPTS) --limit $(TARGET) --check --diff
