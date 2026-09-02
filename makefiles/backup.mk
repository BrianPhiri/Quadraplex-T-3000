# Makefile for backup and restore operations
.PHONY: backup backup-setup backup-postgres backup-daily backup-s3 backup-status backup-verify
.PHONY: restore restore-list restore-dry-run backup-logs backup-timers

# Backup variables
STACK ?= all
SERVICE ?=
DATE ?=
DRY_RUN ?= false
FROM_S3 ?= false

# Ansible backup playbook
BACKUP_PLAYBOOK := playbooks/backup.yml
RESTORE_PLAYBOOK := playbooks/restore.yml

#
# Backup Commands
#

backup-setup: ## Setup backup infrastructure (pull rclone image, create directories, deploy systemd timers)
	@echo "Setting up backup infrastructure on $(TARGET)..."
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "backup_action=setup"

backup-postgres: ## Backup PostgreSQL databases (hourly critical backups)
	@echo "Backing up PostgreSQL databases on $(TARGET)..."
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "backup_action=postgres $(if $(filter-out all,$(STACK)),backup_stack=$(STACK),)"

backup-sqlite: ## Backup SQLite databases
	@echo "Backing up SQLite databases on $(TARGET)..."
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "backup_action=sqlite $(if $(filter-out all,$(STACK)),backup_stack=$(STACK),)"

backup-config: ## Backup configuration directories
	@echo "Backing up configurations on $(TARGET)..."
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "backup_action=config $(if $(filter-out all,$(STACK)),backup_stack=$(STACK),)"

backup-data: ## Backup data directories (Prometheus TSDB, etc.)
	@echo "Backing up data directories on $(TARGET)..."
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "backup_action=data $(if $(filter-out all,$(STACK)),backup_stack=$(STACK),)"

backup-daily: ## Run full daily backup (SQLite, configs, data) + retention cleanup
	@echo "Running full daily backup on $(TARGET)..."
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "backup_action=daily $(if $(filter-out all,$(STACK)),backup_stack=$(STACK),)"

backup-s3: ## Sync backups to S3 storage
	@echo "Syncing backups to S3 from $(TARGET)..."
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "backup_action=s3"

backup: ## Run complete backup (databases, configs, data)
	@echo "Running full backup on $(TARGET)..."
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "backup_action=all $(if $(filter-out all,$(STACK)),backup_stack=$(STACK),)"

backup-retention: ## Clean up old backups (apply retention policy)
	@echo "Cleaning up old backups on $(TARGET)..."
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "backup_action=retention"

#
# Restore Commands
#

restore: ## Restore a service from backup (requires SERVICE, STACK, DATE or use LATEST=true)
	@if [ -z "$(SERVICE)" ] || [ -z "$(STACK)" ]; then \
		echo "Error: SERVICE and STACK are required"; \
		echo "Usage: make restore SERVICE=grafana STACK=utility DATE=20260425T120000"; \
		echo "   or: make restore SERVICE=grafana STACK=utility LATEST=true"; \
		echo "   or: make restore SERVICE=immich STACK=media DATE=20260425 FROM_S3=true"; \
		exit 1; \
	fi
	@echo "Restoring $(SERVICE) from $(STACK) stack on $(TARGET)..."
	ansible-playbook $(RESTORE_PLAYBOOK) $(ANSIBLE_OPTS) \
		--limit $(TARGET) \
		--extra-vars "restore_service=$(SERVICE) restore_stack=$(STACK) $(if $(DATE),restore_date=$(DATE),restore_latest=true) restore_from_s3=$(FROM_S3) restore_dry_run=$(DRY_RUN)"

restore-dry-run: ## Dry-run restore to preview changes (requires SERVICE, STACK, DATE)
	@$(MAKE) restore DRY_RUN=true

restore-remote: ## Restore from S3 backup (requires SERVICE, STACK, DATE)
	@$(MAKE) restore FROM_S3=true

restore-list: ## List available backups for a stack
	@if [ -z "$(STACK)" ]; then \
		echo "Error: STACK is required"; \
		echo "Usage: make restore-list STACK=utility TARGET=host"; \
		exit 1; \
	fi
	@echo "Listing backups for $(STACK) stack on $(TARGET)..."
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "find /backup/$(STACK) -type f -name '*' -exec ls -lh {} \; | tail -50"

#
# Monitoring and Status Commands
#

backup-status: ## Show backup status and recent backups
	@echo "Backup status for $(TARGET):"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "du -sh /backup/* 2>/dev/null || echo 'No backups found'"
	@echo ""
	@echo "Recent backups:"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "find /backup -type f -name '*' -mtime -7 -exec ls -lh {} \; | tail -20"

backup-timers: ## Show systemd timer status
	@echo "Backup timer status for $(TARGET):"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "systemctl list-timers 'backup-*' --all"

backup-logs: ## Show backup logs from systemd journal
	@echo "Recent backup logs for $(TARGET):"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "journalctl -u 'backup-*' -n 50 --no-pager"

backup-logs-postgres: ## Show PostgreSQL backup logs
	@echo "PostgreSQL backup logs for $(TARGET):"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "journalctl -u backup-postgres-hourly.service -n 50 --no-pager"

backup-logs-daily: ## Show daily backup logs
	@echo "Daily backup logs for $(TARGET):"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "journalctl -u backup-daily.service -n 50 --no-pager"

backup-logs-s3: ## Show S3 sync logs
	@echo "S3 sync logs for $(TARGET):"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "journalctl -u backup-s3-sync.service -n 50 --no-pager"

backup-verify: ## Verify backup integrity
	@echo "Verifying backup integrity on $(TARGET)..."
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "cd /backup && find . -name '*.dump' -exec sh -c 'echo \"Checking: \$$1\" && pg_restore --list \$$1 > /dev/null 2>&1 && echo \"OK\" || echo \"FAILED\"' _ {} \;"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "cd /backup && find . -name '*.db.gz' -exec sh -c 'echo \"Checking: \$$1\" && gunzip -t \$$1 && echo \"OK\" || echo \"FAILED\"' _ {} \;"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "cd /backup && find . -name '*.tar.gz' -exec sh -c 'echo \"Checking: \$$1\" && tar -tzf \$$1 > /dev/null && echo \"OK\" || echo \"FAILED\"' _ {} \;"

#
# S3 Management Commands
#

# rclone runs via the official Docker image on the target host, not a host-installed
# binary - matches roles/backup/defaults/main.yml's backup_rclone_bin.
RCLONE_DOCKER := docker run --rm -v /root/.config/rclone:/config/rclone -v /backup:/backup rclone/rclone:latest

s3-test: ## Test S3 connection
	@echo "Testing S3 connection from $(TARGET)..."
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "$(RCLONE_DOCKER) lsd s3backup: 2>&1"

s3-list: ## List S3 backup contents
	@echo "Listing S3 backups for $(TARGET):"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "$(RCLONE_DOCKER) ls s3backup:$(shell ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a 'hostname' --one-line | awk '{print \$$NF}') 2>&1 | tail -50"

s3-size: ## Show S3 backup size
	@echo "S3 backup size for $(TARGET):"
	ansible $(TARGET) $(ANSIBLE_OPTS) -m shell -a "$(RCLONE_DOCKER) size s3backup: 2>&1"

#
# Help
#

backup-help: ## Show detailed backup help
	@echo ""
	@echo "=== Backup & Restore Commands ==="
	@echo ""
	@echo "Setup & Configuration:"
	@echo "  make backup-setup TARGET=host          Setup backup infrastructure"
	@echo ""
	@echo "Backup Operations:"
	@echo "  make backup TARGET=host                 Full backup (all stacks)"
	@echo "  make backup TARGET=host STACK=media     Backup specific stack"
	@echo "  make backup-postgres TARGET=host        PostgreSQL only (hourly)"
	@echo "  make backup-daily TARGET=host           Daily backup (SQLite+configs+data)"
	@echo "  make backup-s3 TARGET=host              Sync to S3"
	@echo ""
	@echo "Restore Operations:"
	@echo "  make restore SERVICE=grafana STACK=utility DATE=20260425T120000 TARGET=host"
	@echo "  make restore SERVICE=grafana STACK=utility LATEST=true TARGET=host"
	@echo "  make restore-dry-run SERVICE=grafana STACK=utility DATE=20260425 TARGET=host"
	@echo "  make restore-remote SERVICE=immich STACK=media DATE=20260425 TARGET=host"
	@echo ""
	@echo "Monitoring:"
	@echo "  make backup-status TARGET=host          Show backup summary"
	@echo "  make backup-timers TARGET=host          Show systemd timers"
	@echo "  make backup-logs TARGET=host            Recent backup logs"
	@echo "  make backup-verify TARGET=host          Verify backup integrity"
	@echo "  make restore-list STACK=utility TARGET=host"
	@echo ""
	@echo "S3 Management:"
	@echo "  make s3-test TARGET=host                Test S3 connection"
	@echo "  make s3-list TARGET=host                List S3 backups"
	@echo "  make s3-size TARGET=host                Show S3 usage"
	@echo ""
	@echo "Environment Variables:"
	@echo "  TARGET  - Target host (required)"
	@echo "  STACK   - Stack name (proxy, dns, media, utility, all)"
	@echo "  SERVICE - Service name (for restore)"
	@echo "  DATE    - Backup timestamp (for restore)"
	@echo "  DRY_RUN - Preview restore (true/false)"
	@echo "  FROM_S3 - Restore from S3 (true/false)"
	@echo ""
	@echo "Examples:"
	@echo "  make backup TARGET=prod-01"
	@echo "  make backup-postgres TARGET=prod-01 STACK=utility"
	@echo "  make restore SERVICE=grafana STACK=utility LATEST=true TARGET=prod-01"
	@echo "  make restore-dry-run SERVICE=immich STACK=media DATE=20260425 TARGET=prod-01"
	@echo ""
