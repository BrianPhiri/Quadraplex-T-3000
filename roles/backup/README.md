# Backup Role

Comprehensive backup and restore system for Quadraplex-T-3000 infrastructure.

## Features

- **Dual-tier backup strategy**: Local `/backup` directory + remote S3-compatible storage
- **Database backups**: PostgreSQL (hourly) and SQLite (daily) with compression and integrity checks
- **Config backups**: Rsync-based snapshots of all stack configurations
- **Data backups**: Prometheus TSDB snapshots and other persistent data
- **Automated retention**: 14 days local, 90 days remote
- **Automated scheduling**: systemd timers for unattended operation
- **Restore capabilities**: Restore from local or remote backups with safety checks

## Backup Scope

### PostgreSQL Databases (Hourly)
- Immich (media stack)
- N8N (utility stack)
- Nextcloud (utility stack)
- Boards (utility stack)

### SQLite Databases (Daily)
- Grafana, Uptime Kuma, Vaultwarden (utility stack)
- Sonarr, Radarr, Prowlarr, Jellyfin, Kavita (media stack)

### Configurations (Daily)
- Traefik (proxy stack)
- AdGuard Home (DNS stack)
- All media services configs
- All utility services configs

### Data (Daily)
- Prometheus TSDB
- Other persistent service data

## Usage

See playbooks/backup.yml and makefiles/backup.mk for usage examples.

## Configuration

Default variables in `defaults/main.yml`. Override in inventory or playbook vars.

Key variables:
- `backup_base_dir`: Local backup directory (default: /backup)
- `backup_retention_local`: Days to keep local backups (default: 14)
- `backup_retention_remote`: Days to keep S3 backups (default: 90)
- `backup_s3_enabled`: Enable S3 sync (default: true)
- `backup_s3_*`: S3 connection details (set in vault)

## S3 Configuration

Set in inventory/group_vars/vault.yml:
```yaml
backup_s3_access_key: "your_access_key"
backup_s3_secret_key: "your_secret_key"
backup_s3_endpoint: "https://s3.example.com"
backup_s3_bucket: "quadraplex-backups"
```

## Systemd Timers

- `backup-postgres-hourly.timer`: Hourly PostgreSQL backups
- `backup-daily.timer`: Daily full backups (SQLite, configs, data) at 2 AM
- `backup-s3-sync.timer`: S3 sync every 6 hours

## Restore Process

Restore operations support dry-run mode and require explicit confirmation before modifying data.

## Notifications

Optional Gotify integration for backup failure alerts. Set `backup_gotify_enabled: true` and configure endpoint/token.
