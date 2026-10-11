# backup role

Installs `/usr/local/bin/quadraplex-backup` (from `templates/backup.sh.j2`) and a daily systemd timer,
or runs/restores on demand. See `docs/BACKUP.md` for how backups work and how to restore.

| `backup_action` | Does |
|---|---|
| `setup` | Install packages, rclone config, the script and `backup-daily.timer` |
| `daily` | Run a backup now (archives, retention, S3 copy) |
| `s3` | Copy existing archives to S3 now |
| `restore` | Restore a stack or service (`tasks/restore.yml`) |

Key variables (`defaults/main.yml`, overridden in `inventory/group_vars/all/vars.yml`):
`backup_base_dir`, `backup_retention_local`, `backup_retention_remote`, `backup_stacks`,
`backup_excludes`, `backup_s3_*`, `backup_gotify_*`.
