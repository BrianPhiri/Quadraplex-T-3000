# dynamic-stack

Turns a stack's declarative service data (`vars/stacks/<name>/base.yml`) into a running Docker
Compose stack. This is the templating engine behind the "services-as-data" pattern used for the
media, utility, and dns stacks.

Given a `services` dict (per-service `enabled`/`image`/`version`/`networks`/... config) and a
`stack` config dict, it:

- Determines which services are enabled (`tasks/main.yml`).
- Renders each enabled service's `templates/services/<service>.yml.j2` fragment — a Docker Compose
  service definition — and merges them all into one `services:` map, building an accompanying
  `networks:` section (marking pre-existing networks external) (`tasks/compose.yml`).
- Writes the assembled result to `docker-compose.yml` in the stack's base path.
- Hands off to `roles/base-stack` (via `include_role`) for the actual directory setup, config
  rendering, `docker compose up`, systemd unit, and verification steps.

Adding a new service to a stack is normally just: add an entry under the stack's `base.yml`, and
add a small `templates/services/<service>.yml.j2` compose fragment here — no task changes needed.
