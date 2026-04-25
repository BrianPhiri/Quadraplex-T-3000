# Backup & Restore Strategy

Comprehensive dual-tier backup system for Quadraplex-T-3000 infrastructure with local and remote storage.

## Overview

The backup system provides:
- **Local backups** to `/backup` for fast recovery (14-day retention)
- **Remote backups** to S3-compatible storage for disaster recovery (90-day retention)
- **Automated scheduling** via systemd timers
- **Database backups** (PostgreSQL + SQLite) with integrity verification
- **Config snapshots** with compression
- **One-command restore** with safety checks and dry-run mode

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Backup Sources                        │
├─────────────────────────────────────────────────────────┤
│ • PostgreSQL DBs (Immich, N8N, Nextcloud, Boards)      │
│ • SQLite DBs (Grafana, Uptime Kuma, Sonarr, Radarr...) │
│ • Configs (/opt/*/configs/)                             │
│ • Prometheus TSDB                                       │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│              Local Storage (/backup/)                    │
├─────────────────────────────────────────────────────────┤
│ /backup/                                                │
│   ├── proxy/                                            │
│   │   ├── databases/                                    │
│   │   ├── configs/                                      │
│   │   └── data/                                         │
│   ├── dns/                                              │
│   ├── media/                                            │
│   └── utility/                                          │
│                                                          │
│ Retention: 14 days                                      │
│ Use: Fast local recovery                                │
└─────────────────────────────────────────────────────────┘
                        ↓ (rclone sync)
┌─────────────────────────────────────────────────────────┐
│          Remote S3 Storage (External)                    │
├─────────────────────────────────────────────────────────┤
│ s3://quadraplex-backups/                                │
│   └── {hostname}/                                       │
│       ├── proxy/                                        │
│       ├── dns/                                          │
│       ├── media/                                        │
│       └── utility/                                      │
│                                                          │
│ Retention: 90 days                                      │
│ Use: Disaster recovery                                  │
└─────────────────────────────────────────────────────────┘
```

## Backup Scope

### What IS Backed Up

| Type | Frequency | Services | Size |
|------|-----------|----------|------|
| **PostgreSQL DBs** | Hourly | Immich, N8N, Nextcloud, Boards | ~100MB-5GB |
| **SQLite DBs** | Daily | Grafana, Uptime Kuma, Vaultwarden, Sonarr, Radarr, Prowlarr, Jellyfin, Kavita | ~10MB-500MB |
| **Configs** | Daily | All stacks (proxy, dns, media, utility) | ~50MB |
| **Prometheus TSDB** | Daily | Metrics data (via snapshot API) | ~500MB-2GB |

### What is NOT Backed Up

- `/mnt/media/` - Large media files (movies, TV shows, music)
- Container images (rebuild from docker-compose)
- Temporary files and logs
- Redis cache (ephemeral data)

**Total estimated backup size:** 1-10GB depending on Prometheus retention

## Initial Setup

### 1. Configure S3 Credentials

Edit and encrypt your vault file:

```bash
# Edit vault
ansible-vault edit inventory/group_vars/vault.yml

# Add these variables:
vault_backup_s3_access_key: "your_access_key_here"
vault_backup_s3_secret_key: "your_secret_key_here"
vault_backup_s3_endpoint: "https://s3.wasabisys.com"  # or your S3 endpoint

# Optional: Add database passwords if not already present
vault_immich_db_password: "your_immich_password"
vault_n8n_db_password: "your_n8n_password"
vault_nextcloud_db_password: "your_nextcloud_password"
vault_boards_db_password: "your_boards_password"

# Optional: Gotify notifications
vault_backup_gotify_token: "your_gotify_token"
```

### 2. Customize Backup Settings (Optional)

Edit `inventory/group_vars/all.yml` to customize:

```yaml
# Backup retention
backup_retention_local: 14    # Days to keep local backups
backup_retention_remote: 90   # Days to keep S3 backups

# S3 configuration
backup_s3_bucket: "quadraplex-backups"
backup_s3_region: "us-east-1"

# Enable Gotify notifications on failure
backup_gotify_enabled: true
backup_gotify_url: "http://localhost:8080"
```

### 3. Deploy Backup Infrastructure

```bash
# Install rclone, create directories, deploy systemd timers
make backup-setup TARGET=your-host

# Verify setup
make backup-status TARGET=your-host
make backup-timers TARGET=your-host
```

### 4. Test S3 Connection

```bash
# Test S3 connectivity
make s3-test TARGET=your-host

# Expected output: List of buckets or successful connection message
```

### 5. Run Initial Backup

```bash
# Run complete initial backup
make backup TARGET=your-host

# Check results
make backup-status TARGET=your-host

# Sync to S3
make backup-s3 TARGET=your-host
```

## Usage

### Running Backups

```bash
# Full backup (all databases, configs, data)
make backup TARGET=your-host

# Backup specific stack only
make backup TARGET=your-host STACK=media
make backup TARGET=your-host STACK=utility

# Backup by type
make backup-postgres TARGET=your-host   # PostgreSQL only (hourly critical)
make backup-sqlite TARGET=your-host     # SQLite only
make backup-config TARGET=your-host     # Configs only
make backup-data TARGET=your-host       # Data directories only
make backup-daily TARGET=your-host      # Full daily (SQLite+config+data+retention)

# Sync to S3
make backup-s3 TARGET=your-host

# Clean up old backups
make backup-retention TARGET=your-host
```

### Automated Backups

Systemd timers are automatically configured:

| Timer | Schedule | What it backs up |
|-------|----------|------------------|
| `backup-postgres-hourly.timer` | Every hour | PostgreSQL databases (critical) |
| `backup-daily.timer` | Daily at 2:00 AM | SQLite, configs, data, retention cleanup |
| `backup-s3-sync.timer` | Every 6 hours | Sync local → S3 |

Check timer status:
```bash
make backup-timers TARGET=your-host

# Or directly with systemctl:
ssh your-host systemctl list-timers 'backup-*'
```

### Monitoring Backups

```bash
# Show backup summary and recent backups
make backup-status TARGET=your-host

# View systemd timer schedules
make backup-timers TARGET=your-host

# View backup logs
make backup-logs TARGET=your-host
make backup-logs-postgres TARGET=your-host
make backup-logs-daily TARGET=your-host
make backup-logs-s3 TARGET=your-host

# Verify backup integrity
make backup-verify TARGET=your-host

# S3 management
make s3-list TARGET=your-host
make s3-size TARGET=your-host
```

### Restoring from Backup

#### List Available Backups

```bash
# List all backups for a stack
make restore-list STACK=utility TARGET=your-host

# Or manually:
ssh your-host find /backup/utility/databases -type f -ls
```

#### Restore Latest Backup

```bash
# Dry-run first (preview what will happen)
make restore-dry-run SERVICE=grafana STACK=utility LATEST=true TARGET=your-host

# If dry-run looks good, restore for real
make restore SERVICE=grafana STACK=utility LATEST=true TARGET=your-host
```

#### Restore Specific Date

```bash
# Find backup date from restore-list, then restore
make restore SERVICE=grafana STACK=utility DATE=20260425T120000 TARGET=your-host
```

#### Restore from S3 (Disaster Recovery)

```bash
# Restore from remote S3 backup
make restore-remote SERVICE=grafana STACK=utility DATE=20260425 TARGET=your-host

# This will:
# 1. Download backup from S3
# 2. Restore to local system
# 3. Restart service
```

## Restore Examples

### Example 1: Restore Grafana Database

```bash
# 1. List available backups
make restore-list STACK=utility TARGET=prod-01

# 2. Dry-run to preview
make restore-dry-run SERVICE=grafana STACK=utility LATEST=true TARGET=prod-01

# 3. Confirm and restore
make restore SERVICE=grafana STACK=utility LATEST=true TARGET=prod-01
# Confirm when prompted: yes

# 4. Verify
ssh prod-01 docker logs grafana
```

### Example 2: Restore PostgreSQL Database (Immich)

```bash
# Restore Immich database from specific date
make restore SERVICE=immich STACK=media DATE=20260425T140000 TARGET=prod-01

# Warning: This will DROP and recreate the database!
# Confirm: yes
```

### Example 3: Disaster Recovery from S3

```bash
# Server crashed, need to restore from S3
make restore-remote SERVICE=n8n STACK=utility DATE=20260424 TARGET=new-server

# This downloads from S3 and restores
```

## Backup Schedule Summary

| Time | Action | What |
|------|--------|------|
| Every hour | PostgreSQL backup | Immich, N8N, Nextcloud, Boards |
| 2:00 AM | Daily full backup | SQLite, configs, Prometheus TSDB |
| 2:00 AM | Retention cleanup | Remove backups > 14 days old |
| Every 6 hours | S3 sync | Upload all new backups to S3 |
| (S3 lifecycle) | S3 retention | Remove backups > 90 days old |

## Troubleshooting

### Backup Failed

```bash
# Check logs
make backup-logs TARGET=your-host

# Check specific service logs
make backup-logs-postgres TARGET=your-host
make backup-logs-daily TARGET=your-host

# Check disk space
ssh your-host df -h /backup

# Manual backup test
ssh your-host
cd /root/ansible
ansible-playbook playbooks/backup.yml --limit localhost --extra-vars "backup_action=postgres" -vv
```

### S3 Sync Failed

```bash
# Test connection
make s3-test TARGET=your-host

# Check S3 credentials
ssh your-host cat /root/.config/rclone/rclone.conf

# Manual S3 test
ssh your-host rclone lsd s3backup:

# Check S3 logs
make backup-logs-s3 TARGET=your-host
```

### Restore Failed

```bash
# Common issues:

# 1. Container not running
ssh your-host docker ps --filter name=SERVICE_NAME

# 2. Backup file not found
make restore-list STACK=utility TARGET=your-host

# 3. Database connection issues
ssh your-host docker logs SERVICE_NAME

# 4. Permissions issues
ssh your-host ls -la /backup/STACK/databases/
```

### Disk Space Issues

```bash
# Check backup size
make backup-status TARGET=your-host

# Force retention cleanup
make backup-retention TARGET=your-host

# Find largest backups
ssh your-host du -sh /backup/* | sort -h

# Manual cleanup (if needed)
ssh your-host find /backup -name '*.dump' -mtime +7 -delete
```

## Security Considerations

1. **Vault Encryption**: All S3 credentials and database passwords are encrypted in `vault.yml`
2. **Backup Permissions**: All backups are `0600` (root only) on the server
3. **S3 Encryption**: Server-side AES256 encryption enabled by default
4. **Network Transfer**: rclone uses HTTPS for S3 transfers
5. **Database Passwords**: Passed securely via environment variables

## Performance Impact

- **PostgreSQL backups**: Minimal impact (uses pg_dump, no locks)
- **SQLite backups**: Brief lock during backup (< 1 second for most DBs)
- **Config backups**: No service impact (rsync of config files)
- **Prometheus backup**: Uses snapshot API (no service disruption)
- **S3 sync**: Background process, bandwidth throttled to 4 transfers

## Advanced Configuration

### Backup Specific Service

Edit `roles/backup/defaults/main.yml` to add/remove services from backup scope.

### Change Backup Schedule

Edit `roles/backup/tasks/systemd-timers.yml` and change `timer_on_calendar` values.

### Custom S3 Provider

For Backblaze B2, Wasabi, or other S3-compatible:

```yaml
# In all.yml
backup_s3_provider: "Wasabi"  # or "Backblaze", "Other"
backup_s3_endpoint: "https://s3.wasabisys.com"
backup_s3_region: "us-east-1"
```

### Exclude Specific Services

```yaml
# In playbook or command line
--extra-vars "backup_action=postgres backup_target_stack=utility"
```

## FAQ

**Q: How much disk space do I need for backups?**
A: Plan for 5-10GB for local backups (14 days). S3 will grow to 20-60GB (90 days).

**Q: Can I backup media files (/mnt/media)?**
A: Not by default (too large). For media backup, use a separate rsync/rclone strategy or exclude media from your backup needs.

**Q: What happens if I restore while the service is running?**
A: PostgreSQL restores drop connections and recreate the database. SQLite restores stop the container first.

**Q: Can I restore to a different server?**
A: Yes! Use `restore-remote` to download from S3 and restore to any server.

**Q: How do I test restores?**
A: Always use `make restore-dry-run` first to preview changes. Test restores regularly in a staging environment.

**Q: What if rclone/S3 is down?**
A: Local backups continue working. S3 sync will retry on next scheduled run (every 6 hours).

## Support Commands Reference

```bash
# Quick reference
make backup-help                          # Show detailed help

# Setup
make backup-setup TARGET=host             # Initial setup

# Backup
make backup TARGET=host                   # Full backup
make backup TARGET=host STACK=media       # Stack-specific

# Restore
make restore SERVICE=x STACK=y DATE=z TARGET=host
make restore-dry-run SERVICE=x STACK=y LATEST=true TARGET=host

# Monitor
make backup-status TARGET=host            # Status & size
make backup-timers TARGET=host            # Timer schedules
make backup-logs TARGET=host              # Recent logs
make backup-verify TARGET=host            # Integrity check

# S3
make s3-test TARGET=host                  # Test connection
make s3-list TARGET=host                  # List backups
make s3-size TARGET=host                  # Show size
```

## Files Created by Backup System

```
/backup/                          # Local backup root
  ├── proxy/
  ├── dns/
  ├── media/
  │   ├── databases/
  │   │   ├── immich_20260425T120000.dump
  │   │   ├── sonarr_20260425T020000.db.gz
  │   │   └── radarr_20260425T020000.db.gz
  │   ├── configs/
  │   │   └── media_20260425T020000.tar.gz
  │   └── data/
  └── utility/
      ├── databases/
      │   ├── n8n_20260425T150000.dump
      │   ├── grafana_20260425T020000.db.gz
      │   └── uptime_kuma_20260425T020000.db.gz
      ├── configs/
      │   └── utility_20260425T020000.tar.gz
      └── data/
          └── prometheus_20260425T020000.tar.gz

/root/.config/rclone/rclone.conf  # S3 configuration
/etc/systemd/system/
  ├── backup-postgres-hourly.service
  ├── backup-postgres-hourly.timer
  ├── backup-daily.service
  ├── backup-daily.timer
  ├── backup-s3-sync.service
  └── backup-s3-sync.timer
```

## Next Steps

1. ✅ Complete initial setup (`make backup-setup`)
2. ✅ Configure S3 credentials in vault
3. ✅ Run test backup (`make backup`)
4. ✅ Verify S3 sync (`make s3-test && make backup-s3`)
5. ✅ Monitor timers (`make backup-timers`)
6. ✅ Test restore in dry-run mode
7. ⏰ Schedule regular restore tests (monthly)
8. 📊 Optional: Setup Gotify notifications
9. 📊 Optional: Create Grafana dashboard for backup metrics

---

**Last Updated**: April 25, 2026
**Backup System Version**: 1.0.0
