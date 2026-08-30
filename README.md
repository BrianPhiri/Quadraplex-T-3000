# Quadraplex-T-3000
An overly complicated homelab setup that also acts as documentation and templete for others (only reason it's public).
It installs **Docker**, configures **Traefik** as a reverse proxy, and orchestrates application stacks including:

- **Media services (Arr stack)** – Radarr, Sonarr, Lidarr, etc.  
- **Monitoring tools** – Prometheus, cAdvisor, Grafana, Uptime Kuma.  
- **Management utilities** – Portainer, Vaultwarden, and helper services.  

All services are grouped into stacks, making it easy to enable or disable specific apps and extend the setup with new deployments.  

---

## Folder Structure
```
Quadraplex-T-3000/
├── ansible.cfg # Ansible configuration
├── Makefile # Root task shortcuts (includes makefiles/*.mk)
├── README.md # Documentation
├── .gitignore # Ignore rules
│
├── makefiles/ # Make target definitions, split by concern
│ ├── docker.mk # Docker install/management targets
│ ├── user.mk # Host user creation
│ ├── base-stack.mk # Generic deploy/status/logs/restart for any stack (STACK=)
│ ├── proxy.mk # Traefik proxy stack targets (deploy-proxy, proxy-*)
│ ├── backup.mk # Backup & restore targets
│ └── clamav.mk # ClamAV targets (currently disabled — see root Makefile)
│
├── inventory/ # Inventory definitions
│ ├── hosts.yml # The actual inventory used by every make target
│ └── group_vars/ # Group-specific variables (incl. vault.yml)
│
├── playbooks/ # Entry-point playbooks
│ ├── deploy-stack.yml # Deploys a stack (media/utility/dns) via dynamic-stack role
│ ├── deploy-proxy.yml # Deploys the Traefik proxy stack
│ ├── deploy-clamav.yml
│ ├── install-docker.yml
│ ├── create-users.yml
│ ├── backup.yml
│ └── restore.yml
│
├── roles/ # Modular Ansible roles
│ ├── docker/ # Docker installation/config
│ ├── traefik/ # Reverse proxy (Traefik) setup
│ ├── dynamic-stack/ # Services-as-data templating engine (renders docker-compose.yml)
│ ├── base-stack/ # Generic Compose lifecycle used by any stack (see role README)
│ ├── backup/ # Backup & restore automation
│ ├── pre-checks/ # Pre-flight checks (Docker present, Python venv, etc.)
│ ├── users/ # Host user management
│ └── clamav/ # ClamAV deployment (currently disabled at the Makefile level)
│
├── vars/ # Declarative stack/service configuration
│ ├── versions.yml # Pinned Docker/containerd/compose versions
│ ├── proxy/ # Proxy (Traefik) base/vault config + routes
│ └── stacks/ # One folder per stack (media, utility, dns)
│ ├── media/ # base.yml (services-as-data) + vault.yml
│ ├── utility/
│ └── dns/
│
└── docs/ # Reference docs (e.g. BACKUP.md)
```
## Tools Used
- **[Ansible](https://www.ansible.com/):** Provisioning, configuration, deployment.  
- **[Make](https://www.gnu.org/software/make/):** Task runner for common operations.  
- **Bash:** Utility scripts for secrets, backups, and host operations.

## What It Does
1. **System Prep**  
   - Installs prerequisites.  
   - Configures Docker daemon and networking.  

2. **Reverse Proxy**  
   - Deploys Traefik for HTTPS and routing.  
   - Manages TLS, middlewares, and service discovery.  

3. **Media Stack**  
   - Deploys Radarr, Sonarr, Lidarr, and related services.  

4. **Monitoring & Utilities**  
   - **Prometheus & cAdvisor** – metrics collection.  
   - **Grafana** – dashboards and visualization.  
   - **Uptime Kuma** – uptime monitoring.  
   - **Portainer** – Docker management UI.  

5. **Secrets & Backup**  
   - Vaultwarden for secure storage.  
   - Automated backup and restore playbooks.  

---
## How to Run

### 1. Prerequisites
- Control machine:  
  - **Ansible ≥ 2.13**  
  - **Python ≥ 3.8**  
  - `make` installed  
- Managed hosts:  
  - Linux (tested on Debian/Ubuntu)  
  - SSH access  

### 2. Customize host
- Edit inventory/hosts.yml and adjust group_vars/ and host_vars/ for your environment.

### 3. Run make commands

## Make Commands

The root `Makefile` just `include`s one file per concern from `makefiles/`. Run `make help` at
any time for a live, auto-generated list (it greps every included file's `## comment` on each
target). The sections below group the commands by which file they come from.

| File | Concern |
|---|---|
| `makefiles/docker.mk` | Install/manage Docker itself on a host |
| `makefiles/user.mk` | Create the host user(s) stacks run as |
| `makefiles/base-stack.mk` | Deploy/manage **any** stack (media, utility, dns) — the generic interface |
| `makefiles/proxy.mk` | Deploy/manage the Traefik proxy stack specifically |
| `makefiles/backup.mk` | Backup & restore |
| `makefiles/clamav.mk` | ClamAV — present but **not included** by the root Makefile (disabled/unmaintained) |

---

### Docker Installation & Management (`makefiles/docker.mk`)

Uses `ENV` as an Ansible group/limit pattern (default inventory group, e.g. `all`) and `HOST` for
a single host.

`make install-docker ENV=production` - Install Docker on every host in the `ENV` group.
`make install-docker-host HOST=media-prod-01` - Install Docker on one specific host.
`make install-docker-parallel ENV=production` - Install Docker across the group in parallel (`install_serial=0`).
`make docker-info` / `docker-version` / `docker-test` - Inspect / verify a Docker install.
`make docker-status` / `docker-logs` / `docker-restart` - Check or manage the Docker service.
`make docker-cleanup` / `docker-disk-usage` - `system prune` / `system df`.
`make docker-validate` - Re-run the install playbook with `--tags validate,test` only.
`make docker-daemon-reload` - `daemon-reload` + restart Docker.
`make docker-users-check` - Show who's in the `docker` group.
`make docker-debug ENV=production` - Re-run the install playbook with `-vvv`.
`make docker-remove ENV=production` - **Destructive.** Uninstalls Docker and deletes `/var/lib/docker`, `/etc/docker`. Prompts for confirmation.

---

### Stack Deployment (`makefiles/base-stack.mk`)

This is the generic engine for every stack under `vars/stacks/` (currently `media`, `utility`,
`dns`) — adding a new stack directory there makes it deployable with the same commands, no new
Makefile code needed.

Key parameters:

| Var | Meaning | Default |
|---|---|---|
| `STACK` | Stack name, matches a `vars/stacks/<name>/` directory | *(required)* |
| `ENV` | Environment overlay name | `production` |
| `TARGET` | Inventory host/group to act on | *(required for most commands)* |
| `TAGS` / `SKIP_TAGS` | Ansible tags to include/exclude | — |
| `SERIAL` | Hosts to deploy to at once | `1` |
| `SERVICE` | Restrict `logs`/`restart` to one compose service | all |
| `TAIL` | Log line count for `logs` | `50` |
| `VERBOSE` | Ansible verbosity (`v`/`vv`/`vvv`/`vvvv`) | — |
| `CHECK` | `true` to run in check/diff (dry-run) mode | `false` |

Commands:

`make deploy STACK=media ENV=production TARGET=media_host` - Deploy (or update) a stack.
`make dry-run STACK=media TARGET=media_host` - Same as `deploy` with `--check --diff`.
`make deploy-all STACK=media TARGET=media_host` - Deploy with an "all hosts in group" confirmation prompt.
`make status STACK=media TARGET=media_host` - `docker compose ps` for the stack.
`make logs STACK=media TARGET=media_host SERVICE=sonarr TAIL=100` - Tail service logs.
`make restart STACK=media TARGET=media_host SERVICE=radarr` - Restart the whole stack, or one service.
`make stop` / `make start` / `make down` - Stop / start / stop+remove the stack's containers (`down` prompts for confirmation).
`make pull STACK=media TARGET=media_host` - Pull latest images.
`make update STACK=media TARGET=media_host` - `pull` then `deploy`.
`make list-stacks` - List every stack under `vars/stacks/` and its env files.
`make list-hosts` - `ansible-inventory --graph`.
`make show-config STACK=media ENV=production` - Print the stack's `base.yml` + `<ENV>.yml`.
`make ping TARGET=media_host` - Ansible ping check.
`make facts TARGET=media_host` - Gather and print Ansible facts.
`make check-syntax` - `--syntax-check` on both `deploy-stack.yml` and `deploy-proxy.yml`.
`make init-stack STACK=newstack` - Scaffold a new `vars/stacks/newstack/` directory.
`make help` - Full command + parameter reference with examples (covers this file's targets).

> **Note:** `ENV`/`production`/`staging` overlay files are currently a no-op — the overlay
> `vars_files` line in `playbooks/deploy-stack.yml` is commented out, so only `base.yml` is ever
> loaded regardless of `ENV`. The parameter is kept (and still passed through as `environment=`)
> for forward compatibility, but don't expect a `staging.yml` to actually change behavior yet.

---

### Proxy Stack (`makefiles/proxy.mk`)

The Traefik reverse proxy is deployed separately from the generic stack engine above, since it
has its own playbook (`playbooks/deploy-proxy.yml`) and domain/subdomain parameters. Targets are
`proxy-`/`deploy-proxy`-prefixed so they never collide with `base-stack.mk`'s bare verbs; shared
helpers (`list-hosts`, `ping`, `validate-target`, `help`) come from `base-stack.mk` and aren't
duplicated here.

`make deploy-proxy TARGET=primary DOMAIN=example.com SUBDOMAIN=traefik` - Deploy Traefik (domain/subdomain optional — falls back to vars defaults).
`make proxy-dry-run TARGET=primary` - Same as above with `--check --diff`.
`make proxy-status TARGET=primary` - `docker compose ps` for the proxy stack.
`make proxy-logs TARGET=primary SERVICE=traefik TAIL=100` - Tail proxy logs.
`make proxy-restart` / `proxy-stop` / `proxy-start` / `proxy-down TARGET=primary` - Manage the proxy container(s) (`proxy-down` prompts for confirmation).
`make proxy-pull TARGET=primary` - Pull latest Traefik image.
`make proxy-update TARGET=primary` - `proxy-pull` then `deploy-proxy`.
`make proxy-config` - Print the proxy's config files.

---

### Backup & Restore (`makefiles/backup.mk`)

All commands take `TARGET=<host>`; most take `STACK=` to scope to one stack instead of `all`.
Run `make backup-help` for the full built-in reference (params, examples). See `docs/BACKUP.md`
for the complete guide.

`make backup-setup TARGET=host` - Install rclone, create directories, deploy systemd timers.
`make backup TARGET=host [STACK=media]` - Full backup (databases, configs, data).
`make backup-postgres` / `backup-sqlite` / `backup-config` / `backup-data TARGET=host` - Backup one category only.
`make backup-daily TARGET=host` - SQLite + configs + data, plus retention cleanup.
`make backup-s3 TARGET=host` - Sync existing backups to S3.
`make backup-retention TARGET=host` - Apply the retention policy (delete old backups).
`make restore SERVICE=grafana STACK=utility DATE=20260425T120000 TARGET=host` - Restore a service from a specific backup.
`make restore SERVICE=grafana STACK=utility LATEST=true TARGET=host` - Restore the most recent backup.
`make restore-dry-run SERVICE=grafana STACK=utility TARGET=host` - Preview a restore without applying it.
`make restore-remote SERVICE=n8n STACK=utility DATE=20260425 TARGET=host` - Restore from the S3 copy.
`make restore-list STACK=utility TARGET=host` - List available backups for a stack.
`make backup-status` / `backup-timers` / `backup-logs TARGET=host` - Check backup health, systemd timers, recent logs.
`make backup-verify TARGET=host` - Integrity-check dump/db/tarball backups.
`make s3-test` / `s3-list` / `s3-size TARGET=host` - S3 connectivity and usage.

---

### User Management (`makefiles/user.mk`)

`make create-users ENV=production HOST=media_host` - Create the host user(s) stacks run as (`ENV` is the Ansible limit/group, `HOST` is passed through as `target_hosts`).

---

### ClamAV (`makefiles/clamav.mk` — disabled)

A full ClamAV integration (deploy/test/status/logs/update targets, backed by `roles/clamav/` and
`playbooks/deploy-clamav.yml`) exists but its `include` is commented out in the root `Makefile`
because it hasn't been verified against the current stack layout. Uncomment
`#include makefiles/clamav.mk` in the root `Makefile` if you want to use/test it.

