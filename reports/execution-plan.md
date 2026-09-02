# Execution Plan — Quadraplex-T-3000

## 📍 Session handoff (read this first)

**Completed this session:** Batch 1 (git hygiene) and Batch 2 (trivial/non-breaking fixes) are
fully done — 18 commits on branch **`chore/batch-1-2-fixes`** (not merged to `main` yet, your
call on when). Working tree is clean, nothing uncommitted.

**Still pending from you before anything else:**
1. ~~**🔴 URGENT — Cloudflare API token expired 2026-07-31**~~ — **✅ fixed 2026-09-02**: you
   generated a new token (`Zone:DNS:Edit` + `Zone:Zone:Read`, scoped to `brianphiri.digital`) and
   updated `vars/proxy/vault.yml` yourself. Redeployed the proxy stack and verified end-to-end:
   token confirmed `active` (valid until Sep 2027) via Cloudflare's own API, plus a full
   create/delete DNS-record functional test (the same sequence the real ACME challenge performs)
   passed cleanly. Traefik hasn't needed to actually renew yet (current wildcard cert is still
   valid until Sep 16), but everything needed for that renewal is confirmed working.
2. **`~/.ssh/id_ed25519` permissions** — still world-readable/root-owned on this control machine.
   Blocked on interactive sudo; run yourself:
   `! sudo chown brian:brian ~/.ssh/id_ed25519* && chmod 600 ~/.ssh/id_ed25519*`
3. **Real Backblaze B2 credentials** — `inventory/group_vars/all/vault.yml` has placeholders
   (`REPLACE_ME_B2_KEY_ID` / `REPLACE_ME_B2_APPLICATION_KEY` / a guessed endpoint). `make s3-test`
   confirms the whole pipeline works end-to-end; it just needs your real key ID/app key/endpoint.
4. **AdGuard's own upstream DNS servers are broken** (its admin-panel config, not this repo's) —
   log in and fix them; the server currently falls back to `1.1.1.1` for its own system DNS as a
   workaround, which works but bypasses AdGuard's ad-blocking for the host's own traffic.
5. **Verify NetBird still connects** next time the utility stack is deployed —
   `vault_netbird_setup_key` now resolves to its real value for the first time (a pre-existing
   `group_vars` loading bug meant it was silently empty before).
6. Merge or open a PR for `chore/batch-1-2-fixes` whenever you're satisfied with it.
7. **When redeploying the proxy stack, always pass `DOMAIN=brianphiri.digital SUBDOMAIN=media`** —
   forgetting this (as happened once this session) regenerates Traefik's dashboard router with the
   placeholder `example.com` domain and breaks dashboard access until redeployed with the correct
   values again. Worth considering hardcoding these as the vars file's defaults instead of relying
   on every `make deploy-proxy` invocation to pass them — see Batch 3 addition below.

**Not started yet:** Batches 3 through 6 below — nothing in them has been touched. Batch 3
(qui/profilarr auth — see update, it's already resolved — plus SSH password auth and the new
domain-default item below) is the natural next step whenever you want to continue.

8. **Jellyfin's trickplay thumbnails are misconfigured** — set to save next to your media files,
   which this repo intentionally mounts read-only, so it's throwing a `Read-only file system`
   error every time it runs (confirmed live, unrelated to the login issue below). Fix from
   Jellyfin's own admin UI: Dashboard → Playback → Trickplay Images → change "Save trickplay
   files" away from the local/next-to-media option. Not an Ansible-managed setting.
9. **Deploy the media stack** to actually apply the `/tmp` volume fix (`df4892e`, added earlier
   this session) — it's in the code but was never deployed; the live container still doesn't have
   it. Run `make deploy STACK=media TARGET=home DOMAIN=brianphiri.digital SUBDOMAIN=media` next
   time you touch the media stack (bundling it with the trickplay-setting fix above would be a
   natural pairing, since both concern the same disk-usage issue).
10. **Uindex indexer is permanently blocked by Cloudflare** (`"Unable to access uindex.org, blocked
    by CloudFlare Protection"`) — not a homelab config issue, just how that tracker behaves now.
    Either accept it as unusable or look into a FlareSolverr-style proxy in front of it if it
    matters to you.
11. **Prowlarr's "Mylar" application connection is still flagged unavailable** (6+ hours of
    failures, same DNS-outage root cause as the indexers) — wasn't re-tested since it's a separate
    app from Sonarr/Radarr; worth clicking Test on it in Prowlarr's UI if comics/Mylar matters.
12. **Version bumps flagged for manual review** (found while checking every pinned image against
    its registry, `4265b03`) — none applied, each has a real breaking-change risk:
    - n8n: stable **2.x** now exists (currently pinned to 1.123.76) — own migration path.
    - n8n's postgres: `17-alpine` → `18-alpine` available — needs dump/restore, not a tag swap.
    - portainer (currently disabled): `2.33.0` → `2.45.0 LTS` — Portainer's docs require a backup
      before upgrading.
    - traefik: `v3.6.13` → `v3.7.12` — documented behavior changes (h2c header forwarding, wildcard
      `Host()` matching, header-strategy rename) — check against `vars/proxy/traefik/traefik-routes.yml` first.
    - mealie: `v3.24.0` → `v3.25.0` — real breaking change, `GET /api/auth/refresh` became `POST`.
    - immich (currently disabled): `v2.3.1` → `v3.1.0` — major version jump.
    - uptime_kuma: pinned major `"1"` → major `"2"` now exists.

For the full story of what happened during Batch 2 (a chain of unrelated pre-existing bugs it
uncovered — disk-filling Jellyfin cache, broken server DNS, a clock 2.5 months off, the
`group_vars` bug, a silently-failing rclone install), see "Unplanned discoveries" under Batch 2
below. For what happened investigating Seerr/Sonarr/Radarr/qBittorrent not grabbing downloads, see
"Additional fixes made 2026-09-02" further down.

---

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

## Batch 1 — Git hygiene (do this first, before any further code edits) ✅ done

Split into 6 commits on `chore/batch-1-2-fixes`: bug fixes, Loki/Promtail stack, qui/profilarr,
misc tweaks, Batch 0 simplification, and the review reports. Working tree is clean.


Every remaining code batch below touches files that are *already* mid-diff from your in-progress
Loki/Promtail/qui/profilarr work. Splitting that into logical commits now, before piling more
changes on top, keeps history readable and makes every batch after this one a clean, reviewable
diff of its own.

| # | Task | Difficulty | Breaking? |
|---|---|---|---|
| 1.1 | Split the current working-tree diff into commits per `reports/diff-review.md`'s suggestion: (1) service-membership-check + networking bug fixes, (2) Loki/Promtail logging stack, (3) qui/profilarr services, (4) misc unrelated tweaks (IP change, Makefile locale fix, pairdrop toggle) | Trivial (just `git add -p` / staged commits, no code changes) | None |
| 1.2 | Commit the already-completed Batch 0 simplification work separately from the above | Trivial | None |

---

## Batch 2 — Do now: trivial, non-breaking, zero operator decisions ✅ done

Everything here is either a manual one-off cleanup, or a code change with no behavioral downside
for how you currently use the system. All committed on `chore/batch-1-2-fixes`.

| # | Task | Where | Status |
|---|---|---|---|
| 2.1 | Fix local SSH key permissions | Control machine | ⏳ **Still needs you** — blocked on interactive sudo; run `! sudo chown brian:brian ~/.ssh/id_ed25519* && chmod 600 ~/.ssh/id_ed25519*` yourself |
| 2.2 | Free disk space on the server (`docker rmi` the 5 leftover disabled-service images) | Server (SSH) | ✅ Done — reclaimed 5.4GB |
| 2.3 | Clean up stray `docker-compose.yml.*~` backup files | Server (SSH) | ✅ Done |
| 2.4 | Deploy the backup system | `roles/backup/`, Makefile | ✅ Done — see "Unplanned discoveries" below for what it took |
| 2.5 | Delete dead `calico.yml.j2` + `etcd.yml.j2` | Code | ✅ Done (`7c2aa3b`) — confirmed with you first, deleted |
| 2.6 | Add `no_log: true` to secret-templating tasks | Code | ✅ Done (`669819a`) |
| 2.7 | Replace `changeme` fallbacks with `mandatory()` | Code | ✅ Done (`8236030`) |
| 2.8 | Fix Prometheus's `ports:` guard + localhost bind | Code | ✅ Done (`73a78c2`) |
| 2.9 | Localhost-bind cAdvisor/node_exporter | Code | ✅ Done (`73a78c2`, same commit) |
| 2.10 | Traefik `debug` default → off | Code | ✅ Done (`8e16b40`) — `vars/proxy/base.yml` explicitly set `debug: true`, so both the vars value and the template default were flipped |

### Unplanned discoveries fixed along the way

Deploying the backup system (2.4) uncovered a chain of pre-existing, unrelated problems — each
confirmed with you before acting:

- **Root disk kept refilling after cleanup**: `jellyfin`'s container writable layer had grown to
  9.37GB because it had no volume mount for `/tmp` (where its trickplay thumbnail cache lives) —
  fixed with a real volume mount (`df4892e`), existing cache cleared manually on the server.
- **Server-wide DNS was completely broken**: `/etc/resolv.conf` pointed at systemd-resolved's stub,
  but that service was inactive (disabled to free port 53 for AdGuard) — fixed by pointing it at
  AdGuard (127.0.0.1) directly, which then revealed AdGuard's own upstream resolvers are broken
  (its own admin config, out of scope here — **you should log into AdGuard and fix its upstream
  DNS servers**). Currently falls back to `1.1.1.1` so the host itself has working DNS in the
  meantime.
- **Server clock was ~2.5 months behind**: chrony had zero reachable time sources (likely a
  downstream effect of the DNS breakage). Restarted chrony + forced a step correction once DNS was
  fixed — clock is now correct and synchronized.
- **`inventory/group_vars/vault.yml` was never actually loaded by any playbook** — wrong filename
  for Ansible's auto-loading convention, and no playbook had an explicit `vars_files` entry for it.
  Restructured into the standard `group_vars/all/` directory pattern (`6ec9fe3`). **Follow-up
  needed**: this means `vault_netbird_setup_key` now resolves to its real value for the first time
  — verify NetBird still connects correctly after the next utility-stack deploy.
- **rclone install was curl-piped onto the host and silently failed** (masked by the DNS issue,
  then again by the clock issue via a Docker registry TLS error) — switched to running rclone via
  its official Docker image instead of a host-installed binary, matching how everything else in
  this repo runs (`roles/backup/defaults/main.yml`, plus `makefiles/backup.mk`'s `s3-test`/
  `s3-list`/`s3-size` which had the same raw-binary problem, `70ac1d7`).
- **Backblaze B2 credentials didn't exist anywhere** (`backup_s3_access_key`/etc. referenced vault
  vars that were never defined) — added as placeholders (`21acd4c`). **Follow-up needed**: replace
  `REPLACE_ME_B2_KEY_ID` / `REPLACE_ME_B2_APPLICATION_KEY` / the endpoint in
  `inventory/group_vars/all/vault.yml` with your real Backblaze B2 application key before S3 sync
  will actually work (confirmed via `make s3-test` — pipeline works end-to-end, just needs real
  creds).
- **Added vault tooling that wasn't asked for in the original plan but came up naturally**:
  `make vault-status/vault-encrypt/vault-decrypt/vault-edit` plus a pre-commit git hook
  (`make install-hooks`) that auto-encrypts any vault.yml accidentally staged in plaintext
  (`7c9dc86`).

**Note on 2.8/2.9**: nikto/nmap confirmed these were *currently* reachable directly on your LAN
with no auth before this fix. If you relied on hitting them by raw IP:port from your phone or
another device, that access is now gone (Grafana remains the intended UI for metrics).

### Additional fixes made 2026-08-31 (post-session follow-up)

- **Root cause found for "prowlarr redirects to the AdGuard page"**: AdGuard Home runs with
  `network_mode: host` and was bound directly to host port 80 (its own internal config, not
  managed by Ansible), while Traefik's `http` entrypoint had been mapped to port 82 to avoid the
  conflict. Effect: **every** Traefik-fronted domain's plain `http://` request — not just
  prowlarr — silently hit AdGuard's login page instead of getting redirected to HTTPS by Traefik.
  Fixed by editing `AdGuardHome.yaml`'s `http.address` to `0.0.0.0:81` on the live server (backed
  up first, verified AdGuard's UI still worked before touching anything else), then flipping
  `vars/proxy/base.yml`'s `http: 82` → `80` in code and redeploying (`0ba6394`). Verified
  end-to-end: `http://` now correctly 301s to `https://` for Traefik-fronted domains, AdGuard
  reachable on its new port 81, HTTPS unaffected throughout.
- **Incident during that fix's verification**: a `make deploy-proxy TARGET=home` run (mine, to test
  the port change) without `DOMAIN=`/`SUBDOMAIN=` regenerated Traefik's dashboard router using the
  placeholder `example.com` domain, breaking dashboard access (`401`/no valid cert, since Let's
  Encrypt policy-blocks `.example.com`). Fixed by redeploying with the correct
  `DOMAIN=brianphiri.digital SUBDOMAIN=media` — verified the dashboard is now reachable with a
  valid, trusted cert (reused the existing `*.media.brianphiri.digital` wildcard, no new Let's
  Encrypt request needed). See Batch 3.5 (new) for the follow-up fix to stop this from recurring.
- **🔴 Found while investigating the above: your Cloudflare API token expired on 2026-07-31**,
  confirmed directly against Cloudflare's own token-verify API (independent of anything touched
  this session). The current wildcard cert is valid until Sep 16, 2026, but auto-renewal is
  already being attempted and failing. **This needs a new Cloudflare token before Sep 16** — see
  the top of this file for the exact steps. Nothing was changed in the vault since I don't have a
  replacement token; this is purely a finding.
- **Jellyfin logins were intermittently failing** with a `SaveChangesAsync` exception on every
  login attempt (a DB write Jellyfin does to record last-login-time). Investigated end-to-end: full
  Ansible code review turned up nothing (no task touches jellyfin's config directory after initial
  creation; the backup role only reads the DB non-destructively into a separate location and hadn't
  even run yet; ClamAV only scans, doesn't modify). File/WAL/SHM ownership on the live DB was
  correct throughout. Live logs caught a background ffmpeg trickplay-generation job running at the
  exact moment a login failed, pointing to transient SQLite lock contention rather than a
  permissions or code bug. **Fixed by `docker restart jellyfin`** — confirmed via a live login
  immediately after, which succeeded cleanly. Also found, unrelated: Jellyfin's trickplay setting
  is misconfigured to save thumbnails next to media files (mounted read-only by design here),
  throwing a separate, real `Read-only file system` error on every attempt — see item 8 above.

### Additional fixes made 2026-09-02

- **Added Mealie** (SQLite install, `867e4c9`) to the utility stack — Traefik-only, no direct host
  port, deployed and verified live (`https://mealie.media.brianphiri.digital` returns 200 through
  a healthy container).
- **Bumped n8n** `1.120.3` → `1.123.76` (`4265b03`) — routine same-major patch. See item 12 above
  for the version bumps that were flagged instead of applied.
- **Removed orphaned `crowdsec`/`wireshark` version entries** (`3a69e00`) from
  `vars/stacks/utility/base.yml` — dead config, no service entry or template referenced either key
  anywhere in the repo. `crowdsec`'s value was also a typo (`"latjst"`), moot now that the line's
  gone.
- **Root-caused and fixed "Seerr approves requests but Sonarr/Radarr never grab anything"** — a
  multi-layered investigation:
  1. Seerr → Sonarr/Radarr request submission was never actually broken — confirmed requests were
     being sent and accepted correctly throughout.
  2. The real break: Sonarr/Radarr's release searches consistently found **"0 active indexers"**.
     Traced to two compounding causes: (a) two indexers (`TorrentGalaxyClone`, `Demonoid Clone`)
     had **no indexer definition at all** left in Prowlarr's current catalog (626 entries checked,
     no match for either) — deleted via Prowlarr's API, which correctly propagated the removal to
     both Sonarr and Radarr; (b) the morning's DNS outage had pushed nearly every remaining indexer
     into an **escalating failure-backoff** inside Prowlarr/Sonarr/Radarr's own health tracking,
     and those backoffs **outlived the outage itself** — so even healthy indexers kept reading as
     inactive long after DNS was fixed.
  3. Fixed via the same non-destructive "Test" action a user would click in the UI, run against the
     three still-flagged indexers (Prowlarr's `/api/v1/indexer/test`, Sonarr/Radarr's
     `/api/v3/indexer/test`) — cleared the stale backoffs for `Torrent Downloads` and
     `Internet Archive`. `Uindex` genuinely failed its test (Cloudflare-blocked at the source, see
     item 10 above) and was correctly left alone.
  4. **Verified end-to-end**: a live Ted Lasso search went from 0 to 7/8 active indexers in Sonarr,
     ran a real search, and grabbed 3 releases that were confirmed sent to qBittorrent
     successfully. Radarr showed 6/7 active similarly.
  5. **Found and cleaned up incidentally**: Sonarr's download queue had 146 stale entries all
     showing `"qBittorrent is reporting missing files"` — turned out to collapse to just 4 actual
     torrents (the complete Hey Arnold! series, seasons 1/3/4/5, all added the same day in May and
     genuinely deleted from disk since, confirmed via direct filesystem check). Bulk-removed all
     146 queue entries (`DELETE /api/v3/queue/bulk`, `removeFromClient=true`) and triggered a fresh
     series search — search completed cleanly but found no current release for Hey Arnold on any
     active indexer (a legitimate "not currently available" result, not a further bug; it'll pick
     up automatically via RSS if a release ever appears, since the series is still monitored).
  - No Ansible code changes were needed for any of this — it was entirely live Prowlarr/Sonarr/
    Radarr application state, unrelated to the Ansible-managed deployment itself.

---

## Batch 3 — Do soon: small/moderate effort, changes an access path (tell yourself before doing)

Why this order: these are safe and correct, but each one changes *how you reach something* —
worth doing deliberately, not on autopilot, since you're both the implementer and the one who has
to remember the new way in afterward.

| # | Task | Difficulty | Breaking? |
|---|---|---|---|
| 3.1 | ~~qui + profilarr: add Traefik basicauth middleware~~ — **✅ not needed, confirmed 2026-08-30**: both actually have their own built-in login pages (the earlier scan findings mistook "serves a page with no redirect" for "no auth," but the app itself gates access). Still true that both are double-published (Traefik + direct host port `7476`/`6868`) — dropping the direct host-port publish is now a lower-priority hygiene item, not a security one, since the app-level login covers the LAN exposure either way. | ~~Moderate~~ N/A | ~~Breaking~~ N/A |
| 3.2 | **Restart Profilarr** (`docker restart profilarr` on the server) — it's been unresponsive since the nikto scan wedged it; you said "leave it, check later" | Trivial | None (recovers the hung process) |
| 3.3 | Investigate Profilarr's fragility long-term — check if `santiagosayshey/profilarr`'s gunicorn setup supports `--workers`/`--timeout` tuning, since a single ordinary `HEAD`/`OPTIONS`/404 request was enough to hang it | Small-moderate (may require an upstream image change or entrypoint override, not just an Ansible edit) | None if done as an addition; risk is only in getting the gunicorn flags wrong |
| 3.4 | Disable SSH `PasswordAuthentication` — no role currently manages `sshd_config`, so this needs a small new task (e.g. in `roles/pre-checks/` or a new minimal role) setting `PasswordAuthentication no` and reloading `sshd` | Small | **Breaking in the strict sense** (removes an enabled auth method) but **zero practical impact** — your key-based login is already confirmed working and is the only method you actually use |
| 3.5 | **New, added 2026-08-31**: Hardcode `DOMAIN=brianphiri.digital SUBDOMAIN=media` as defaults in `makefiles/proxy.mk` (or `vars/proxy/base.yml`'s `domain`/`stack_domain` computation) instead of relying on every `make deploy-proxy` call to pass them correctly. Root-caused a real incident this session: a proxy redeploy without those flags silently regenerated the dashboard's router for the placeholder `example.com` domain, breaking dashboard access until manually corrected. | Small | None if done right — just changes what happens when the flags are *omitted*, not when they're passed explicitly |

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
- **Finding #19** (`curl \| bash` rclone install) — ended up fixed anyway, not left as-is: it was
  silently failing (masked by the DNS/clock bugs discovered in Batch 2), so it was replaced with
  running rclone via its official Docker image instead of a host-installed binary (`10a1cd6`).
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
