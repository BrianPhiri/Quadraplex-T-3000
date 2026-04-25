# Backup Quick Start Guide

Get your backup system running in 5 minutes.

## Prerequisites

- Ansible deployed Quadraplex-T-3000 infrastructure
- S3-compatible storage account (Backblaze B2, Wasabi, AWS S3, etc.)
- Root/sudo access to target hosts

## Step 1: Configure S3 Credentials (2 minutes)

```bash
# Edit encrypted vault
ansible-vault edit inventory/group_vars/vault.yml

# Add these three lines:
vault_backup_s3_access_key: "YOUR_ACCESS_KEY"
vault_backup_s3_secret_key: "YOUR_SECRET_KEY"
vault_backup_s3_endpoint: "https://s3.wasabisys.com"  # Your S3 endpoint

# Save and exit (:wq in vim)
```

**Where to get S3 credentials:**
- **Backblaze B2**: https://www.backblaze.com/b2/cloud-storage.html (10GB free)
- **Wasabi**: https://wasabi.com/ (First 1TB free trial)
- **AWS S3**: https://aws.amazon.com/s3/

## Step 2: Deploy Backup Infrastructure (1 minute)

```bash
# Install rclone, create directories, setup timers
make backup-setup TARGET=your-host-name

# Example:
make backup-setup TARGET=prod-01
```

## Step 3: Test S3 Connection (30 seconds)

```bash
# Verify S3 credentials work
make s3-test TARGET=your-host-name

# Expected: Success message or bucket list
```

## Step 4: Run Initial Backup (1 minute)

```bash
# Run first backup (all databases, configs, data)
make backup TARGET=your-host-name

# Wait for completion, then sync to S3
make backup-s3 TARGET=your-host-name
```

## Step 5: Verify Everything Works (30 seconds)

```bash
# Check local backups
make backup-status TARGET=your-host-name

# Check S3 backups
make s3-list TARGET=your-host-name

# Check automated timers
make backup-timers TARGET=your-host-name
```

**Expected output:**
- Local backups in `/backup/` (1-5GB)
- S3 bucket contains synced backups
- 3 systemd timers active (postgres-hourly, daily, s3-sync)

## ✅ Done!

Your backup system is now running automatically:
- **Every hour**: PostgreSQL databases
- **Daily at 2 AM**: SQLite, configs, Prometheus data
- **Every 6 hours**: Sync to S3
- **Automatic cleanup**: Old backups removed after 14 days (local) / 90 days (S3)

## What's Next?

### Test a Restore (Recommended)

```bash
# Dry-run restore (no changes made)
make restore-dry-run SERVICE=grafana STACK=utility LATEST=true TARGET=your-host

# If looks good, restore for real
make restore SERVICE=grafana STACK=utility LATEST=true TARGET=your-host
```

### Monitor Backups

```bash
# View recent backups
make backup-status TARGET=your-host

# View logs
make backup-logs TARGET=your-host

# Verify integrity
make backup-verify TARGET=your-host
```

### Optional: Enable Gotify Notifications

```bash
# Edit vault
ansible-vault edit inventory/group_vars/vault.yml

# Add:
vault_backup_gotify_token: "YOUR_GOTIFY_TOKEN"

# Edit all.yml
nano inventory/group_vars/all.yml

# Change:
backup_gotify_enabled: true
backup_gotify_url: "http://gotify.example.com"

# Redeploy
make backup-setup TARGET=your-host
```

## Troubleshooting

**S3 connection fails:**
```bash
# Check credentials
ssh your-host cat /root/.config/rclone/rclone.conf

# Test manually
ssh your-host rclone lsd s3backup:
```

**Backups not running:**
```bash
# Check timers
make backup-timers TARGET=your-host

# Check logs
make backup-logs TARGET=your-host

# Run manual backup with verbose output
ssh your-host
ansible-playbook /root/ansible/playbooks/backup.yml --extra-vars "backup_action=all" -vv
```

**Need help:**
- See full documentation: `docs/BACKUP.md`
- Run: `make backup-help`

## Common Commands

```bash
# Backup
make backup TARGET=host                           # Full backup
make backup TARGET=host STACK=media               # Specific stack

# Restore
make restore SERVICE=grafana STACK=utility LATEST=true TARGET=host
make restore-dry-run SERVICE=grafana STACK=utility DATE=20260425 TARGET=host

# Monitor
make backup-status TARGET=host                    # Summary
make backup-logs TARGET=host                      # Recent logs
make s3-list TARGET=host                          # S3 contents

# List backups
make restore-list STACK=utility TARGET=host       # List available backups
```

## Backup Scope

**What IS backed up:**
- ✅ PostgreSQL databases (Immich, N8N, Nextcloud, Boards)
- ✅ SQLite databases (Grafana, Sonarr, Radarr, Jellyfin, etc.)
- ✅ All service configs
- ✅ Prometheus metrics
- ✅ Traefik certificates

**What is NOT backed up:**
- ❌ Media files (/mnt/media) - too large
- ❌ Container images - rebuild from compose
- ❌ Logs - not needed for restore

---

**Need more details?** See full documentation in `docs/BACKUP.md`
