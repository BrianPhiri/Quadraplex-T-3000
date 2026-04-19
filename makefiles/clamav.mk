.PHONY: help deploy test check-vars

# Default values
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
	@echo "  make deploy HOST=server.example.com                                    # Deploy without notifications"
	@echo "  make deploy HOST=server.example.com GOTIFY_URL=https://gotify.example.com GOTIFY_TOKEN=your-token"
	@echo "  make test HOST=server.example.com                                      # Run a manual test scan"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Examples:$(NC)"
	@echo "  # Deploy to single host without notifications:"
	@echo "  $(BLUE)make deploy HOST=192.168.1.100$(NC)"
	@echo ""
	@echo "  # Deploy with Gotify notifications:"
	@echo "  $(BLUE)make deploy HOST=prod-server GOTIFY_URL=https://gotify.myserver.com GOTIFY_TOKEN=AbCdEf123$(NC)"
	@echo ""
	@echo "  # Deploy to multiple hosts (comma-separated):"
	@echo "  $(BLUE)make deploy HOST=server1,server2,server3$(NC)"
	@echo ""
	@echo "  # Custom scan directory:"
	@echo "  $(BLUE)make deploy HOST=webserver SCAN_DIR=/var/www$(NC)"
	@echo ""
	@echo "  # Run manual test scan:"
	@echo "  $(BLUE)make test HOST=server1$(NC)"

check-vars: ## Check if required variables are set
ifndef HOST
	@echo "$(RED)Error: HOST is required$(NC)"
	@echo "Usage: make deploy HOST=your-server.com"
	@exit 1
endif

deploy-clamav: check-vars ## Deploy ClamAV to specified host(s)
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
	@echo "$(GREEN)Deployment complete!$(NC)"

deploy-with-inventory: check-vars ## Deploy using an inventory file
	@echo "$(GREEN)Deploying ClamAV using inventory file$(NC)"
	@if [ -n "$(GOTIFY_URL)" ] && [ -n "$(GOTIFY_TOKEN)" ]; then \
		echo "$(GREEN)Gotify notifications: ENABLED$(NC)"; \
		ansible-playbook -i inventory playbooks/deploy-clamav.yml \
			-e "gotify_url=$(GOTIFY_URL)" \
			-e "gotify_token=$(GOTIFY_TOKEN)" \
			-e "scan_directory=$(SCAN_DIR)"; \
	else \
		echo "$(YELLOW)Gotify notifications: DISABLED$(NC)"; \
		ansible-playbook -i inventory playbooks/deploy-clamav.yml \
			-e "scan_directory=$(SCAN_DIR)"; \
	fi

test-clamav: check-vars ## Run a manual test scan on the host
	@echo "$(GREEN)Running manual ClamAV test scan on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "/usr/local/bin/clamav-scan.sh" -b
	@echo "$(GREEN)Test scan initiated. Check Gotify or /var/log/clamav/scan.log for results$(NC)"

check-clamav-status: check-vars ## Check ClamAV service status
	@echo "$(GREEN)Checking ClamAV status on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "systemctl status clamav-freshclam" -b
	@ansible -i "$(HOST)," all -m shell -a "crontab -l | grep clamav" -b

view-logs: check-vars ## View recent ClamAV logs
	@echo "$(GREEN)Viewing ClamAV logs on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "tail -50 /var/log/clamav/scan.log" -b

update-signatures: check-vars ## Manually update virus signatures
	@echo "$(GREEN)Updating ClamAV virus signatures on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "freshclam" -b

ping: check-vars ## Test connectivity to host
	@echo "$(GREEN)Testing connection to: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m ping

clean-logs: check-vars ## Clean old ClamAV logs
	@echo "$(YELLOW)Cleaning ClamAV logs on: $(HOST)$(NC)"
	@ansible -i "$(HOST)," all -m shell -a "rm -f /var/log/clamav/scan.log.*" -b
	@echo "$(GREEN)Old logs cleaned$(NC)"
