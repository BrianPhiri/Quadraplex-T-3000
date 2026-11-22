# Weekly ClamAV scan: /usr/local/bin/clamav-scan.sh on the host, run from root's crontab (roles/clamav).
.PHONY: deploy-clamav clamav-scan clamav-status clamav-logs

deploy-clamav: ## Install ClamAV, the scan script and its weekly cron job (TARGET=host)
	ansible-playbook playbooks/deploy-clamav.yml $(ANSIBLE_OPTS) --limit $(TARGET)

clamav-scan: ## Run the scan now and wait for it; fails if anything is found (TARGET=host)
	ansible $(TARGET) $(ANSIBLE_OPTS) -b -m shell -a "/usr/local/bin/clamav-scan.sh; rc=\$$?; tail -25 /var/log/clamav/scan.log; exit \$$rc"

clamav-status: ## Show the cron entry, signature age and services (TARGET=host)
	ansible $(TARGET) $(ANSIBLE_OPTS) -b -m shell -a "crontab -l | grep -A1 ClamAV; clamscan --version; systemctl is-active clamav-freshclam clamav-daemon"

clamav-logs: ## Show the recent scan log (TARGET=host)
	ansible $(TARGET) $(ANSIBLE_OPTS) -b -m shell -a "tail -50 /var/log/clamav/scan.log"
