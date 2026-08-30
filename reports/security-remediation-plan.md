# Security Remediation Plan — Quadraplex-T-3000

_Generated: 2026-08-30 — companion to `reports/security-audit.md`. Planning only; nothing in this
document has been applied. Numbering matches the audit (Critical #1, High #2-6, Medium #7-14,
Low #15-19, Informational #20-22)._

## Scope

This is a homelab: single operator, single host, LAN-first with Traefik as the only
internet-facing front door (Cloudflare DNS challenge). The plan below is written for that trust
model — no mTLS, no enterprise IAM, no suggestion to "add a WAF." Where a raw port is currently
bound to `0.0.0.0`, the pragmatic fix is almost always "bind to `127.0.0.1`" or "put it behind the
Traefik basic-auth middleware pattern that already exists for the Traefik dashboard itself"
(`roles/traefik/templates/docker-compose.yml.j2:34`, `traefik-auth.basicauth.users`) — not a new
auth stack. 22 items are covered below (20 findings get full treatment; #21/#22 are one-liners
per the audit itself being informational-only).

---

## Findings

### Finding #1 — `calico.yml.j2` (Critical: privileged + host-network + RW docker.sock)

- **Fix**: Delete `roles/dynamic-stack/templates/services/calico.yml.j2` and its sibling
  `etcd.yml.j2` (Finding #12), since they form an incomplete/dead Calico+etcd pairing that is not
  referenced by any `vars/stacks/*/base.yml` (confirmed: no `calico` or `etcd` key exists in
  `vars/stacks/media/base.yml`, `vars/stacks/utility/base.yml`, or `vars/stacks/dns/base.yml`).
  Alternative if the operator has plans for it: keep the file but rename it (e.g. `.disabled`
  suffix or move to a `templates/services/_unused/` dir excluded from the service-loop glob) so it
  can't be silently enabled by a future `services.calico: {}` entry without deliberate re-adding.
- **Breaking or not**: Non-breaking either way — the template is not wired into any vars file, so
  no currently-running deployment references it. Deleting it changes nothing at runtime.
- **Prerequisites**: None. Just confirm with the operator it isn't "parked" for a planned Calico
  rollout (see Batch 3).
- **Effort**: Trivial (file deletion) — but see needs-operator-decision note below.

### Finding #2 — `portracker.yml.j2` (SYS_PTRACE + pid:host + apparmor:unconfined)

- **Fix**: In `roles/dynamic-stack/templates/services/portracker.yml.j2`, remove
  `pid: "host"`, `cap_add: [SYS_PTRACE, SYS_ADMIN]`, and `security_opt: [apparmor:unconfined]`.
  Portracker's stated job (per its RO docker.sock mount) is reading container/port metadata via
  the Docker API — that doesn't require reading host process memory or ptrace. Test with just the
  RO docker.sock mount first; only re-add `SYS_PTRACE`/`pid: host` if the app genuinely fails
  without them (some "what's using this port" tools do shell out to host `ss`/`lsof` via
  `pid: host`, so verify against portracker's actual docs/GitHub issues before assuming it's
  purely gratuitous).
- **Breaking or not**: Potentially breaking for portracker's own functionality if it genuinely
  uses `pid: host` to inspect host-level socket/process info (some port-scanner tools do this to
  see non-Dockerized processes bound to ports). This is NOT a code judgment call — it depends on
  what portracker's upstream image actually needs. Removing `apparmor:unconfined` alone is very
  likely safe (AppArmor's default docker profile is permissive enough for API-only tools).
- **Prerequisites**: Redeploy portracker after the edit and manually verify it still lists ports
  end-to-end (including non-Docker host processes, if that's a feature it currently exposes)
  before considering this done.
- **Effort**: Small (single-file edit), but needs-operator-decision on the pid/cap_add removal —
  recommend operator test-drives the stripped-down version since only they can validate the app
  still works as expected.

### Finding #3 — `portainer.yml.j2` (0.0.0.0:8000/9000/port + RO docker.sock)

- **Fix**: In `roles/dynamic-stack/templates/services/portainer.yml.j2`, change the `ports:` block
  (currently hardcoded `"8000:8000"`, `"9000:9000"`, `"{{ services.portainer.port }}:9443"` with no
  bind IP) to prefix each with `127.0.0.1:`, e.g. `"127.0.0.1:9443:9443"`. Since
  `services.portainer.traefik.enabled` already renders a full Traefik router block
  (`Host()` rule, TLS, redirect-to-https) in the same file, Traefik is the intended access path;
  8000/9000 (Portainer's legacy HTTP/edge-agent ports) likely aren't needed at all if edge agents
  aren't in use — confirm before dropping vs. localhost-binding them.
- **Breaking or not**: Breaking for LAN-IP-direct access. Anyone currently hitting
  `http://<host-ip>:9443` or `:9000` directly (bypassing Traefik) loses that path; they'd need to
  switch to the Traefik-fronted hostname. Access via the Traefik hostname is unaffected.
- **Prerequisites**: Confirm `services.portainer.traefik.enabled: true` is actually set for the
  environment in question (it's conditional in the template) — if Traefik routing isn't enabled
  anywhere, localhost-binding would remove all access and Traefik needs enabling first.
- **Effort**: Small — one-line-per-port edit, but operator should confirm they use the Traefik URL
  (or want to start using it) before applying.

### Finding #4 — `cadvisor.yml.j2` / `node_exporter.yml.j2` (0.0.0.0 metrics, no auth)

- **Fix**: Add `127.0.0.1:` prefix to the `ports:` entries: `"127.0.0.1:{{ services.cadvisor.port }}:8080"`
  in `roles/dynamic-stack/templates/services/cadvisor.yml.j2` and
  `"127.0.0.1:{{ services.node_exporter.port }}:9100"` in
  `roles/dynamic-stack/templates/services/node_exporter.yml.j2`. Both already correctly wrap
  `ports:` in `{% if services.X.port is defined %}` guards, so this is purely adding the bind
  prefix inside the existing block, no structural change.
- **Breaking or not**: Non-breaking for Prometheus scraping (Prometheus reaches both via Docker
  service-name DNS over the internal bridge network — `cadvisor:8080` / `node_exporter:9100` in
  `roles/dynamic-stack/templates/configs/prometheus.yml.j2` — which works regardless of published
  host ports). Breaking only for an operator who currently browses
  `http://<host-ip>:8081/metrics` or `:9100/metrics` directly in a browser/curl from another LAN
  device — that access method goes away; they'd need SSH-tunnel or a Traefik route instead.
- **Prerequisites**: None required for Prometheus scraping to keep working. If direct
  LAN-dashboard access to raw metrics is wanted, add a Traefik router block to each template
  first (neither currently has one — `traefik.enabled` handling doesn't exist in these two
  templates unlike portracker/portainer/prometheus), ideally behind the same basicauth middleware
  pattern the Traefik dashboard uses, since raw cAdvisor/node_exporter output has no built-in auth.
- **Effort**: Trivial (two one-line edits) once the operator confirms they don't rely on
  browser-direct access.

### Finding #5 — `prometheus.yml.j2` (unconditional 0.0.0.0:9090 port; enable-lifecycle)

- **Fix**: In `roles/dynamic-stack/templates/services/prometheus.yml.j2` lines 19-20, wrap the
  `ports:` block in the same `{% if services.prometheus.port is defined %}` guard every sibling
  template uses, and add a `127.0.0.1:` bind prefix inside it:
  ```
  {% if services.prometheus.port is defined %}
    ports:
      - "127.0.0.1:{{ services.prometheus.port }}:9090"
  {% endif %}
  ```
  This also directly fixes Informational #20 (the inconsistency was accidental per the audit).
- **Breaking or not**: Same shape as Finding #4 — non-breaking for internal use.
  `roles/backup/tasks/data-backup.yml:29` calls `http://localhost:9090/...` which is loopback and
  unaffected by an external bind change. `--web.enable-lifecycle`'s `/-/reload` becomes
  LAN-unreachable too, which is a net safety improvement (no legitimate reason for it to be
  externally reachable). Breaking only for browser-direct access to the Prometheus UI at
  `http://<host-ip>:9090`, same caveat as Finding #4.
- **Prerequisites**: None for the backup snapshot call (loopback-based, already works over
  `localhost`). If browser access to the Prometheus UI is wanted, same Traefik-route-first
  suggestion as Finding #4 (Grafana is presumably the intended UI for querying anyway, so this may
  not be needed at all).
- **Effort**: Trivial (add if-guard + bind prefix, mirrors an existing pattern elsewhere in the
  same file already, e.g. the `networks:`/`dns:` guards below it).

### Finding #6 — `adguard_home.yml.j2` (host network, exposed setup wizard on :3000)

- **Fix**: Confirmed active — `vars/stacks/dns/base.yml:35-39` has `adguard_home.enabled: true`
  with `http: 81`, `https: 8443`. The template
  (`roles/dynamic-stack/templates/services/adguard_home.yml.j2`) uses `network_mode: host` with a
  hardcoded `"3000:3000/tcp"` line — in host-network mode this `ports:` entry is cosmetic (the
  container binds directly to the host's port 3000 the moment the AdGuard process starts
  listening), so the "fix" is operational, not code: **complete AdGuard's first-run setup wizard
  immediately after first deploy** to close the exposure window, then optionally remove the now
  purely-decorative `"3000:3000/tcp"` line from the template (does not change behavior under
  `network_mode: host` either way — cosmetic cleanup only). A more durable code fix: switch off
  `network_mode: host` and instead publish only the explicit ports AdGuard needs (53/tcp+udp,
  81, 8443, 853) with normal bridge networking, which would make the `ports:` list actually
  authoritative and let a `127.0.0.1:` bind be added for the DNS-over-TLS/admin ports if desired.
- **Breaking or not**: Removing the dead `3000:3000` line is non-breaking. Switching off
  `network_mode: host` entirely is breaking / needs care — DNS services often use host networking
  specifically so clients can reach port 53 without extra Docker port-forwarding overhead/latency,
  and any existing client devices pointed at the host's IP for DNS need that IP to keep answering
  on 53 after the change (it should, under bridge+explicit `ports:`, but verify UDP DNS still
  works correctly, some setups see issues with conntrack/UDP under bridged Docker DNS at scale —
  unlikely to bite in a homelab but worth a real test after the change, not just an assumption).
- **Prerequisites**: Before any template change, operator must complete the AdGuard setup wizard
  now if it hasn't been done already (mitigates the actual finding immediately, independent of any
  code change).
- **Effort**: Operational step is trivial (visit the URL, set a password) and should happen today
  regardless of the code fix. The `network_mode: host` → bridge conversion is moderate (touches
  networking behavior, needs a real functional test of DNS resolution afterward).

### Finding #7 — `docker.service.override.j2` (dormant 0.0.0.0:2375 TCP daemon socket)

- **Fix**: No code change strictly required — `docker_daemon_port_enabled` already defaults to
  `false` in `roles/docker/defaults/main.yml:33`, and nothing in the tracked vars files overrides
  it to `true`. If the operator wants extra insurance against someone flipping it on later without
  realizing the risk, add a comment above the `{% if docker_daemon_port_enabled %}` block in
  `roles/docker/templates/docker.service.override.j2` warning that this exposes an unauthenticated
  root-equivalent daemon socket, and that TLS client-cert config (`--tlsverify`, `--tlscacert`,
  etc.) is not wired up anywhere in this role — so it should never be enabled without adding that
  first.
- **Breaking or not**: Non-breaking — comment-only, or leave as-is entirely.
- **Prerequisites**: None.
- **Effort**: Trivial (optional comment) or zero (accept as-is, already safe-by-default).

### Finding #8 — Missing `no_log: true` on secret-templating tasks

- **Fix**: Add `no_log: true` to these specific tasks:
  - `roles/backup/tasks/main.yml` — the "Configure rclone for S3" task (templates
    `rclone.conf.j2`, which embeds `backup_s3_access_key` / `backup_s3_secret_key` in plaintext,
    confirmed at `roles/backup/templates/rclone.conf.j2:6-7`).
  - `roles/traefik/tasks/configs.yml` — the "Generate environment file" task (templates
    `.env.j2`, which embeds `CF_DNS_API_TOKEN` and `TRAEFIK_DASHBOARD_CREDENTIALS`, confirmed at
    `roles/traefik/templates/.env.j2`).
  - `roles/base-stack/tasks/configs.yml` — the "Generate environment file" task (templates
    `.env.j2` for each stack; currently 0 bytes for dynamic-stack/base-stack but should still get
    `no_log` defensively since it's the designated place secrets would land as the stacks grow).
  - Any other `template:`/`copy:` task whose source embeds a `vault_*` variable — worth a repo-wide
    grep for `vault_` inside `roles/*/templates/*.j2` cross-referenced against the tasks that
    render them, to make sure none are missed (the three above are the ones directly named in the
    audit and confirmed by reading the templates).
- **Breaking or not**: Non-breaking. `no_log: true` only suppresses console/log output of the
  task's parameters; it doesn't change what gets written to disk or the resulting file's
  permissions/content.
- **Prerequisites**: None.
- **Effort**: Small — a handful of one-line additions across 2-3 files, plus a quick grep sweep to
  catch anything not explicitly named in the audit.

### Finding #9 — `"changeme"` silent-fallback passwords

- **Fix**: Replace `| default('changeme')` with `| mandatory('vault_x must be set — see vault.yml')`
  (or Ansible's `| mandatory` filter form) in:
  - `vars/stacks/media/base.yml:234` — `vault_immich_db_password`
  - `vars/stacks/utility/base.yml:182` — `vault_n8n_encryption_key`
  - `vars/stacks/utility/base.yml:187` — `vault_n8n_db_password`
  - `vars/stacks/utility/base.yml:189` — `vault_n8n_db_password_non_root`
  - `vars/stacks/utility/base.yml:200` — `vault_grist_secret`
  Note both `immich` and `n8n`/`grist` are currently `enabled: false` in their respective
  `base.yml` files, so none of these fallbacks are presently reachable in a live deploy — this is
  pure hardening against future enablement, not an active leak today.
- **Breaking or not**: Non-breaking for anyone who already has the corresponding `vault_*`
  variable set correctly (behavior is identical — the value used is the same either way). It
  *does* change behavior for the specific case of "vault var missing + service enabled": today
  that deploys silently with a known weak password; after the fix, the playbook run fails loudly
  with a clear error instead. That's the intended effect, not a regression, but the operator
  should know a previously-"working" (i.e., silently-changeme'd) deploy of one of these
  currently-disabled services would now require them to actually populate the vault before
  enabling it.
- **Prerequisites**: Before enabling immich/n8n/grist for the first time, populate the
  corresponding vault entries — otherwise the fixed code will correctly refuse to deploy.
- **Effort**: Trivial — five one-line filter swaps.

### Finding #10 — `netbird.yml.j2` (privileged + NET_ADMIN/SYS_ADMIN/SYS_RESOURCE + host network)

- **Fix**: In `roles/dynamic-stack/templates/services/netbird.yml.j2`, remove the top-level
  `privileged: true` line and keep `cap_add: [NET_ADMIN, SYS_ADMIN, SYS_RESOURCE]` (NetBird's own
  docs generally call for `NET_ADMIN` for WireGuard interface management and sometimes
  `SYS_RESOURCE` for connection-tracking table limits; `SYS_ADMIN` is more debatable but is
  commonly requested by NetBird for netfilter/routing manipulation in some modes). `privileged: true`
  grants every capability plus device access plus disables seccomp/AppArmor confinement — strictly
  broader than the three explicit caps already listed, so it's very likely redundant. Confirmed
  this service is active: `vars/stacks/utility/base.yml:93-97` has `netbird.enabled: true`.
- **Breaking or not**: **Verify against NetBird's actual requirements before removing** — this is
  exactly the kind of change the task description flags as needing care rather than blind
  trust in the audit. If NetBird's userspace WireGuard implementation or its integrated firewall
  manager (netbird manages iptables/nftables rules for peer routing) needs a capability not in the
  explicit list (e.g. `NET_RAW`, `NET_BROADCAST`, or genuine `SYS_ADMIN`-gated netns operations),
  removing `privileged: true` without adding that specific cap would break VPN connectivity or
  routing between peers.
- **Prerequisites**: Test in isolation — deploy netbird with `privileged: true` removed and verify
  (a) peer-to-peer connectivity still establishes, (b) routing rules (if `NB_SETUP_KEY` config uses
  route-advertising) still apply, before considering this closed. Check the currently-pinned
  version's release notes/docs for the minimum required capability set.
- **Effort**: Small edit, but needs-operator-decision / hands-on verification since a wrong guess
  here silently breaks VPN connectivity rather than failing loudly.

### Finding #11 — `traefik.yml.j2` (insecureSkipVerify + debug both default true)

- **Fix**: In `roles/traefik/templates/traefik.yml.j2`, change:
  - Line 3: `debug: {{ proxy_services.traefik.debug | default('true') }}` → default to `'false'`.
  - Line 18: `insecureSkipVerify: {{ proxy_services.traefik.insecure_skip_verify | default('true') }}`
    → default to `'false'`.
  Both remain overridable per-deployment via `proxy_services.traefik.debug` /
  `.insecure_skip_verify` in vars if a specific backend genuinely needs the old behavior.
- **Breaking or not**: Breaking / requires care for `insecureSkipVerify` specifically — if any
  currently-routed backend serves HTTPS to Traefik with a self-signed or otherwise
  non-CA-validated certificate (common for containers that ship their own snakeoil cert on their
  internal HTTPS port), Traefik will start rejecting that backend's cert once verification is
  turned on, causing 502s for that route. `debug: false` is much lower risk — dashboard/access
  behavior is unaffected, only verbosity of logs changes; essentially non-breaking.
- **Prerequisites**: Before flipping `insecureSkipVerify` to `false` globally, audit which
  Traefik-fronted services proxy to backends over HTTPS internally (vs. HTTP, which is unaffected)
  and check whether those backends use a real cert or a self-signed one. Portracker and Portainer
  templates in this repo, for example, both set
  `traefik.http.services.X.loadbalancer.server.scheme=https` in some cases — those are the ones
  to check first.
- **Effort**: Trivial edit for `debug`; moderate for `insecureSkipVerify` because it requires an
  audit pass across all Traefik-labeled services to avoid an outage, not just a filter change.

### Finding #12 — `etcd.yml.j2` (0.0.0.0 peer/client URLs, no auth)

- **Fix**: Covered together with Finding #1 — `etcd.yml.j2` is the other half of the
  dead calico/etcd pairing (confirmed no `etcd` key in any `vars/stacks/*/base.yml`). Same
  recommendation: delete alongside `calico.yml.j2`, or mark both clearly as unused/parked.
- **Breaking or not**: Non-breaking — not referenced by any vars file today.
- **Prerequisites**: Same operator-decision as Finding #1 (is Calico/etcd planned or abandoned?).
- **Effort**: Trivial (bundled with Finding #1's deletion).

### Finding #13 — `portracker.yml.j2` `TRUENAS_API_KEY` sourcing

- **Fix**: No code change needed today — grep confirms `services.portracker.truenas_api_key` is
  not set in any currently-tracked vars file, so the conditional
  (`{% if services.portracker.truenas_api_key is defined and services.portracker.truenas_api_key %}`)
  never fires. This is purely a "when you do configure it" reminder: whoever adds
  `truenas_api_key` to a vars file in the future should source it from `vault_*` (e.g.
  `services.portracker.truenas_api_key: "{{ vault_truenas_api_key }}"` in the relevant
  `vault.yml`), matching the pattern every other credential in this repo already follows.
- **Breaking or not**: Non-breaking (no current usage to break).
- **Prerequisites**: None now; applies only at the time TrueNAS integration is actually configured.
- **Effort**: Trivial / not-yet-applicable — informational reminder rather than an active fix.

### Finding #14 — cAdvisor/node_exporter/Prometheus running without `user:` directive

- **Fix**: None recommended, per the audit's own assessment — cAdvisor and node_exporter's
  upstream images are designed to run as root specifically because they need broad host
  filesystem/proc access to report container and host metrics; adding a `user:` directive would
  likely break their core function. Note: Prometheus itself actually **already has**
  `user: "{{ stack_config.user_id }}:{{ stack_config.group_id }}"` set at
  `roles/dynamic-stack/templates/services/prometheus.yml.j2:5` — the audit's finding is really
  about cAdvisor and node_exporter only, Prometheus is already compliant.
- **Breaking or not**: N/A — no change recommended.
- **Prerequisites**: N/A.
- **Effort**: N/A (accept as-is / documentation-only).

### Finding #15 — arr-stack/Jellyfin/qBittorrent without explicit `user:`

- **Fix**: None recommended — audit explicitly calls this an acceptable pattern (PUID/PGID env-var
  based privilege drop handled by the images' own entrypoints, e.g. linuxserver.io images).
- **Breaking or not**: N/A.
- **Prerequisites**: N/A.
- **Effort**: N/A (accept as-is).

### Finding #16 — Config directories at `0755` (world-readable at directory level)

- **Fix**: In `roles/base-stack/tasks/directories.yml` and `roles/traefik/tasks/directories.yml`,
  change `mode: '0755'` to `mode: '0750'` on the "Create service-specific config directories" /
  "Create service-specific data directories" tasks specifically (leave base/top-level dirs at
  `0755` if other tooling expects to traverse them, or tighten those too — the sensitive content
  lives in the per-service subdirs like `sonarr.db`, not the parent `base_path`).
- **Breaking or not**: Low risk of breaking, but worth care: if any service's own container
  process runs as a different UID/GID than `stack_user_id`/`stack_group_id` (e.g. an image with
  its own internal UID mapping that doesn't match the host-side owner), `0750` could deny it read
  access where `0755` happened to paper over a UID mismatch via world-read. Verify each service's
  container actually runs as the owning UID/GID before tightening, or test one stack at a time.
- **Prerequisites**: Confirm which services (if any) run with a UID/GID different from
  `stack_config.user_id`/`group_id` before applying repo-wide — a quick audit of each `*.yml.j2`
  template's `environment: PUID/PGID` values against `stack_config` should confirm they match.
- **Effort**: Small edit (two files, few lines each), but needs a quick verification pass first —
  low severity finding so this can reasonably be deprioritized.

### Finding #17 — `PGPASSWORD` via `environment:` dict (positive control)

- **Fix**: None needed — already correct pattern, explicitly called out by the audit as a
  positive control (avoids leaking the password via `ps aux`), confirmed at
  `roles/backup/tasks/postgres-backup.yml:27-28`.
- **Breaking or not**: N/A.
- **Prerequisites**: N/A.
- **Effort**: N/A (no action).

### Finding #18 — Command/shell interpolation from static hardcoded dict (theoretical only)

- **Fix**: None needed — `backup_services` is a static, repo-defined dict in
  `roles/backup/defaults/main.yml`, not attacker- or externally-influenced input. No actionable
  change; noted by the audit as theoretical/self-inflicted risk only.
- **Breaking or not**: N/A.
- **Prerequisites**: N/A.
- **Effort**: N/A (accept as-is).

### Finding #19 — `curl | bash` rclone install (no checksum verification)

- **Fix**: In `roles/backup/tasks/main.yml` ("Install rclone" task), optionally replace the
  `curl https://rclone.org/install.sh | bash` shell task with `ansible.builtin.apt`/`dnf`
  installing the distro-packaged rclone (simpler, loses curl-pipe-to-bash but rclone.org's own
  package may lag distro repos in version), or at minimum pin/verify the script via a checksum
  fetched from a second source before piping to bash. For a homelab, the pragmatic middle ground
  is: leave as-is (rclone.org's install script is widely trusted and this task only runs on
  initial setup, not routinely), or switch to the distro package manager if version currency isn't
  critical.
- **Breaking or not**: Non-breaking if switching to distro package — same `rclone` binary at
  `/usr/bin/rclone`, same `creates:` guard already in place
  (`args: creates: /usr/bin/rclone`). Slight risk the distro-packaged version is older than what
  `rclone.conf.j2`'s config options (e.g. `server_side_encryption`, `storage_class`) expect —
  check compatibility if switching.
- **Prerequisites**: If switching to a package-manager install, confirm the target distro's repo
  rclone version supports all options used in `rclone.conf.j2`.
- **Effort**: Small (single task rewrite), genuinely optional / low priority given homelab context.

### Finding #20 (Informational) — Prometheus `ports:` inconsistency

Directly fixed by Finding #5's edit (adding the matching `{% if %}` guard) — no separate action
needed.

### Finding #21 (Informational) — Empty `production.yml` override files

No fix needed — by design, no environment-specific override layer is currently in use. Not a
security issue.

### Finding #22 (Informational) — 0-byte `.env.j2` in dynamic-stack

Confirmed benign — `roles/dynamic-stack/templates/.env.j2` and
`roles/base-stack/templates/.env.j2` are placeholder stubs. If Finding #8's `no_log` addition is
applied to the tasks templating these files, it's already covered defensively for whenever they
gain real content.

---

## Recommended Order of Operations

### Batch 1 — Safe to apply immediately, no operator input needed

**Findings: #1 (calico deletion — pending Batch 3 confirmation it's truly unwanted, see caveat
below), #4, #5, #7 (comment-only), #8, #9, #12 (bundled with #1), #16 (after the quick UID/GID
verification pass), #19 (optional)**

Reason: these are template/task edits that either (a) touch templates not referenced by any live
vars file (calico/etcd), (b) add a bind-IP prefix that doesn't change how Prometheus scrapes
anything over the internal Docker network, (c) add `no_log`/`mandatory()` which only changes
behavior in the "something was already misconfigured" case, or (d) are pure hardening with no
functional dependency. None of these require the operator to make a judgment call about how they
currently use the system — *except* #1/#12 should really sit in Batch 3 pending a one-line
confirmation that Calico isn't planned; treat it as Batch 1 only once that's confirmed, otherwise
hold it.

### Batch 2 — Safe but the operator should be told what changed

**Findings: #3, #6 (the setup-wizard mitigation is urgent and should actually happen *first*,
before Batch 1, even though it's a Batch 2 item structurally), #11 (debug flag only)**

Reason: these change externally-visible access paths or startup log verbosity in ways that are
correct and intended, but the operator needs to know about them to avoid confusion: Portainer's
raw `:8000`/`:9000`/`:9443` LAN access goes away in favor of the Traefik hostname (#3); AdGuard's
setup wizard needs completing now regardless of any template change (#6); Traefik's debug log
volume changes (#11, debug-only half). None of these require a *decision*, just a heads-up.

### Batch 3 — Needs an explicit operator decision before touching

**Findings: #1/#12 (is Calico/etcd parked for future use or genuinely dead — delete vs. keep?),
#2 (does portracker actually need SYS_PTRACE/pid:host — requires testing the app with them
removed), #10 (does netbird actually need `privileged: true` on top of its explicit caps — verify
against NetBird's docs/behavior before removing), #11 (insecureSkipVerify half — requires an
audit of which Traefik-fronted backends serve self-signed HTTPS before flipping the default)**

Reason: each of these can silently break a currently-working feature (VPN connectivity, an
app's process-inspection feature, or HTTPS backend routing) if the audit's assumption about
"this looks unnecessary" turns out to be wrong for this specific app/version. These need the
operator (or a hands-on test cycle) to verify actual behavior before the code changes, not just
a read of the Ansible templates.
