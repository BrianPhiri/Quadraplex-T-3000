# Internal Server Audit — `deborah` (192.168.100.26)

_Generated: 2026-08-30 — SSH-based, read-only inspection with passwordless sudo available for the
`brian` user. Cross-referenced against `reports/external-recon.md`, `reports/security-audit.md`,
and the live Ansible codebase in this repo._

## Summary

The host is in reasonable day-to-day shape (all four stack systemd units active, no obvious
compromise indicators, vault/secret files correctly `0600`, live container inventory matches the
Ansible vars files with **zero drift**), but three things need attention soon:

1. **The backup system documented in `docs/BACKUP.md` and implemented in `roles/backup/` is not
   deployed on this host at all.** No `backup-*` systemd units, no `/backup` directory, no
   `rclone` binary installed. There are currently **zero backups** of this server, despite the
   recent "implement comprehensive backup and restore system" commit.
2. **The root filesystem is at 100% capacity (363M free out of 57G)**, driven mainly by
   `/var/lib/docker` (40G) — including several GB of images for **disabled** services (`calibre`
   3.41GB, `shelfmark` 1.25GB, `lazylibrarian` 389MB, `audiobookshelf` 320MB, `pairdrop` 125MB — all
   `enabled: false` in vars but their images were pulled and never removed). This is a real
   operational risk: a full root disk can break Docker, package installs, and logging with no
   warning, and it's already essentially there.
3. **No host firewall (`ufw` inactive, `iptables` INPUT/OUTPUT policy `ACCEPT` with zero rules) and
   no `fail2ban`** — every container-published port is reachable from the LAN (and from the WAN if
   the router forwards it) with nothing at the OS level standing in the way, and there's no
   automated ban for repeated SSH auth failures. Combined with `brian ALL=(ALL) NOPASSWD:ALL` in
   `/etc/sudoers.d/brian`, a single compromised credential (SSH key or a leaked service password)
   is a straight line to full root on the box.

None of this indicates the host is currently compromised — no unexpected processes, no rogue
listeners, no unauthorized containers were found — but the backup gap and the disk-full condition
are the most urgent to fix, since either one turns a future incident into data loss.

---

## 1. System basics

- `uname -a`: `Linux deborah 6.17.0-41-generic #41-Ubuntu SMP PREEMPT_DYNAMIC Sat Jun 20 18:01:40 UTC 2026 x86_64 GNU/Linux`
- Uptime: 3 days, 15h43m; load average 1.23/1.17/1.11 (idle-ish for a 30GB/many-core box)
- Memory: 30Gi total, 2.6Gi used, 8.2Gi free, 20Gi buff/cache — healthy. Swap: 4.0Gi total, **1.6Gi
  in use** (worth watching, not alarming given 20Gi in cache).
- Disk:
  - `/dev/mapper/ubuntu--vg-ubuntu--lv` (root, `/`): **57G total, 54G used, 363M available, 100%
    used**. This is the top actionable finding — see Summary and Recommendations.
  - `/dev/sda1` (`/mnt/media`): 3.6T total, 852G used, 2.6T available — fine.
  - `/boot`, `/boot/efi`: healthy headroom.
- Pending package updates: `apt list --upgradable` → **20 packages**, dominated by the Docker
  package family (`docker-ce`, `docker-ce-cli`, `docker-ce-rootless-extras`,
  `docker-buildx-plugin`, `docker-compose-plugin` — 29.4.0 → 29.6.2 and a compose plugin bump from
  5.1.3 to 5.3.1). No pending kernel or openssh-server updates seen among the 20.
- `unattended-upgrades`: installed (2.12ubuntu4), systemd unit **enabled and active** — security
  patches should be applying automatically for packages covered by that policy (typically
  `-security` pocket; the Docker packages above are from a third-party repo and unattended-upgrades
  usually doesn't touch those, which is why they're sitting pending).

## 2. Listening ports (internal view) vs. external scan

`sudo ss -tulnp` output, compared to `reports/external-recon.md`:

| Port | Bound to | Process | External scan agrees? |
|---|---|---|---|
| 22/tcp | 0.0.0.0 + `::` | sshd | Yes |
| 53/tcp+udp | `*` (all interfaces) | AdGuardHome | Yes (external saw port 80 for AdGuard's UI; DNS itself wasn't in scope of that scan but is open here) |
| 80/tcp | `*` | AdGuardHome | Yes |
| 82/tcp | 0.0.0.0 + `::` | docker-proxy (Traefik) | Yes |
| 443/tcp | 0.0.0.0 + `::` | docker-proxy (Traefik) | Yes |
| 1900/udp, 7359/udp | 0.0.0.0 + `::` | docker-proxy (Jellyfin discovery) | Not in external table (UDP wasn't scanned — matches the recon report's stated gap) |
| 6868/tcp | 0.0.0.0 + `::` | docker-proxy (Profilarr) | Yes — confirms unauthenticated exposure |
| 6881/tcp+udp | 0.0.0.0 + `::` | docker-proxy (qBittorrent peer) | Yes |
| 7476/tcp | 0.0.0.0 + `::` | docker-proxy (qui) | Yes — confirms unauthenticated exposure |
| 8080/tcp | 0.0.0.0 + `::` | docker-proxy (qBittorrent WebUI) | Yes |
| 8081/tcp | 0.0.0.0 + `::` | docker-proxy (cAdvisor) | Yes |
| 8096/tcp, 8920/tcp | 0.0.0.0 + `::` | docker-proxy (Jellyfin HTTP/HTTPS) | Yes (external table only listed 8096; 8920 is Jellyfin's HTTPS port, likely just not scanned) |
| 9090/tcp | 0.0.0.0 + `::` | docker-proxy (Prometheus) | Yes |
| 9100/tcp | 0.0.0.0 + `::` | docker-proxy (node_exporter) | Yes |
| 127.0.0.1:323, `[::1]:323` | localhost only | chronyd (NTP query) | Not externally visible — correctly localhost-bound, no drift |
| `192.168.100.26%eno1:68` | link-local | systemd-network (DHCP client) | N/A, not a service |

**No surprises in either direction**: everything externally visible was confirmed internally, and
the only internally-visible-but-not-externally-listed items are either UDP (out of scope for the
external nmap pass, as it noted) or genuinely localhost-only (chrony) and thus correctly invisible
from outside. There is no hidden service bound only to `127.0.0.1` that the external scan simply
couldn't see and that would represent extra exposure — the difference is fully explained by the
recon report's own stated gaps.

## 3. Firewall status

- **`ufw status verbose` → `Status: inactive`.** No UFW rules are loaded, despite `ufw.service`
  being `enabled` in systemd (enabled just means "run at boot," not "actually turned on" — it was
  apparently never `ufw enable`-d).
- **`iptables -L -n -v`**: `INPUT` chain policy `ACCEPT`, **zero rules**, zero packets matched.
  `OUTPUT` policy `ACCEPT`, zero rules. `FORWARD` policy `DROP` but immediately delegates to
  Docker's own `DOCKER-USER`/`DOCKER-FORWARD` chains, which contain only the auto-generated rules
  Docker adds per published container port (visible: 8920, 8096, 7359/udp, 1900/udp, 8080, 443, 80,
  9090, 6881, 6868, 9100, 7476 — matching the containers above) plus per-bridge-network isolation
  `DROP` rules for the three unused custom bridge networks.
- **Net effect: there is no host-level firewall filtering inbound host traffic at all.** Every
  service a container publishes to `0.0.0.0` is reachable from anywhere that can route to
  `192.168.100.26`, gated only by whatever auth (or lack of it) the application itself provides.
  Docker's iptables integration controls container-to-container/bridge isolation, not
  host-inbound access control.

## 4. fail2ban

**Not installed.** `dpkg -l fail2ban` returned nothing, `systemctl status fail2ban` → "Unit
fail2ban.service could not be found," `fail2ban-client` → command not found. There is no automated
response to repeated SSH (or any other) auth failures on this host. (For context, `auth.log`
currently shows only 1 historical "Failed password" match, so this isn't evidence of an active
brute-force problem — just an absent safety net.)

## 5. SSH server config

`sudo sshd -T` (effective config, resolves defaults):

| Directive | Value |
|---|---|
| `Port` | 22 |
| `PasswordAuthentication` | **yes** |
| `PubkeyAuthentication` | yes |
| `PermitRootLogin` | without-password (key-only root login is technically possible; no root password login) |
| `KbdInteractiveAuthentication` | no |
| `MaxAuthTries` | 6 |
| `UsePAM` | yes |
| `AllowUsers` / `AllowGroups` | not set (no allow-list — any local account with a valid credential can attempt login) |

This matches `reports/external-recon.md`'s finding exactly: password auth is enabled at the sshd
level even though key-based login is the intended/actual method.

`~/.ssh/authorized_keys` (user `brian`): **1 entry**, comment `ops@brianphiri.com`, type
`ssh-ed25519`. File permissions: `-rw------- brian brian` (0600) inside `~/.ssh` at `drwx------`
(0700) — correct.

## 6. sudo configuration

`sudo -l` for `brian`:
```
User brian may run the following commands on deborah:
    (ALL : ALL) ALL
    (ALL) NOPASSWD: ALL
```
`/etc/sudoers.d/brian` (mode `0440`, root-owned): `brian ALL=(ALL) NOPASSWD:ALL`.

This is unrestricted, passwordless sudo for the primary account — exactly the "common home-lab
foot-gun" the task description called out. It's what made this entire audit possible without an
interactive password, but it's also the single highest-value target for anyone who ever obtains
`brian`'s SSH key or session: no second factor (a sudo password) stands between that credential and
full root.

## 7. Docker container inventory and hardening

22 containers running. Full list (name / image / published ports):

```
adguardhome    adguard/adguardhome                       (host network — 53, 80, 3000 implied)
cadvisor       gcr.io/cadvisor/cadvisor:latest            0.0.0.0:8081->8080
gotify         gotify/server                              (traefik_net only, no host port)
grafana        grafana/grafana:main                       (traefik_net only, no host port)
jellyfin       lscr.io/linuxserver/jellyfin:latest         0.0.0.0:{1900/udp,8096,7359/udp,8920}
kavita         lscr.io/linuxserver/kavita:latest           (traefik_net only)
loki           grafana/loki:3                              (traefik_net only)
mylar          lscr.io/linuxserver/mylar3:latest           (traefik_net only)
netbird        netbirdio/netbird:latest                    (host network, no published port list)
node_exporter  prom/node-exporter:latest                   0.0.0.0:9100->9100
portracker     mostafawahied/portracker:latest             (traefik_net only, no host port)
profilarr      santiagosayshey/profilarr:latest            0.0.0.0:6868->6868
prometheus     prom/prometheus:latest                      0.0.0.0:9090->9090
promtail       grafana/promtail:3                          (traefik_net only)
prowlarr       lscr.io/linuxserver/prowlarr:latest         (traefik_net only)
qbittorrent    lscr.io/linuxserver/qbittorrent:latest       0.0.0.0:{6881 tcp/udp, 8080}
qui            ghcr.io/autobrr/qui:latest                  0.0.0.0:7476->7476
radarr         lscr.io/linuxserver/radarr:latest           (traefik_net only)
seerr          ghcr.io/seerr-team/seerr:latest              (traefik_net only)
sonarr         lscr.io/linuxserver/sonarr:latest            (traefik_net only)
traefik        traefik:v3.6.13                             0.0.0.0:{443, 82->80}
uptime_kuma    louislam/uptime-kuma:1                       (traefik_net only)
```

Hardening spot-checks (`docker inspect`) against the static-audit predictions:

- **`portracker` — CONFIRMED exactly as predicted.** `Privileged=false`, but `CapAdd=[CAP_SYS_ADMIN
  CAP_SYS_PTRACE]`, `PidMode=host`, `SecurityOpt=[apparmor:unconfined label=disable]`, plus a
  **read-only** `/var/run/docker.sock` mount. This is a real container-escape/host-process-read
  primitive and it is actually running, fronted by Traefik (`ports.enabled: true` in
  `vars/stacks/utility/base.yml`).
- **`netbird` — CONFIRMED.** `Privileged=true`, `CapAdd=[CAP_NET_ADMIN CAP_SYS_ADMIN
  CAP_SYS_RESOURCE]`, `NetworkMode=host`. Matches `roles/dynamic-stack/templates/services/netbird.yml.j2` exactly.
- **`calico` / `etcd` — CONFIRMED dead.** No containers with those names exist, running or stopped
  (`docker ps -a` has zero matches). The Critical finding in `reports/security-audit.md`
  (`calico.yml.j2`'s RW docker.sock + privileged + host-network combo) remains **dormant** — the
  template exists in the repo but nothing has ever instantiated it on this host.
- **Read-write docker.sock mounts: none found.** Across all 22 running containers (and all
  containers including stopped, `docker ps -a`), only two mount `/var/run/docker.sock`: `portracker`
  (RO) and `traefik` (RO). `promtail` also mounts `/run/docker.sock` (RO) to read container logs —
  not previously flagged, low risk since it's read-only and Promtail doesn't expose a shell/API.
  No container has a **RW** docker.sock mount.
- **Other broad host-path mounts**: `cadvisor` mounts `/` → `/rootfs` (RO), `/var/lib/docker` (RO),
  `/sys` (RO), `/dev/disk` (RO), `/var/run` (RO) — matches its template, all read-only, inherent to
  the tool. `node_exporter` mounts `/` → `/host` (RO) with `PidMode=host` — also matches its
  template and is inherent to the tool's function.
- No container besides the ones named above runs `Privileged=true`, uses `PidMode=host`, or sets a
  `SecurityOpt` weakening AppArmor.

## 8. Live config drift check

Compared `docker ps` against `vars/stacks/media/base.yml`, `vars/stacks/utility/base.yml`, and
`vars/stacks/dns/base.yml`:

**No drift found.** Every service marked `enabled: true` in the vars files has a matching running
container, and no running container falls outside what the vars files declare:

- **Media stack** (`enabled: true`: prowlarr, sonarr, radarr, seerr, jellyfin, qbittorrent, kavita,
  mylar, profilarr, qui) — all 10 present and running. All `enabled: false` services (filebrowser,
  jellyfin_vue, bazarr, lidarr, releasarr, huntarr, suggestarr, boxarr, immich, freshrss, calibre,
  audiobookshelf, lazylibrarian, shelfmark) correctly have **no** running container — though see
  §11/Recommendations, several of them left orphaned *images* behind.
- **Utility stack** (`enabled: true`: cadvisor, node_exporter, grafana, prometheus, loki, promtail,
  netbird, gotify, uptime_kuma, portracker) — all 10 present. All `enabled: false` services
  (pairdrop, homeassistant, portainer, vaultwarden, filestash, glance, n8n, grist) correctly absent.
- **DNS stack** (`enabled: true`: adguard_home only) — `adguardhome` container present and running
  on `network_mode: host` as the template specifies; `cadvisor`/`node_exporter`/`netbird` are
  `enabled: false` for this stack and correctly absent (the utility stack's own cadvisor/
  node_exporter cover host-wide metrics instead).
- `traefik` (proxy stack, not one of the three vars files reviewed) is running as expected — no
  vars file for it was in scope for this comparison but its presence is expected infrastructure.
- The four Ansible-generated `*-stack.service` systemd units (`dns-stack`, `media-stack`,
  `proxy-stack`, `utility-stack`) are all `active`, meaning each `docker-compose.yml` is being
  brought up correctly on boot.
- No manual/undocumented containers (nothing outside the naming/image set the vars files would
  produce) were found running on the host.

## 9. File permissions on deployed config/secrets

Base paths (from `roles/base-stack/tasks/directories.yml` pattern, `/opt/<stack>-stack/...`):

- `/opt/proxy/.env` — `-rw------- brian docker`, 326 bytes (0600, correct).
- `/opt/utility-stack/.env`, `/opt/media-stack/.env`, `/opt/dns-stack/.env` — all `-rw-------
  brian docker` (0600, correct) but **0 bytes**. These appear to be stub files not actually used
  for secret interpolation in this deployment (per-service secrets are instead embedded directly in
  each container's environment via the rendered `docker-compose.yml`, not via a shared root `.env`)
  — not a security issue, just worth knowing the `.env.j2` templates are effectively unused stubs
  (consistent with finding #22 in `reports/security-audit.md`, which already flagged
  `roles/dynamic-stack/templates/.env.j2` as a 0-byte stub).
- `/opt/proxy/configs/traefik/acme.json` — `-rw------- brian docker` (0600, correct — this holds
  Let's Encrypt private keys and must stay 0600, which it does).
- Top-level `/opt/*` stack directories: `drwxr-xr-x brian docker` (0755) — matches
  `roles/base-stack/tasks/directories.yml`'s `mode: '0755'` exactly, including the noted low-risk
  world-readability of config directory *listings* (not contents) called out as finding #16 in the
  security audit.
- `grep -c "changeme"` across all four `.env` files: **0 matches in every file** — the insecure
  `changeme` vault-fallback pattern flagged as finding #9 in `reports/security-audit.md` does not
  appear to have actually been triggered on this host (the vault variables are populated). This
  particular risk is confirmed **not currently realized** in practice, though the silent-fallback
  code path itself is still present in the vars files and remains a risk for future deploys/new
  operators.
- **Cruft found**: Ansible's `backup: yes`-style templating (or similar) has left numbered
  timestamped backup copies of `docker-compose.yml` scattered in stack directories —
  `/opt/media-stack` has 20 of them, `/opt/utility-stack` has 11, `/opt/proxy` has 4 (total ~280KB,
  not a disk problem, but worth a cleanup pass; some are root-owned from earlier `become: true`
  runs, mixed with brian-owned ones from more recent runs).

## 10. Backup system health

**Not deployed.** Checked against `docs/BACKUP.md`'s described architecture (hourly Postgres,
daily full backup at 2 AM, 6-hourly S3 sync via three systemd timers: `backup-postgres-hourly`,
`backup-daily`, `backup-s3-sync`):

- `sudo systemctl list-timers 'backup-*' --all` → **0 timers listed**.
- `sudo systemctl list-unit-files | grep -i backup` → only `dpkg-db-backup.service`/`.timer`
  (Ubuntu's own unrelated `/var/lib/dpkg` backup), nothing from this repo's `roles/backup/`.
- `rclone` is **not installed** (`which rclone` → not found).
- `/backup` directory (the documented local backup root) **does not exist**.
- No backup-related cron entries either (only the pre-existing ClamAV scan cron job).

This means `make backup-setup TARGET=...` (or the equivalent playbook run) has never actually been
executed against this host, despite `roles/backup/` being fully implemented in the repo and the
recent commit message "feat: implement comprehensive backup and restore system." **There are
currently zero backups — local or remote — of any database, config, or Prometheus data on this
server.** If the disk-full condition in §1 or any other failure destroys `/opt/*/configs` or
`/opt/*/data` right now, none of it is recoverable from a backup.

## 11. Anything else notable

- **Root filesystem at 100% (363M free)** — see Summary. `/var/lib/docker` is 40G of the 54G used.
  `docker system df` shows several multi-hundred-MB-to-multi-GB images for **disabled** services
  still present with 0 attached containers: `calibre` (3.41GB), `shelfmark` (1.25GB),
  `lazylibrarian` (389MB), `audiobookshelf` (320MB), `pairdrop` (125MB). These were evidently pulled
  during testing/iteration on the `media`/`utility` stacks and never cleaned up. `docker images
  -f dangling=true` shows 0 fully-dangling (untagged) images, and only 1 unused volume — so a
  `docker image prune` alone won't reclaim these; they'd need targeted `docker rmi` of the specific
  disabled-service images (a manual, one-off action, not something to run unprompted here).
- **`/var/log/journal` is 907MB** — not urgent, but a contributor to disk pressure; default
  journald retention policy on Ubuntu will eventually rotate it, but with the root disk this full
  it's worth checking `journalctl --disk-usage` and considering a `SystemMaxUse=` cap if not
  already set.
- **`qui` and `profilarr` are double-exposed**, confirming and extending `reports/security-audit.md`
  finding #3's pattern (previously only flagged for Portainer): both containers are (a) fronted by
  Traefik with **no auth middleware** — their labels show only a `redirect-to-https` middleware, no
  `basicauth`/`forwardAuth` — reachable at `qui.media.brianphiri.digital` /
  `profilarr.media.brianphiri.digital` over HTTPS with zero login, **and** (b) separately publish
  their raw ports (`7476`, `6868`) directly to `0.0.0.0` on the host, bypassing Traefik/TLS entirely
  for anyone on the LAN. This matches and confirms `reports/external-recon.md`'s finding.
- 71 world-writable files and 2 world-writable directories found under `/opt`, all confined to
  `/opt/media-stack/configs/mylar/mylar/{logs,cache}/` — these are Mylar's own application log/cache
  files (the container's own process created them with loose permissions), low risk (no secrets,
  not executable), not an Ansible-role issue.
- No unexpected root processes were found — the root-owned processes present are all
  s6-overlay/service-supervisor processes internal to the LinuxServer.io container images
  (`svc-radarr`, `svc-qbittorrent`, `svc-mylar3`, etc., each container's own init), plus normal
  system daemons (`fwupd`, `upowerd`, `nscd`, `netbird up`). Nothing unrecognized.
- No stale/orphaned cron jobs beyond the existing, expected ClamAV scan (`/usr/local/bin/clamav-scan.sh`, every 12h) — consistent with the earlier "Add inventory support to ClamAV makefile" commit.
- `docker --version` → 29.4.0; 5 Docker-related packages have updates pending (29.4.0 → 29.6.2 CE,
  plus buildx/compose plugins) — not urgent (no CVE context checked here) but worth folding into
  routine maintenance.
- SSH brute-force exposure is currently low in practice: `auth.log` shows only 1 historical failed
  password match total, so `PasswordAuthentication yes` + no fail2ban is a latent risk, not
  evidence of an ongoing attack.

---

## Drift from Ansible code

**None of substance.** This is a positive finding: live `docker ps` output matches
`vars/stacks/{media,utility,dns}/base.yml` `enabled:` flags exactly in both directions — nothing
enabled in vars is missing from the running set, and nothing runs that isn't declared. The only
"drift" is cosmetic/operational, not configuration drift:

- Leftover Docker **images** for services that were enabled at some point during iteration and
  later disabled (calibre, shelfmark, lazylibrarian, audiobookshelf, pairdrop) — the vars files and
  running containers agree these are off, but the image layers were never pruned (§11).
- Timestamped `docker-compose.yml.<pid>.<timestamp>~` backup files left in each stack directory by
  the deployment process itself (§9) — cosmetic cruft, not a functional drift.
- The backup system (`roles/backup/`) exists fully in code but has never been applied to this host
  (§10) — this is "code not yet deployed," not "deployed state diverging from code."

## Confirmed vs. Ansible security audit

Going through each Critical/High finding in `reports/security-audit.md` against what live
inspection actually shows:

| # | Finding | Status |
|---|---|---|
| 1 (Critical) | `calico.yml.j2` RW docker.sock + privileged + host-network | **Not deployed / dormant.** No `calico` or `etcd` container exists, running or stopped. The template is dead code as shipped, exactly as predicted. |
| 2 (High) | `portracker` — `pid: host` + `SYS_PTRACE`/`SYS_ADMIN` + `apparmor:unconfined` + RO docker.sock, Traefik-fronted | **CONFIRMED, actively running.** `docker inspect` matches every element of the prediction exactly. |
| 3 (High) | `portainer` double-published directly to host + Traefik, RO docker.sock | **Not applicable — portainer is `enabled: false` and not running.** However, the *same double-exposure pattern* was independently confirmed on `qui` and `profilarr` instead (§11) — the underlying template pattern this finding warned about is real and currently manifesting on two other services. |
| 4 (High) | `cadvisor`/`node_exporter` published unauthenticated to `0.0.0.0`, no Traefik/auth | **CONFIRMED.** Both listening on `0.0.0.0:8081` and `0.0.0.0:9100` respectively with no auth in front, matching the vars-file `enabled: true` state. |
| 5 (High) | `prometheus` unconditionally published to `0.0.0.0:9090`, no auth | **CONFIRMED.** Listening on `0.0.0.0:9090` (and `[::]:9090`), no login. `--web.enable-admin-api` was not observed as an added flag (checked container command), so the destructive-snapshot-API compounding risk described remains theoretical for now. |
| 6 (High) | `adguard_home` host-network, unauthenticated setup wizard on `:3000` | **Partially confirmed / mostly moot.** AdGuardHome is running in `network_mode: host`, but its actual listeners are `:53` (DNS) and `:80` (already past setup, redirects to `/login.html` per the external recon) — port 3000 was not observed as an active listener on this host, meaning first-run setup has already been completed and the exposure window described has already closed. No live risk remains here. |

**Net picture**: the two findings that matter most in a pure-homelab trust model per the audit's
own "Homelab-trust-model context" section — the `portracker` SYS_PTRACE/pid:host/apparmor:unconfined
combo, and the RW-docker.sock+privileged `calico` landmine — are respectively **confirmed live** and
**confirmed still dormant**, exactly bracketing the two ends of the risk spectrum the static audit
predicted.

---

## Recommendations (prioritized)

**Immediate / manual one-off fixes on the box** (not Ansible-role changes, since they're either
one-time cleanup or things Ansible doesn't currently manage):

1. **Free up root disk space now.** Remove the unused images for disabled services (`docker rmi` for
   calibre/shelfmark/lazylibrarian/audiobookshelf/pairdrop tags — reclaims ~5.5GB), and review
   `/var/log/journal` (907MB) for a retention cap. At 363MB free, the host is one log burst or image
   pull away from real trouble.
2. **Deploy the backup system that's already written**: run `make backup-setup TARGET=deborah` (or
   whatever inventory name applies) per `docs/BACKUP.md`'s quickstart, then verify with
   `make backup-status` / `make s3-list`. This is the single highest-value fix here — the code
   exists, it's just never been run on this host.
3. **Clean up the accumulated `docker-compose.yml.<pid>.<timestamp>~` files** in
   `/opt/{media,utility,proxy}-stack/` — cosmetic but worth tidying (some are root-owned from past
   `become: true` runs).

**Fixable via an Ansible role/vars change:**

4. **`vars/stacks/utility/base.yml`** (portracker service block) and
   **`roles/dynamic-stack/templates/services/portracker.yml.j2`** — drop `pid: "host"`,
   `SYS_PTRACE`/`SYS_ADMIN`, and `apparmor:unconfined` unless the tool genuinely can't function
   without them; this is a live, confirmed escape primitive on the running server, not a
   theoretical one.
5. **`vars/stacks/media/base.yml`** (qui/profilarr service blocks) and their templates in
   `roles/dynamic-stack/templates/services/` — either add a `basicauth`/`forwardAuth` Traefik
   middleware (the repo already has a working pattern per `reports/security-remediation-plan.md`)
   or remove their direct host port publishes (`7476`, `6868`) now that they're Traefik-fronted, so
   they aren't reachable unauthenticated on the LAN independent of Traefik.
6. **`roles/dynamic-stack/templates/services/cadvisor.yml.j2` / `node_exporter.yml.j2` /
   `prometheus.yml.j2`** — bind these to `127.0.0.1:` instead of `0.0.0.0` as the external recon
   and static audit both already recommended; confirmed still open to the whole LAN.
7. **Inventory/host config** — set `PasswordAuthentication no` in the templated `sshd_config` (find
   the role that manages it, or add one) now that key-only login is confirmed as the actual and
   only intended method; `MaxAuthTries 6` and modern algorithms are already fine as-is.
8. **New role or task**: install and configure `fail2ban` with an `sshd` jail — there's currently no
   automated response to repeated auth failures anywhere on the host.
9. **New role or task, or extend the existing firewall posture**: either enable `ufw` with explicit
   allow rules for the ports that should be reachable (22, 80, 443, plus whatever's intentionally
   LAN-exposed) or accept the current "Docker manages all inbound filtering" model explicitly and
   document it — right now there's silently no host-level firewall at all, which is easy to mistake
   for "ufw.service is enabled, so we're covered."
10. **`/etc/sudoers.d/brian`** (not templated by this repo as far as this audit could tell — check
    `roles/*/tasks` for wherever it originates) — narrow `NOPASSWD:ALL` to specific commands if
    feasible, or at minimum treat the SSH key as equivalent to a root credential in your own threat
    model (it effectively already is).
11. Once confirmed safe, remove `roles/dynamic-stack/templates/services/calico.yml.j2` and
    `etcd.yml.j2` outright (per the Critical/Medium findings) rather than leaving them as dead code
    a future edit could accidentally wire up — no functional loss since nothing references them.
