# Backup and restore. The backup itself is /usr/local/bin/quadraplex-backup on the host,
# run daily at 02:00 by backup-daily.timer; these targets install it, run it, or restore.
.PHONY: backup-setup backup backup-s3 backup-status backup-logs restore restore-dry-run restore-list s3-test

STACK ?=
SERVICE ?=
DATE ?=
FROM_S3 ?= false
BACKUP_DIR ?= /mnt/media/backups
BACKUP_PLAYBOOK := playbooks/backup.yml
RESTORE_PLAYBOOK := playbooks/restore.yml

backup-setup: ## Install backup script, rclone config and daily timer (TARGET=host)
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) --limit $(TARGET) -e action=setup

backup: ## Run a full backup now, incl. S3 copy (TARGET=host)
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) --limit $(TARGET) -e action=daily

backup-s3: ## Copy existing backups to S3 now (TARGET=host)
	ansible-playbook $(BACKUP_PLAYBOOK) $(ANSIBLE_OPTS) --limit $(TARGET) -e action=s3

backup-status: ## Show backup timer, sizes and newest archives (TARGET=host)
	ansible $(TARGET) $(ANSIBLE_OPTS) -b -m shell -a "systemctl list-timers backup-daily.timer --no-pager; du -sh $(BACKUP_DIR)/*/; ls -lt $(BACKUP_DIR)/*/ | head -20"

backup-logs: ## Show recent backup logs (TARGET=host)
	ansible $(TARGET) $(ANSIBLE_OPTS) -b -m shell -a "journalctl -u backup-daily -n 50 --no-pager"

restore: ## Restore a stack, or one service (STACK=media [SERVICE=sonarr] [DATE=20261011] [FROM_S3=true] TARGET=host)
	@[ -n "$(STACK)" ] || { echo "Usage: make restore STACK=media [SERVICE=sonarr] [DATE=20261011] TARGET=host"; exit 1; }
	ansible-playbook $(RESTORE_PLAYBOOK) $(ANSIBLE_OPTS) --limit $(TARGET) \
		-e "restore_stack=$(STACK) restore_from_s3=$(FROM_S3) $(if $(SERVICE),restore_service=$(SERVICE)) $(if $(DATE),restore_date=$(DATE)) restore_dry_run=$(or $(DRY_RUN),false)"

restore-dry-run: ## Preview a restore without changing anything (same args as restore)
	@$(MAKE) restore DRY_RUN=true

restore-list: ## List backup archives (TARGET=host [STACK=media])
	ansible $(TARGET) $(ANSIBLE_OPTS) -b -m shell -a "ls -lh $(BACKUP_DIR)/$(STACK)*"

s3-test: ## Test the S3 connection (TARGET=host)
	ansible $(TARGET) $(ANSIBLE_OPTS) -b -m shell -a "docker run --rm -v /root/.config/rclone:/config/rclone rclone/rclone:1.75.2 lsd s3backup: 2>&1"
