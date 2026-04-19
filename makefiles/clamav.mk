.PHONY: help deploy test check-vars

# Configuration
INVENTORY := inventory/hosts.yml

# Default values
TARGET ?=
HOST ?=
GOTIFY_URL ?=
GOTIFY_TOKEN ?=
SCAN_DIR ?= /

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)ClamAV Deployment Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Usage:$(NC)"
	@echo "  make deploy-clamav TARGET=home                                         # Deploy using inventory"
	@echo "  make deploy-clamav HOST=192.168.1.100                                  # Deploy to IP directly"
	@echo "  make deploy-clamav TARGET=home GOTIFY_URL=https://gotify.example.com GOTIFY_TOKEN=your-token"
	@echo "  make test-clamav TARGET=home                                           # Run a manual test scan"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Examples:$(NC)"
	@echo "  # Deploy using inventory (recommended):"
	@echo "  $(BLUE)make deploy-clamav TARGET=home$(NC)"
	@echo ""
	@echo "  # Deploy to IP address:"
	@echo "  $(BLUE)make deploy-clamav HOST=192.168.1.100$(NC)"
	@echo ""
	@echo "  # Deploy with Gotify notifications:"
	@echo "  $(BLUE)make deploy-clamav TARGET=home GOTIFY_URL=https://gotify.myserver.com GOTIFY_TOKEN=AbCdEf123$(NC)"
	@echo ""
	@echo "  # Custom scan directory:"
	@echo "  $(BLUE)make deploy-clamav TARGET=home SCAN_DIR=/var/www$(NC)"
	@echo ""
	@echo "  # Run manual test scan:"
	@echo "  $(BLUE)make test-clamav TARGET=home$(NC)"

check-vars: ## Check if required variables are set
ifeq ($(TARGET)$(HOST),)
	@echo "$(RED)Error: Either TARGET or HOST is required$(NC)"
	@echo "Usage: make deploy-clamav TARGET=home  (uses inventory)"
	@echo "   or: make deploy-clamav HOST=192.168.1.100  (direct IP/hostname)"
	@exit 1
endif

deploy-clamav: check-vars ## Deploy ClamAV to specified host(s)
ifdef TARGET
	@echo "$(GREEN)Deploying ClamAV to: $(TARGET) (using inventory)$(NC)"
	@if [ -n "$(GOTIFY_URL)" ] && [ -n "$(GOTIFY_TOKEN)" ]; then \
		echo "$(GREEN)Gotify notifications: ENABLED$(NC)"; \
		echo "$(BLUE)Gotify URL: $(GOTIFY_URL)$(NC)"; \
		ansible-playbook -i $(INVENTORY) playbooks/deploy-clamav.yml \
			-l $(TARGET) \
			-e "gotify_url=$(GOTIFY_URL)" \
			-e "gotify_token=$(GOTIFY_TOKEN)" \
			-e "scan_directory=$(SCAN_DIR)"; \
	else \
		echo "$(YELLOW)Gotify notifications: DISABLED$(NC)"; \
		ansible-playbook -i $(INVENTORY) playbooks/deploy-clamav.yml \
			-l $(TARGET) \
			-e "scan_directory=$(SCAN_DIR)"; \
	fi
else
	@echo "$(GREEN)Deploying ClamAV to: $(HOST)$(NC)"
	@if [ -n "$(GOTIFY_URL)" ] && [ -n "$(GOTIFY_TOKEN)" ]; then \
		echo "$(GREEN)Gotify notifications: ENABLED$(NC)"; \
		echo "$(BLUE)Gotify URL: $(GOTIFY_URL)$(NC)"; \
		ansible-playbook -i "$(HOST)," playbooks/deploy-clamav.yml \
			-e "gotify_url=$(GOTIFY_URL)" \
			-e "gotify_token=$(GOTIFY_TOKEN)" \
			-e "scan_directory=$(SCAN_DIR)"; \
	else \
		echo "$(YELLOW)Gotify notifications: DISABLED$(NC)"; \
		ansible-playbook -i "$(HOST)," playbooks/deploy-clamav.yml \
			-e "scan_directory=$(SCAN_DIR)"; \
	fi
endif
	@echo "$(GREEN)Deployment complete!$(NC)"

test-clamav: check-vars ## Run a manual test scan on the host
ifdef TARGET
	@echo "$(GREEN)Running manual ClamAV test scan on: $(TARGET) (using inventory)$(NC)"
	@ansible -i $(INVENTORY) $(TARGET) -m shell -a "/usr/local/bin/clamav-scan.sh" -b
else
	@echo "$(GREEN)Running manual ClamAV test scan on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "/usr/local/bin/clamav-scan.sh" -b
endif
	@echo "$(GREEN)Test scan initiated. Check Gotify or /var/log/clamav/scan.log for results$(NC)"

check-clamav-status: check-vars ## Check ClamAV service status
ifdef TARGET
	@echo "$(GREEN)Checking ClamAV status on: $(TARGET) (using inventory)$(NC)"
	@ansible -i $(INVENTORY) $(TARGET) -m shell -a "systemctl status clamav-freshclam" -b
	@ansible -i $(INVENTORY) $(TARGET) -m shell -a "crontab -l | grep clamav" -b
else
	@echo "$(GREEN)Checking ClamAV status on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "systemctl status clamav-freshclam" -b
	@ansible -i "$(HOST)," all -m shell -a "crontab -l | grep clamav" -b
endif

view-logs: check-vars ## View recent ClamAV logs
ifdef TARGET
	@echo "$(GREEN)Viewing ClamAV logs on: $(TARGET) (using inventory)$(NC)"
	@ansible -i $(INVENTORY) $(TARGET) -m shell -a "tail -50 /var/log/clamav/scan.log" -b
else
	@echo "$(GREEN)Viewing ClamAV logs on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "tail -50 /var/log/clamav/scan.log" -b
endif

update-signatures: check-vars ## Manually update virus signatures
ifdef TARGET
	@echo "$(GREEN)Updating ClamAV virus signatures on: $(TARGET) (using inventory)$(NC)"
	@ansible -i $(INVENTORY) $(TARGET) -m shell -a "freshclam" -b
else
	@echo "$(GREEN)Updating ClamAV virus signatures on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "freshclam" -b
endif

ping: check-vars ## Test connectivity to host
ifdef TARGET
	@echo "$(GREEN)Testing connection to: $(TARGET) (using inventory)$(NC)"
	@ansible -i $(INVENTORY) $(TARGET) -m ping
else
	@echo "$(GREEN)Testing connection to: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m ping
endif

clean-logs: check-vars ## Clean old ClamAV logs
ifdef TARGET
	@echo "$(YELLOW)Cleaning ClamAV logs on: $(TARGET) (using inventory)$(NC)"
	@ansible -i $(INVENTORY) $(TARGET) -m shell -a "rm -f /var/log/clamav/scan.log.*" -b
else
	@echo "$(YELLOW)Cleaning ClamAV logs on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "rm -f /var/log/clamav/scan.log.*" -b
endif
	@echo "$(GREEN)Old logs cleaned$(NC)"
