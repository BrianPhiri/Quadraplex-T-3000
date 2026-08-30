# Security Audit — Quadraplex-T-3000

_Generated: 2026-08-30 — based on current working-tree code, including uncommitted changes._

## Summary

**Total findings: 1 Critical, 5 High, 8 Medium, 5 Low, 3 Informational**

The good news up front: `ansible-vault` is used correctly and consistently. Every file that should be encrypted (`inventory/group_vars/vault.yml`, `vars/stacks/*/vault.yml`, `vars/proxy/vault.yml`) is genuinely `$ANSIBLE_VAULT;1.1;AES256`-encrypted, and no hardcoded plaintext passwords, API keys, or tokens were found anywhere in `vars/`, `roles/`, or `inventory/`. `inventory/hosts.yml` uses SSH-key auth (`ansible_ssh_private_key_file: ~/.ssh/id_ed25519`), not a plaintext password. Sensitive rendered files (`.env`, `rclone.conf`, `acme.json`) are correctly written with `mode: '0600'`.

---

## Critical

1. **`roles/dynamic-stack/templates/services/calico.yml.j2`** — `privileged: true` + `network_mode: host` + **read-write** `/var/run/docker.sock:/var/run/docker.sock` mount. RW docker.sock + privileged + host networking is a full host-compromise vector (trivial container escape via `docker run -v /:/host ...` from inside). This template is currently **not referenced/enabled by any vars file** (dead code as shipped — `vars/stacks/*/base.yml` has no `calico` key), but it's a live landmine: if anyone flips it on, it's an instant root-equivalent host takeover from any code running in that container. Recommend removing it or gating it very explicitly.

## High

2. **`roles/dynamic-stack/templates/services/portracker.yml.j2`** — combines `pid: "host"`, `cap_add: [SYS_PTRACE, SYS_ADMIN]`, `security_opt: [apparmor:unconfined]`, and a RO docker.sock mount, and is `enabled: true` with `traefik.enabled: true` in `vars/stacks/utility/base.yml`. `SYS_PTRACE` + `pid: host` is a well-known container-escape/host-process-memory-read technique (CIS Docker Benchmark flags this combo explicitly), and `apparmor:unconfined` strips the one MAC layer that would otherwise limit it. Since this container is also fronted by Traefik, a vulnerability in the portracker app itself becomes a host-compromise vector, not just a container-compromise vector.

3. **`roles/dynamic-stack/templates/services/portainer.yml.j2`** — publishes `8000:8000`, `9000:9000`, and the configured HTTPS port **directly to the host** (no bind IP → binds `0.0.0.0`) in addition to being Traefik-fronted, and mounts docker.sock RO. Portainer's full docker-control UI is reachable directly on the LAN, bypassing Traefik's TLS/auth entirely, and RO docker.sock is trivially sufficient to read every other container's environment variables (including secrets) via `docker inspect`. Recommend binding to `127.0.0.1:` or removing the direct port publish since Traefik already fronts it.

4. **`roles/dynamic-stack/templates/services/cadvisor.yml.j2`** and **`node_exporter.yml.j2`** — both publish unauthenticated metrics endpoints directly to the host (`"{{ port }}:8080"` / `"{{ port }}:9100"`, no bind IP), and both are `enabled: true` in `vars/stacks/utility/base.yml` (ports 8081/9100) with no Traefik front-door or auth. cAdvisor additionally mounts `/:/rootfs:ro`, `/var/lib/docker:ro`; node_exporter mounts `/:/host:ro,rslave` with `pid: host`. Anyone who can reach the host's IP on those ports (any device on the LAN, or the WAN if the router has UPnP/port-forwarding) gets full container/process/filesystem metadata with zero authentication. Recommend binding these to `127.0.0.1:` since they're meant to be scraped by the co-located Prometheus, not browsed directly.

5. **`roles/dynamic-stack/templates/services/prometheus.yml.j2`** — the `ports:` block is **unconditional** (unlike every other service template, which wraps `ports:` in `{% if services.X.port is defined %}`), so Prometheus is always published to `0.0.0.0:9090` with `--web.enable-lifecycle` (unauthenticated `/-/reload`) and no auth. This is inconsistent with the rest of the codebase's pattern. Compounding risk: `roles/backup/tasks/data-backup.yml` calls `POST http://localhost:9090/api/v1/admin/tsdb/snapshot`, which requires `--web.enable-admin-api` to work — not currently set, but if someone adds it later to make backups work, the destructive admin API (can delete time-series data) becomes reachable from the whole LAN with zero auth, since the port is already open to `0.0.0.0`.

6. **`roles/dynamic-stack/templates/services/adguard_home.yml.j2`** — `network_mode: host` with hardcoded `3000:3000/tcp` exposure. In host-network mode, Docker `ports:` entries are cosmetic; AdGuard's first-run setup wizard (unauthenticated until an admin password is created) binds to all host interfaces on port 3000. Exposed/forgotten AdGuard setup wizards are a known real-world compromise vector (attacker completes setup and takes over DNS for the network). No AdGuardHome.yaml is pre-seeded with credentials in this repo, so the exposure window depends entirely on the operator completing setup promptly.

## Medium

7. **`roles/docker/templates/docker.service.override.j2`** (lines 6-8) — templates an **unauthenticated, non-TLS** Docker daemon TCP listener (`tcp://0.0.0.0:2375`) gated by `docker_daemon_port_enabled` (defaults to `false` in `roles/docker/defaults/main.yml`). Dormant by default, but if ever flipped on for convenience, it's remote-root-equivalent to anyone who can reach port 2375 — no TLS client-cert option is wired up at all.
8. **No `no_log: true` anywhere in the repo** (confirmed via grep — zero matches). Tasks that template files containing real secrets — `roles/backup/tasks/main.yml` "Configure rclone for S3" (embeds S3 access/secret keys), `roles/traefik/tasks/configs.yml`/`dynamic-stack` `.env` generation (Cloudflare API token, Traefik dashboard credentials) — have no `no_log`. Files themselves land at `0600`, which is correct, but running any of these playbooks with `-v`/`--diff` (a very normal debugging habit) or on task failure can print secret values or diffs to the console/CI log. Add `no_log: true` to every task that templates a secret-bearing file.
9. **Silent insecure fallback defaults**: `vars/stacks/media/base.yml:234` (Immich DB password), `vars/stacks/utility/base.yml:182,187,189,200` (n8n encryption key, n8n DB passwords, Grist secret) all fall back to the literal string `"changeme"` if the corresponding vault variable isn't set, via `{{ vault_x | default('changeme') }}`. If an operator forgets to populate vault.yml for a given service, the stack deploys silently with a known, guessable credential instead of failing loudly. Prefer `{{ vault_x | mandatory('vault_x must be set') }}` or similar fail-fast behavior.
10. **`roles/dynamic-stack/templates/services/netbird.yml.j2`** — `privileged: true` **plus** `cap_add: [NET_ADMIN, SYS_ADMIN, SYS_RESOURCE]` **plus** `network_mode: host`. NetBird's docs generally only require `NET_ADMIN`/`SYS_ADMIN` for userspace WireGuard; adding `privileged: true` on top is redundant/overbroad defense-in-depth violation, not fatal on its own but worth trimming since this container also handles a plaintext-in-transit setup key.
11. **`roles/traefik/templates/traefik.yml.j2`** — `serversTransport.insecureSkipVerify` defaults to `true` (line 18) and `api.debug` defaults to `true` (line 4). Disabling backend TLS verification means Traefik won't validate certs of any HTTPS backend it proxies to (MITM exposure inside the docker network — low practical risk on a private bridge network, but a bad default to ship), and `debug: true` in production increases the chance of sensitive data ending up in verbose logs.
12. **`roles/dynamic-stack/templates/services/etcd.yml.j2`** binds `ETCD_LISTEN_PEER_URLS`/`ETCD_LISTEN_CLIENT_URLS` to `0.0.0.0` with no auth — only a real issue if etcd's ports are ever published to the host (no `ports:` block currently does so, but the etcd/calico pairing looks like abandoned/incomplete work — same caveat as finding #1).
13. **`roles/dynamic-stack/templates/services/portracker.yml.j2`** additionally supports an optional `TRUENAS_API_KEY` environment variable (line 16) sourced from `services.portracker.truenas_api_key` — verify that variable is vault-sourced wherever it's actually set (not present in the currently-tracked vars files, so likely fine, but flag for whoever configures TrueNAS integration).
14. **cAdvisor/node_exporter/Prometheus** — cAdvisor/node_exporter run without a `user:` directive (Prometheus/Grafana/Loki correctly set `user: "{{ stack_config.user_id }}:{{ stack_config.group_id }}"`). cAdvisor/node_exporter necessarily need broader host access to do their job (upstream images run root by design), so this is more "inherent to the tool" than a fixable misconfiguration — noted for completeness rather than as an actionable fix.

## Low

15. Standard `arr`-stack containers (Sonarr/Radarr/Prowlarr/Bazarr/Lidarr/etc.), Jellyfin, qBittorrent, etc. run without explicit `user:` directives, relying on PUID/PGID env vars for privilege drop inside the container (the images' own entrypoint handles this) — acceptable pattern for these particular images.
16. `roles/base-stack/tasks/directories.yml` / `roles/traefik/tasks/directories.yml` — all directories created with `mode: '0755'`, no `0777` anywhere. Fine, but config dirs holding per-service data (some including app-level secrets, e.g. `sonarr.db` API keys) are world-readable at the directory level (`0755`) though owned by the stack user — low risk in a single-user homelab, would matter more multi-tenant.
17. `roles/backup/tasks/postgres-backup.yml` passes `PGPASSWORD` via the Ansible `environment:` dict rather than a CLI arg — this is actually the *correct* pattern (avoids the password showing in `ps aux`), noted as a positive control.
18. Command/shell tasks that interpolate variables (`docker exec {{ item.container }} pg_dump -U {{ item.user }} ...`, `sqlite3 {{ item.path }} ...`) all pull `item.*` from a **static, hardcoded** `backup_services` dict in `roles/backup/defaults/main.yml` — not from any externally-influenced input, so injection risk is theoretical/self-inflicted only.
19. `roles/backup/tasks/main.yml` installs rclone via `curl https://rclone.org/install.sh | bash` (curl-pipe-to-bash). Standard practice for homelabs but worth knowing it trusts rclone.org's install script unconditionally with no checksum verification.

## Informational

20. `roles/dynamic-stack/templates/services/prometheus.yml.j2`'s `ports:` block being unconditional (vs. every sibling template's `{% if port is defined %}` guard) looks like an accidental inconsistency rather than an intentional design choice — worth confirming with whoever wrote it.
21. `vars/stacks/media/production.yml`, `vars/stacks/utility/production.yml` are currently empty (0 bytes) — not a vulnerability, but means there's currently no environment-specific override layer in use.
22. `roles/dynamic-stack/templates/.env.j2` is a 0-byte file — likely a stub/placeholder; not security-relevant but flagged since it looked suspicious during the audit (turned out benign).

---

## Homelab-trust-model context

Given the single-host, single-operator, LAN-only nature of this deployment, the **Critical** (`calico.yml.j2`) and most of the docker.sock-related **High** findings are real but currently *dormant* (calico isn't wired into any vars file) or *narrowed* (Traefik/Cloudflare suggest actual internet exposure only for domains explicitly routed through Traefik with TLS+DNS challenge — most raw ports like cadvisor/node_exporter/prometheus are LAN-only unless the router forwards them). The findings that would matter **even in a pure homelab** are:

- The RW docker.sock + privileged + host-network combo in `calico.yml.j2` (a landmine if ever activated).
- The `portracker` SYS_PTRACE+pid:host+apparmor:unconfined combo (real escape primitive, and it's actually enabled).
- The missing `no_log` on secret-templating tasks (real leak vector any time `--diff`/`-v` is used).
- The `"changeme"` silent-fallback passwords (a classic "forgot to fill in the vault" trap).

Everything else (cadvisor/node_exporter/prometheus bound to 0.0.0.0, AdGuard host networking) is low-stakes on a trusted home LAN but would be an immediate finding in any multi-tenant or internet-adjacent context — worth fixing regardless since it costs little (just add `127.0.0.1:` bind prefixes).
</content>
