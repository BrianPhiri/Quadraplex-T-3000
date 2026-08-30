# Uncommitted Changes Review — Quadraplex-T-3000

_Generated: 2026-08-30_

## What the uncommitted work is

Two intertwined efforts sitting together in the working tree:

1. **A Loki/Promtail logging stack added to the `utility` stack**, wired into Grafana (new datasource provisioning) and Prometheus (new scrape job), plus supporting directories/configs. This is the bulk of the new/untracked files.
2. **Two new media-stack services** (`qui` — an autobrr qBittorrent WebUI, `profilarr` — a Trash-guides profile manager), added to `vars/stacks/media/base.yml` with matching compose templates.
3. **A grab-bag of small, unrelated infra fixes**: a homelab IP change in inventory, a locale env-var fix in the Makefile, a real bug fix in how `'service' in services` membership checks are done (fixes silent failures), a `networks:` block added to cadvisor/node_exporter templates (fixes them not being reachable by Prometheus over `traefik_net`), and a `mylar3` → `mylar` container rename to match its config path.

## File-by-file summary

**Modified (tracked):**
- `inventory/hosts.yml` — changes the `home` host's `ansible_host` IP from `192.168.100.188` to `192.168.100.26`.
- `makefiles/base-stack.mk` — prefixes the ansible-playbook invocation with `LC_ALL=C.UTF-8` (locale fix, unrelated to the logging feature).
- `roles/base-stack/tasks/configs.yml` — adds tasks to deploy Grafana's Prometheus/Loki datasource provisioning files and to create+deploy Loki/Promtail config directories and configs (all gated on `stack_name == 'utility-stack'`).
- `roles/base-stack/tasks/directories.yml` — creates `provisioning/datasources` and `provisioning/dashboards` Grafana subdirs, and switches the Grafana directory-creation guard from `services.grafana.enabled | default(false)` to `"'grafana' in services"` — a genuine bug fix, since in the base-stack role's context `services` is actually a flat list of enabled service names (passed down from `dynamic-stack/tasks/main.yml` as `enabled_services`), not a dict, so the old `services.grafana.enabled` attribute access always silently resolved to `false`.
- `roles/base-stack/templates/configs/prometheus.yml.j2` — same `'x' in services` fix applied throughout, renames the node_exporter job from `node` to `node_exporter`, and adds a new `loki` scrape job. **This is the template that's actually deployed** (referenced by `configs.yml`'s `src: configs/prometheus.yml.j2`).
- `roles/dynamic-stack/templates/configs/prometheus.yml.j2` — gets the same `'x' in services` and job-rename edits but **not** the new Loki scrape job. Grep confirms this file is never referenced by any task in the repo — it's dead/duplicate code, and now the two copies have drifted further apart.
- `roles/dynamic-stack/templates/services/cadvisor.yml.j2` / `node_exporter.yml.j2` — add a `networks:` block driven by `services.X.networks`. Real fix: both already declared `networks: [traefik_net]` in `vars/stacks/utility/base.yml`, but the compose templates never rendered it, so the containers were never actually attached to `traefik_net` — meaning Prometheus (which lives on `traefik_net`) could not resolve `cadvisor:8080` / `node_exporter:9100` by service name. This diff fixes that.
- `roles/dynamic-stack/templates/services/mylar.yml.j2` — renames service key from `mylar3` to `mylar` (container name and block key), aligning with the `mylar` key already used in vars and the `/mylar` config volume path.
- `vars/stacks/media/base.yml` — adds `profilarr` and `qui` version entries and full service definitions (port, version, traefik routing).
- `vars/stacks/utility/base.yml` — adds `loki`/`promtail` versions and service entries (both on `traefik_net`); also flips `pairdrop.enabled` from `true` to `false` (unrelated, looks like an unrelated toggle, not part of the logging work).

**Untracked (new):**
- `roles/base-stack/templates/configs/grafana/datasources/prometheus.yml.j2` — Grafana provisioning file wiring the Prometheus datasource (`http://prometheus:9090`, marked `isDefault: true`).
- `roles/base-stack/templates/configs/grafana/datasources/loki.yml.j2` — Grafana provisioning file wiring the Loki datasource (`http://loki:3100`).
- `roles/base-stack/templates/configs/loki.yml.j2` — Loki server config (filesystem storage, TSDB schema v13, single-node/inmemory ring — fine for a homelab single-node deploy).
- `roles/base-stack/templates/configs/promtail.yml.j2` — Promtail config scraping Docker container logs via `docker_sd_configs` + syslog/auth/kern logs, pushing to `http://loki:3100/loki/api/v1/push`.
- `roles/dynamic-stack/templates/services/loki.yml.j2` — Loki compose service definition (config + data volumes, optional port/networks).
- `roles/dynamic-stack/templates/services/promtail.yml.j2` — Promtail compose service definition; mounts `/var/log`, `/var/lib/docker/containers`, and `/run/docker.sock` read-only.
- `roles/dynamic-stack/templates/services/qui.yml.j2` — compose service for `qui`, with Traefik labels and optional `networks`/`dnss`.
- `roles/dynamic-stack/templates/services/profilarr.yml.j2` — compose service for `profilarr`, same shape as qui plus a `TZ` env var.

## Issues found

- **Dead-code drift (minor):** `roles/dynamic-stack/templates/configs/prometheus.yml.j2` is unused (nothing references it) but was hand-edited anyway, and now differs from the real, deployed `base-stack` copy (missing the new `loki` job). Worth deleting or at minimum not touching it further — it's confusing to have two near-identical Prometheus templates in different roles.
- **Grafana dashboards provisioning is a stub:** `directories.yml` now creates `provisioning/dashboards`, and there's a real `datasources` directory with two provisioning YAMLs, but there is no dashboards-provider YAML nor any dashboard JSON. Not broken, just incomplete — the directory exists but nothing populates it yet.
- **Unrelated change bundled in:** `vars/stacks/utility/base.yml` also disables `pairdrop` (`enabled: true` → `false`). This has nothing to do with logging or media services and looks like it either belongs in its own commit or was an accidental leftover from local testing — worth double-checking before committing.
- **`inventory/hosts.yml` IP change and the `LC_ALL` Makefile fix** are both completely unrelated to the logging/media work — they're standalone infra tweaks that happen to be sitting in the working tree at the same time.
- **qui/profilarr have no PUID/PGID:** Unlike most other services in this repo (mylar, jellyfin, etc.), `qui.yml.j2` sets no environment at all and `profilarr.yml.j2` only sets `TZ`. This may be correct for these specific images (autobrr-style Go binaries often don't use PUID/PGID), but it's inconsistent with the rest of the codebase's pattern and worth a deliberate check against each image's actual documented env vars rather than assuming.
- **Loki/Promtail config directories are created twice**, harmlessly: once generically by the pre-existing per-service loop in `directories.yml` (since `loki`/`promtail` are now enabled services), and again explicitly in `configs.yml`'s new tasks (`Create Loki config directory` / `Create Promtail config directory`). Not a bug (idempotent `file` module), just redundant — could be simplified by dropping the explicit directory tasks in `configs.yml` since `directories.yml` already covers it.
- The `'x' in services` fix and the cadvisor/node_exporter `networks:` fix are both real, worthwhile bug fixes but are logically distinct from "add Loki/Promtail" — they're infrastructure corrections that happen to have been needed to make the new Grafana/Loki wiring actually function (e.g., without the `in services` fix, the new Grafana Loki/Prometheus datasource-provisioning tasks would also have silently no-opped).

## Readiness assessment

Not a single clean logical change — recommend splitting into at least 3-4 commits:

1. **"Fix service-membership checks and inter-container networking in base/dynamic-stack"** — the `services.X.enabled` → `'X' in services` fix in `directories.yml`/`prometheus.yml.j2`, the cadvisor/node_exporter `networks:` block addition, and the `mylar3`→`mylar` rename. These are bug fixes independent of the logging feature (though the logging feature depends on the membership-check fix to work at all, so this commit should land first or be squashed as a prerequisite).
2. **"Add Loki/Promtail logging stack to utility stack"** — all the new loki/promtail templates, configs, Grafana datasource provisioning, the `configs.yml`/`directories.yml` deploy tasks for them, and the `vars/stacks/utility/base.yml` loki/promtail additions.
3. **"Add qui and profilarr services to media stack"** — the two new compose templates and the `vars/stacks/media/base.yml` additions.
4. **"Misc infra tweaks"** (or fold into separate tiny commits) — the `inventory/hosts.yml` IP change, the Makefile `LC_ALL` fix, and the `pairdrop.enabled: false` toggle in utility vars — none of these relate to logging/media and should not be silently absorbed into a big feature commit.

Also worth resolving before/alongside committing: delete or intentionally sync the dead `roles/dynamic-stack/templates/configs/prometheus.yml.j2`, and decide whether the `pairdrop` disable was intentional.
</content>
