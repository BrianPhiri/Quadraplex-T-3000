# Backups

## How it works

`make backup-setup TARGET=home` installs `/usr/local/bin/quadraplex-backup` and `backup-daily.timer`
(02:00 every day). The host needs neither Ansible nor this repo. Each run:

1. **Archives each stack.** It writes one `<stack>_<timestamp>.tar.gz` per stack (`/opt/proxy`,
   `/opt/dns-stack`, `/opt/media-stack`, `/opt/utility-stack`) to `/mnt/media/backups/<stack>/`.
2. **Copies databases safely.** It finds every SQLite database in a stack automatically and copies it
   with `sqlite3 .backup`, which is safe while the app is running, then integrity-checks the copy.
   Files sqlite3 can't open (BoltDB, for example) are copied as-is. Any running Postgres container is
   dumped with `pg_dumpall` to `/mnt/media/backups/postgres/`.
3. **Skips caches.** Caches, logs, artwork/metadata and Prometheus/Loki history are left out (see
   `backup_excludes` in `roles/backup/defaults/main.yml`).
4. **Applies local retention.** Local archives older than `backup_retention_local` (14) days are deleted.
5. **Copies to S3.** Archives are copied, not mirrored, to `s3backup:quadraplex-backups/<host>/`, and
   S3 keeps them for `backup_retention_remote` (90) days.

New services need no backup config: anything under a stack directory is included.

Failures (including S3) make the systemd unit fail. Check them with `make backup-status` /
`make backup-logs`. Set `backup_gotify_enabled: true` to get a Gotify message on failure.

## S3

Credentials live in `inventory/group_vars/all/vault.yml`:

```yaml
vault_backup_s3_access_key: "..."   # Backblaze: the keyID
vault_backup_s3_secret_key: "..."   # Backblaze: the applicationKey
vault_backup_s3_endpoint: "s3.us-west-002.backblazeb2.com"
```

After changing them, run `make backup-setup TARGET=home`, then `make s3-test TARGET=home`.

## Restore

```bash
make restore-list STACK=media TARGET=home                        # list archives
make restore-dry-run STACK=media SERVICE=mylar TARGET=home      # preview
make restore STACK=media SERVICE=mylar TARGET=home               # newest archive
make restore STACK=media SERVICE=mylar DATE=20261011 TARGET=home
make restore STACK=media TARGET=home                             # whole stack
make restore STACK=media DATE=20261011 FROM_S3=true TARGET=home  # fetch from S3 first
```

With `SERVICE`, only `configs/<service>` and `data/<service>` are restored, with that container
stopped. Without it, the whole stack is stopped (`<stack>-stack.service`), restored and restarted.

Manual restore without Ansible: stop the container or stack, then
`tar -xzf <archive> -C /opt/<stack dir> ./configs/<service>`.
