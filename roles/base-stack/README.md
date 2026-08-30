# base-stack

Generic Docker Compose lifecycle role, shared by every "stack" (media, utility, dns) deployed
through `roles/dynamic-stack`. Despite the name, it has no media-specific logic — it's the common
plumbing every stack needs, driven entirely by the `stack_name`, `stack_config`, and `services`
variables passed in by the caller.

Given those inputs, it:

- Resolves the Docker runtime user/group (`stack_config.preferred_user` if it exists on the host,
  otherwise falls back to `ansible_user`) and their UID/GID (`tasks/main.yml`).
- Creates the stack's base/config/data directories and per-service subdirectories, including
  extra `logs/` dirs for the Arr-family services and Grafana's provisioning subtree
  (`tasks/directories.yml`).
- Renders the stack's `.env` file plus any stack-specific config files — currently the
  utility-stack's Prometheus, Loki, Promtail configs and Grafana datasource provisioning
  (`tasks/configs.yml`).
- Pulls images (optional), runs `docker compose up -d`, and installs/enables a systemd unit for
  the stack (`tasks/docker-compose.yml`).
- Verifies the deployed containers are running, listening on their configured ports, correctly
  owned, and that the systemd service is enabled (`tasks/verify.yml`).

It is invoked via `include_role` from `roles/dynamic-stack`, which is responsible for actually
generating the stack's `docker-compose.yml` before handing off to this role.
