# Weekly homelab check + cleanup: /usr/local/bin/quadraplex-maintenance, run Sundays 08:00 by maintenance.timer.
.PHONY: maintenance-setup maintenance maintenance-check maintenance-report

maintenance-setup: ## Install the weekly maintenance check and timer (TARGET=host)
	ansible-playbook playbooks/maintenance.yml $(ANSIBLE_OPTS) --limit $(TARGET)

maintenance: ## Run the maintenance check + cleanup now (TARGET=host)
	ansible-playbook playbooks/maintenance.yml $(ANSIBLE_OPTS) --limit $(TARGET) -e maintenance_run_now=true

maintenance-check: ## Run the checks only, no cleanup (TARGET=host)
	ansible-playbook playbooks/maintenance.yml $(ANSIBLE_OPTS) --limit $(TARGET) -e maintenance_run_now=true -e maintenance_no_cleanup=true

maintenance-report: ## Show the latest maintenance report (TARGET=host)
	ansible $(TARGET) $(ANSIBLE_OPTS) -b -m shell -a "ls -t /var/log/quadraplex-maintenance/*.log | head -1 | xargs cat; systemctl list-timers maintenance.timer --no-pager"
