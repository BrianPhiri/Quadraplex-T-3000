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

## Quickstart

Get the backup system running in about 5 minutes.

**Prerequisites**: Ansible-deployed Quadraplex-T-3000 infrastructure, an S3-compatible storage account
(Backblaze B2, Wasabi, AWS S3, etc.), and root/sudo access to the target host.

1. **Configure S3 credentials** (2 min)

   ```bash
   ansible-vault edit inventory/group_vars/vault.yml
   ```

   Add:
   ```yaml
   vault_backup_s3_access_key: "YOUR_ACCESS_KEY"
   vault_backup_s3_secret_key: "YOUR_SECRET_KEY"
   vault_backup_s3_endpoint: "https://s3.wasabisys.com"  # your S3 endpoint
   ```

2. **Deploy backup infrastructure** (1 min) — installs rclone, creates directories, sets up systemd timers

   ```bash
   make backup-setup TARGET=your-host-name
   ```

3. **Test the S3 connection** (30 sec)

   ```bash
   make s3-test TARGET=your-host-name
   ```

4. **Run the initial backup** (1 min)

   ```bash
   make backup TARGET=your-host-name
   make backup-s3 TARGET=your-host-name
   ```

5. **Verify everything works** (30 sec)

   ```bash
   make backup-status TARGET=your-host-name
   make s3-list TARGET=your-host-name
   make backup-timers TARGET=your-host-name
   ```

Once set up, backups run automatically: PostgreSQL every hour, a full daily backup (SQLite, configs,
Prometheus data) at 2 AM, and an S3 sync every 6 hours. Old backups are cleaned up automatically
(14 days locally, 90 days on S3).

**Recommended next step** — test a restore before you need one for real:

```bash
make restore-dry-run SERVICE=grafana STACK=utility LATEST=true TARGET=your-host
make restore SERVICE=grafana STACK=utility LATEST=true TARGET=your-host   # if the dry-run looks good
```

The rest of this document is the fuller reference: architecture, full command list, restore
procedures, troubleshooting, and configuration details.

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

## Configuration

### S3 Credentials (required)

```bash
ansible-vault edit inventory/group_vars/vault.yml
```

```yaml
vault_backup_s3_access_key: "your_access_key_here"
vault_backup_s3_secret_key: "your_secret_key_here"
vault_backup_s3_endpoint: "https://s3.wasabisys.com"  # or your S3 endpoint

# Optional: database passwords if not already present
vault_immich_db_password: "your_immich_password"
vault_n8n_db_password: "your_n8n_password"
vault_nextcloud_db_password: "your_nextcloud_password"
vault_boards_db_password: "your_boards_password"

# Optional: Gotify notifications
vault_backup_gotify_token: "your_gotify_token"
```

**Where to get S3 credentials:** [Backblaze B2](https://www.backblaze.com/b2/cloud-storage.html)
(10GB free), [Wasabi](https://wasabi.com/) (1TB free trial), or [AWS S3](https://aws.amazon.com/s3/).

### Backup Settings (optional)

Edit `inventory/group_vars/all.yml`:

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

Systemd timers are configured automatically by `make backup-setup`:

| Timer | Schedule | What it backs up |
|-------|----------|------------------|
| `backup-postgres-hourly.timer` | Every hour | PostgreSQL databases (critical) |
| `backup-daily.timer` | Daily at 2:00 AM | SQLite, configs, data, retention cleanup |
| `backup-s3-sync.timer` | Every 6 hours | Sync local → S3 |

```bash
make backup-timers TARGET=your-host
# or directly:
ssh your-host systemctl list-timers 'backup-*'
```

### Monitoring Backups

```bash
make backup-status TARGET=your-host       # Summary and recent backups
make backup-timers TARGET=your-host       # Systemd timer schedules
make backup-logs TARGET=your-host         # Backup logs
make backup-logs-postgres TARGET=your-host
make backup-logs-daily TARGET=your-host
make backup-logs-s3 TARGET=your-host
make backup-verify TARGET=your-host       # Verify backup integrity

# S3 management
make s3-list TARGET=your-host
make s3-size TARGET=your-host
```

## Restoring from Backup

### List Available Backups

```bash
make restore-list STACK=utility TARGET=your-host
# or manually:
ssh your-host find /backup/utility/databases -type f -ls
```

### Restore Latest Backup

```bash
# Dry-run first (preview what will happen)
make restore-dry-run SERVICE=grafana STACK=utility LATEST=true TARGET=your-host

# If it looks good, restore for real
make restore SERVICE=grafana STACK=utility LATEST=true TARGET=your-host
```

### Restore Specific Date

```bash
# Find the backup date from restore-list, then:
make restore SERVICE=grafana STACK=utility DATE=20260425T120000 TARGET=your-host
```

### Restore from S3 (Disaster Recovery)

```bash
make restore-remote SERVICE=grafana STACK=utility DATE=20260425 TARGET=your-host
# Downloads the backup from S3, restores locally, and restarts the service.
```

### Restore Examples

**Restore Grafana database:**
```bash
make restore-list STACK=utility TARGET=prod-01
make restore-dry-run SERVICE=grafana STACK=utility LATEST=true TARGET=prod-01
make restore SERVICE=grafana STACK=utility LATEST=true TARGET=prod-01   # confirm: yes
ssh prod-01 docker logs grafana
```

**Restore PostgreSQL database (Immich):**
```bash
make restore SERVICE=immich STACK=media DATE=20260425T140000 TARGET=prod-01
# Warning: this drops and recreates the database. Confirm: yes
```

**Disaster recovery from S3:**
```bash
make restore-remote SERVICE=n8n STACK=utility DATE=20260424 TARGET=new-server
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
make backup-logs TARGET=your-host
make backup-logs-postgres TARGET=your-host
make backup-logs-daily TARGET=your-host
ssh your-host df -h /backup

# Manual backup test
ssh your-host
cd /root/ansible
ansible-playbook playbooks/backup.yml --limit localhost --extra-vars "backup_action=postgres" -vv
```

### S3 Sync Failed

```bash
make s3-test TARGET=your-host
ssh your-host cat /root/.config/rclone/rclone.conf
ssh your-host rclone lsd s3backup:
make backup-logs-s3 TARGET=your-host
```

### Restore Failed

```bash
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
make backup-status TARGET=your-host
make backup-retention TARGET=your-host
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

| Operation | Impact | Duration |
|-----------|--------|----------|
| PostgreSQL backup | Minimal (uses pg_dump, no locks) | 30-120s per DB |
| SQLite backup | Brief lock (<1s for most DBs) | 5-30s per DB |
| Config backup | None (rsync of config files) | 10-30s |
| Prometheus backup | None (uses snapshot API) | 30-60s |
| S3 sync | Background, throttled to 4 transfers | 1-10 min |

## Advanced Configuration

**Backup specific service**: edit `roles/backup/defaults/main.yml` to add/remove services from
backup scope.

**Change backup schedule**: edit `roles/backup/tasks/systemd-timers.yml` and change
`timer_on_calendar` values.

**Custom S3 provider** (Backblaze B2, Wasabi, or other S3-compatible), in `all.yml`:

```yaml
backup_s3_provider: "Wasabi"  # or "Backblaze", "Other"
backup_s3_endpoint: "https://s3.wasabisys.com"
backup_s3_region: "us-east-1"
```

**Exclude specific services**:

```yaml
# In playbook or command line
--extra-vars "backup_action=postgres backup_target_stack=utility"
```

## Known Limitations

1. **Media files not backed up**: `/mnt/media` excluded due to size
2. **Requires PostgreSQL passwords**: must be set in vault for PostgreSQL backups
3. **S3 required for remote backup**: no alternative remote storage implemented
4. **Manual Gotify setup**: notification setup is optional and manual
5. **No backup encryption layer**: relies on S3 server-side encryption

## Possible Future Enhancements

- Grafana dashboard for backup metrics
- Automated restore testing
- Email notifications (in addition to Gotify)
- Differential backups for large data
- Backup encryption layer (in addition to S3)
- Immich uploaded-photos backup
- Multi-region S3 replication
- Backup compression ratio metrics

## FAQ

**Q: How much disk space do I need for backups?**
A: Plan for 5-10GB for local backups (14 days). S3 will grow to 20-60GB (90 days).

**Q: Can I backup media files (/mnt/media)?**
A: Not by default (too large). Use a separate rsync/rclone strategy if you need this.

**Q: What happens if I restore while the service is running?**
A: PostgreSQL restores drop connections and recreate the database. SQLite restores stop the
container first.

**Q: Can I restore to a different server?**
A: Yes — use `restore-remote` to download from S3 and restore to any server.

**Q: How do I test restores?**
A: Always use `make restore-dry-run` first to preview changes. Test restores regularly.

**Q: What if rclone/S3 is down?**
A: Local backups continue working. S3 sync retries on the next scheduled run (every 6 hours).

## Command Reference

```bash
make backup-help                          # Show detailed help

# Setup
make backup-setup TARGET=host             # Initial setup

# Backup
make backup TARGET=host                   # Full backup
make backup TARGET=host STACK=media       # Stack-specific

# Restore
make restore SERVICE=x STACK=y DATE=z TARGET=host
make restore-dry-run SERVICE=x STACK=y LATEST=true TARGET=host
make restore-remote SERVICE=x STACK=y DATE=z TARGET=host
make restore-list STACK=y TARGET=host

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

## Files Created by the Backup System (reference)

On the target host:

```
/backup/                          # Local backup root
  ├── proxy/
  ├── dns/
  ├── media/
  │   ├── databases/
  │   ├── configs/
  │   └── data/
  └── utility/
      ├── databases/
      ├── configs/
      └── data/

/root/.config/rclone/rclone.conf  # S3 configuration
/etc/systemd/system/
  ├── backup-postgres-hourly.service / .timer
  ├── backup-daily.service / .timer
  └── backup-s3-sync.service / .timer
```

In the repo, the feature lives in:

```
roles/backup/
├── README.md                    # Role-specific documentation
├── defaults/main.yml            # Default variables & service definitions
├── handlers/main.yml            # Systemd handlers
├── tasks/
│   ├── main.yml                 # Main orchestration
│   ├── postgres-backup.yml
│   ├── sqlite-backup.yml
│   ├── config-backup.yml
│   ├── data-backup.yml
│   ├── retention.yml
│   ├── s3-sync.yml
│   ├── restore.yml
│   └── systemd-timers.yml
└── templates/
    ├── backup-systemd.service.j2
    ├── backup-systemd.timer.j2
    └── rclone.conf.j2

playbooks/backup.yml             # Backup orchestration playbook
playbooks/restore.yml            # Restore orchestration playbook
makefiles/backup.mk              # `make backup-*` / `make restore-*` command interface
```

## Next Steps Checklist

1. Complete initial setup (`make backup-setup`)
2. Configure S3 credentials in vault
3. Run a test backup (`make backup`)
4. Verify S3 sync (`make s3-test && make backup-s3`)
5. Monitor timers (`make backup-timers`)
6. Test a restore in dry-run mode
7. Schedule regular restore drills (monthly)
8. Optional: set up Gotify notifications
9. Optional: create a Grafana dashboard for backup metrics

---

**Last Updated**: April 25, 2026
**Backup System Version**: 1.0.0
