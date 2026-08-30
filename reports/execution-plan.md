# Execution Plan — Quadraplex-T-3000

_Generated: 2026-08-30 — consolidates all seven prior reports (`diff-review.md`,
`architecture-review.md`, `security-audit.md`, `security-remediation-plan.md`,
`internal-server-audit.md`, `external-recon.md`, `nikto-scan.md`) into one ordered, batched
checklist. Finding numbers (`#1`-`#22`) match `security-audit.md`/`security-remediation-plan.md`
throughout. Check items off (`- [x]`) as they're done — this file is meant to be edited in place
as we work through it._

**How to use this**: work through batches roughly in order. Within Batch 1 everything is
independent — do them in any order, or all at once. From Batch 2 onward, read the "why this
order" note before starting, since some items depend on earlier ones or on you making a call.

---

## Batch 0 — Already done ✅

- [x] Makefile consolidation, dead-code removal, docs cleanup, README rewrite — see
      `reports/simplification-plan.md` (fully executed, nothing left to do here).

---

## Batch 1 — Git hygiene (do this first, before any further code edits)

Every remaining code batch below touches files that are *already* mid-diff from your in-progress
Loki/Promtail/qui/profilarr work. Splitting that into logical commits now, before piling more
changes on top, keeps history readable and makes every batch after this one a clean, reviewable
diff of its own.

| # | Task | Difficulty | Breaking? |
|---|---|---|---|
| 1.1 | Split the current working-tree diff into commits per `reports/diff-review.md`'s suggestion: (1) service-membership-check + networking bug fixes, (2) Loki/Promtail logging stack, (3) qui/profilarr services, (4) misc unrelated tweaks (IP change, Makefile locale fix, pairdrop toggle) | Trivial (just `git add -p` / staged commits, no code changes) | None |
| 1.2 | Commit the already-completed Batch 0 simplification work separately from the above | Trivial | None |

---

## Batch 2 — Do now: trivial, non-breaking, zero operator decisions

Everything here is either a manual one-off cleanup, or a code change with no behavioral downside
for how you currently use the system.

| # | Task | Where | Difficulty | Breaking? |
|---|---|---|---|---|
| 2.1 | **Fix local SSH key permissions** — `chmod 600 ~/.ssh/id_ed25519 && sudo chown brian:brian ~/.ssh/id_ed25519*` on this control machine (found world-readable, root-owned, during the recon session) | Control machine | Trivial | None |
| 2.2 | **Free disk space on the server** — `docker rmi` the leftover images for disabled services (calibre 3.4GB, shelfmark 1.25GB, lazylibrarian 389MB, audiobookshelf 320MB, pairdrop 125MB ≈ 5.5GB). Server is at **363MB free / 100% full** — this is the most urgent item in the whole plan | Server (manual, SSH) | Trivial | None |
| 2.3 | Clean up stray `docker-compose.yml.<pid>.<timestamp>~` backup files under `/opt/{media,utility,proxy}-stack/` (~35 files, ~280KB, some root-owned) | Server (manual, SSH) | Trivial | None |
| 2.4 | **Deploy the backup system** — `make backup-setup TARGET=<host>` per `docs/BACKUP.md`, then verify with `make backup-status`. Currently **zero backups exist** despite the feature being fully built | `roles/backup/`, run via Makefile | Small | None (purely additive) |
| 2.5 | Delete dead `roles/dynamic-stack/templates/services/calico.yml.j2` + `etcd.yml.j2` (Findings #1, #12) — confirmed unreferenced by any vars file, confirmed no such containers exist on the server | Code | Trivial | None — *but confirm first these aren't parked for a future Calico rollout; if they are, rename to `.disabled` instead of deleting* |
| 2.6 | Add `no_log: true` to the secret-templating tasks (Finding #8): `roles/backup/tasks/main.yml` (rclone config), `roles/traefik/tasks/configs.yml` (`.env` generation), `roles/base-stack/tasks/configs.yml` (`.env` generation) | Code | Small | None |
| 2.7 | Replace `\| default('changeme')` with `\| mandatory(...)` for the 5 vault fallbacks (Finding #9): `vars/stacks/media/base.yml:234`, `vars/stacks/utility/base.yml:182,187,189,200` | Code | Trivial | None today (immich/n8n/grist are all `enabled: false`) — only affects the moment someone enables one of those services without first populating its vault entry, which is the intended effect |
| 2.8 | Fix `roles/dynamic-stack/templates/services/prometheus.yml.j2`'s unconditional `ports:` block to match every sibling template's `{% if port is defined %}` pattern, and add a `127.0.0.1:` bind (Findings #5, #20) | Code | Trivial | Non-breaking for Prometheus/Grafana/backups (all reach it over the internal Docker network or loopback). **Breaking only if you currently browse `http://<host-ip>:9090` directly** — you'd lose that; Grafana remains the intended UI |
| 2.9 | Add `127.0.0.1:` bind to `cadvisor.yml.j2` / `node_exporter.yml.j2` (Finding #4) | Code | Trivial | Same caveat as 2.8 — non-breaking for Prometheus scraping, breaking only for direct browser/curl access to `:8081`/`:9100` from another LAN device |
| 2.10 | Traefik `debug` default → `false` in `roles/traefik/templates/traefik.yml.j2` (Finding #11, debug half only — not `insecureSkipVerify`, that's Batch 4) | Code | Trivial | None (only affects log verbosity) |

**Note on 2.8/2.9**: nikto/nmap confirmed these are *currently* reachable directly on your LAN
with no auth. If you rely on hitting them by raw IP:port from your phone or another device, do
that check before applying — otherwise these are the highest safety-per-effort fixes in the whole
plan.

---

## Batch 3 — Do soon: small/moderate effort, changes an access path (tell yourself before doing)

Why this order: these are safe and correct, but each one changes *how you reach something* —
worth doing deliberately, not on autopilot, since you're both the implementer and the one who has
to remember the new way in afterward.

| # | Task | Difficulty | Breaking? |
|---|---|---|---|
| 3.1 | **qui + profilarr: add Traefik basicauth middleware, drop their direct host-port publish** (`7476`, `6868`) — new finding from the live scans (both are double-exposed: Traefik-fronted with no auth *and* directly published). Reuse the existing `traefik-auth` basicauth pattern from `roles/traefik/templates/docker-compose.yml.j2:34` | Moderate — needs a vault-sourced htpasswd secret + template/vars edits for both services | **Breaking**: removes unauthenticated direct-LAN access to both; going forward you'd reach them only via their Traefik hostname + a basic-auth login you set up |
| 3.2 | **Restart Profilarr** (`docker restart profilarr` on the server) — it's been unresponsive since the nikto scan wedged it; you said "leave it, check later" | Trivial | None (recovers the hung process) |
| 3.3 | Investigate Profilarr's fragility long-term — check if `santiagosayshey/profilarr`'s gunicorn setup supports `--workers`/`--timeout` tuning, since a single ordinary `HEAD`/`OPTIONS`/404 request was enough to hang it | Small-moderate (may require an upstream image change or entrypoint override, not just an Ansible edit) | None if done as an addition; risk is only in getting the gunicorn flags wrong |
| 3.4 | Disable SSH `PasswordAuthentication` — no role currently manages `sshd_config`, so this needs a small new task (e.g. in `roles/pre-checks/` or a new minimal role) setting `PasswordAuthentication no` and reloading `sshd` | Small | **Breaking in the strict sense** (removes an enabled auth method) but **zero practical impact** — your key-based login is already confirmed working and is the only method you actually use |

---

## Batch 4 — Needs your hands-on verification first (wrong guess breaks a working feature)

These three are flagged by the remediation plan as needing you to actually test the change, not
just trust that the "looks unnecessary" read of the Ansible template is correct for this specific
app/version.

| # | Task | Difficulty | Breaking if wrong? |
|---|---|---|---|
| 4.1 | **Portracker**: strip `pid: "host"`, `SYS_PTRACE`, `SYS_ADMIN`, `apparmor:unconfined` from `roles/dynamic-stack/templates/services/portracker.yml.j2` (Finding #2) — confirmed live and running with all of these right now. Redeploy, then manually verify Portracker still lists ports correctly (some "what's using this port" tools genuinely need `pid: host` to see non-Dockerized host processes) | Small edit, moderate verification | Yes, if Portracker's port-listing feature actually depends on host-process visibility — test before considering done |
| 4.2 | **NetBird**: remove `privileged: true` from `roles/dynamic-stack/templates/services/netbird.yml.j2`, keep the three explicit `cap_add` entries (Finding #10) — confirmed live with `privileged: true` set. Redeploy, then verify peer-to-peer connectivity and routing still work | Small edit, moderate verification | Yes — could break VPN connectivity/routing if NetBird needs a capability not in the explicit list |
| 4.3 | **Traefik `insecureSkipVerify`**: audit which Traefik-fronted backends serve HTTPS with self-signed certs (Portracker/Portainer templates both support an https backend scheme) before flipping the default to `false` in `roles/traefik/templates/traefik.yml.j2` (Finding #11, TLS-verify half) | Moderate (audit pass across all Traefik-labeled services first) | Yes — any backend with a self-signed cert starts 502ing the moment verification turns on, until that backend's cert/scheme is fixed |
| 4.4 | Confirm calico/etcd decision from 2.5 if you skipped it there — is Calico genuinely on the roadmap, or fully abandoned? | Trivial (just a decision) | None |

---

## Batch 5 — Bigger hardening: new roles/infra (highest care — risk of self-lockout)

These are real gaps (confirmed by the internal audit: no firewall, no fail2ban, unrestricted
passwordless sudo) but each needs enough care that rushing it risks locking yourself out of your
own home server.

| # | Task | Difficulty | Breaking / risk |
|---|---|---|---|
| 5.1 | **Host firewall**: enable `ufw` with an explicit `allow 22/tcp` rule **before** `ufw enable`, plus rules for whatever else should be LAN/WAN-reachable (80, 443 at minimum; decide per-service for the rest) | Moderate-large (new role/task; needs careful, tested rule set) | **High risk if done carelessly** — enabling `ufw` without first allowing SSH cuts off your only remote access to the box. Test from console/physical access if at all possible, not purely over SSH |
| 5.2 | **fail2ban**: install with an `sshd` jail | Small-moderate (new role) | Low risk — just monitors `auth.log`; set a sane ban threshold so you don't lock yourself out during your own testing |
| 5.3 | **Narrow `/etc/sudoers.d/brian`'s `NOPASSWD:ALL`** to specific commands, or explicitly accept and document the current "single-operator homelab" threat model instead | Moderate-large | **High risk** — Ansible's own `become: true` tasks across every role currently rely on this being unrestricted; narrowing it without auditing every privileged task first will break deploys, not just harden the box |

---

## Batch 6 — Deferred architecture cleanup (optional, non-security, low urgency)

Carried over from `reports/architecture-review.md`, explicitly deferred during the Batch 0
simplification pass. No security or operational urgency — do these whenever you feel like a
bigger refactor.

| # | Task | Difficulty |
|---|---|---|
| 6.1 | Fold `roles/traefik` into the generic `dynamic-stack`/`base-stack` pattern instead of its hand-duplicated lifecycle tasks | Large — needs a full test deploy of the proxy stack to verify nothing regresses |
| 6.2 | Consolidate monitoring config templates (`prometheus`/`loki`/`promtail`) into one role's template tree instead of split across `base-stack`/`dynamic-stack` | Moderate — mostly file-organization, low behavioral risk, but touches the same files as the in-progress logging-stack work, so do it after that's committed |

---

## No action needed (reviewed and accepted as-is)

For completeness/closure — these were investigated and correctly require nothing:

- **Finding #7** (dormant Docker daemon TCP port) — already safe-by-default, optional comment only.
- **Finding #13** (Portracker `TRUENAS_API_KEY`) — not currently used anywhere; just remember to vault-source it when you do configure TrueNAS integration.
- **Finding #14** (cAdvisor/node_exporter no `user:`) — inherent to how those tools work; Prometheus already has the directive.
- **Finding #15** (arr-stack/Jellyfin/qBittorrent no `user:`) — PUID/PGID pattern is correct for these images.
- **Finding #17** (`PGPASSWORD` via `environment:`) — already the correct pattern.
- **Finding #18** (shell interpolation from a static hardcoded dict) — no externally-influenced input, theoretical only.
- **Finding #19** (`curl \| bash` rclone install) — acceptable for a homelab initial-setup task; optional distro-package swap if you want it, not required.
- **Finding #21** (empty `production.yml` overlays) — already deleted in Batch 0.
- **Finding #22** (0-byte `.env.j2` stubs) — confirmed benign, covered defensively by 2.6's `no_log` addition.

---

## Suggested pacing

If you want one thing to anchor each work session:

1. **Batch 1 + 2** in one sitting — it's all trivial/small and non-breaking; the disk-space and
   backup items (2.2, 2.4) are the two that actually protect you from data loss and should not
   wait.
2. **Batch 3** next — mostly about qui/profilarr, contained to two services.
3. **Batch 4** when you have time to sit and watch a redeploy for each — these need verification,
   not just an edit.
4. **Batch 5** on a day you're near the physical machine or have console access as a fallback, in
   case a firewall rule goes wrong.
5. **Batch 6** whenever, no rush.

Let me know which batch you want to start on and I'll work through it with you.
</content>
