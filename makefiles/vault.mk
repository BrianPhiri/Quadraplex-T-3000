# Ansible Vault Helpers + Git Hook Installer
#
# Every secrets file in this repo is named vault.yml (vars/stacks/*/vault.yml,
# vars/proxy/vault.yml, inventory/group_vars/all/vault.yml) - discovered here
# by that convention rather than a hardcoded list, so a new stack's vault.yml
# is picked up automatically.

VAULT_PASSWORD_FILE ?= .vault_password
VAULT_FILES := $(shell find . -path './.git' -prune -o -name 'vault.yml' -print)

# Color output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

.PHONY: vault-status
vault-status: ## Show encrypted/plaintext status of every vault.yml in the repo
	@for f in $(VAULT_FILES); do \
		first_line=$$(head -n1 "$$f"); \
		case "$$first_line" in \
			'$$ANSIBLE_VAULT'*) echo "$(GREEN)encrypted$(RESET)   $$f" ;; \
			*) echo "$(RED)PLAINTEXT$(RESET)   $$f" ;; \
		esac; \
	done

.PHONY: vault-encrypt
vault-encrypt: ## Encrypt every vault.yml in the repo that isn't already encrypted
	@for f in $(VAULT_FILES); do \
		first_line=$$(head -n1 "$$f"); \
		case "$$first_line" in \
			'$$ANSIBLE_VAULT'*) echo "$(BLUE)Already encrypted:$(RESET) $$f" ;; \
			*) echo "$(GREEN)Encrypting:$(RESET) $$f"; \
			   ansible-vault encrypt --vault-password-file $(VAULT_PASSWORD_FILE) --encrypt-vault-id default "$$f" ;; \
		esac; \
	done

.PHONY: vault-decrypt
vault-decrypt: ## Decrypt every vault.yml in the repo for local editing (DO NOT commit while decrypted)
	@echo "$(YELLOW)Decrypting all vault files for local editing.$(RESET)"
	@echo "$(YELLOW)Run 'make vault-encrypt' before committing - the pre-commit hook (make install-hooks) also catches this.$(RESET)"
	@for f in $(VAULT_FILES); do \
		first_line=$$(head -n1 "$$f"); \
		case "$$first_line" in \
			'$$ANSIBLE_VAULT'*) echo "$(GREEN)Decrypting:$(RESET) $$f"; \
			   ansible-vault decrypt --vault-password-file $(VAULT_PASSWORD_FILE) "$$f" ;; \
			*) echo "$(BLUE)Already decrypted:$(RESET) $$f" ;; \
		esac; \
	done

.PHONY: vault-edit
vault-edit: ## Edit one vault file in $EDITOR, handling decrypt/encrypt automatically (FILE=path/to/vault.yml)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Usage: make vault-edit FILE=vars/stacks/media/vault.yml$(RESET)"; \
		exit 1; \
	fi
	ansible-vault edit --vault-password-file $(VAULT_PASSWORD_FILE) "$(FILE)"

.PHONY: install-hooks
install-hooks: ## Install this repo's git hooks (auto-encrypts vault.yml files before they're committed)
	git config core.hooksDir .githooks
	chmod +x .githooks/*
	@echo "$(GREEN)✓ Git hooks installed$(RESET) (core.hooksDir=.githooks)"
	@echo "  Every clone of this repo needs to run 'make install-hooks' once - it's a local git config, not something git tracks on its own."
