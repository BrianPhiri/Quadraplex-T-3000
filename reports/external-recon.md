# External Network Recon — Home Server (192.168.100.26)

_Generated: 2026-08-30 — LAN-based scan only, run from another machine on the same home network.
No WAN/internet vantage point was used (see "What this doesn't cover" below). No credential
guessing, brute-forcing, or exploitation was attempted — this is passive/light-touch
reconnaissance only: port scanning, service/version fingerprinting, and checking whether each
exposed service presents an auth wall._

## Answering the core question: "can you get in without a password or SSH key?"

**SSH itself: no.** The server only offers `publickey` and `password` authentication — no `none`
auth, no anonymous access. No login was attempted (that would require either a valid key or a
guessed password, and guessing passwords against a live SSH server risks lockouts/fail6ban bans
and wasn't part of this "basic tests" scope).

**Several other services: yes, right now, over the LAN.** Five services respond with full
functionality and zero authentication to anyone who can reach the host's IP — no exploit needed,
they're just running with no auth configured:

- **Prometheus** (`:9090`) — full metrics query UI/API, no login.
- **cAdvisor** (`:8081`) — full per-container resource/metrics UI, no login.
- **node_exporter** (`:9100`) — raw host metrics, no login.
- **Profilarr** (`:6868`) — serves its full app UI directly with no login redirect (unlike every other web UI on this host, which either shows a login page or redirects to one).
- **qui** (`:7476`) — same pattern as Profilarr: serves its app directly, no visible login gate.

These aren't exotic findings — they match (and for Profilarr/qui, extend) what the earlier static
code audit (`reports/security-audit.md` findings #4, #5) predicted from the Ansible templates.
This scan confirms those predictions against the actual running server, and surfaces two more
(Profilarr, qui) that only exist in the uncommitted, not-yet-deployed feature work — worth fixing
before that work ships if it hasn't already been deployed with this exposure.

## Full port/service inventory

| Port | Service | Version/Details | Auth present? |
|---|---|---|---|
| 22/tcp | SSH | OpenSSH 10.0p2 (Ubuntu 5ubuntu5.4) | Yes — publickey + password both accepted |
| 53/tcp | DNS | Unbound | N/A (resolver, not a login surface) |
| 80/tcp | HTTP | AdGuard Home admin UI | **Yes** — redirects to `/login.html` (setup already completed, good) |
| 82/tcp | HTTP | Traefik (Golang net/http) | Redirects to HTTPS — this is Traefik's http entrypoint working as designed |
| 443/tcp | HTTPS | Traefik | Traefik default self-signed cert on unmatched Host — expected behavior for the proxy entrypoint |
| 6868/tcp | HTTP | Profilarr (gunicorn) | **No** — serves full app directly |
| 6881/tcp | BitTorrent | qBittorrent peer port | N/A — this is qBittorrent's normal incoming-peer port, not a management interface |
| 7476/tcp | HTTP | qui | **No** — serves full app directly |
| 8080/tcp | HTTP | qBittorrent WebUI | Yes — presents login page |
| 8081/tcp | HTTP | cAdvisor | **No** — redirects straight to `/containers/` |
| 8096/tcp | HTTP | Jellyfin (Kestrel) | Redirects to its own setup/login flow |
| 9090/tcp | HTTP | Prometheus | **No** — redirects straight to `/query` |
| 9100/tcp | HTTP | node_exporter | **No** — serves raw metrics |

No open ports were found for: Portainer (8000/9000/9443), AdGuard's raw setup port (3000, since
it's already configured and only reachable via 80 now), the Docker daemon TCP port (2375), or any
database port (5432/3306/6379) — all consistent with the Ansible vars/config reviewed earlier
(Portainer isn't currently enabled in a tracked vars file; the Docker daemon TCP listener defaults
to disabled; databases are correctly kept off the host-published port list).

## SSH detail

- Offered auth methods: `publickey`, `password` — password auth is enabled at the `sshd` level
  even though the operator uses key-based login day to day. This means a weak/guessed/leaked
  account password would be enough to log in remotely; it's not a live compromise, but it's an
  unnecessary extra attack surface given a key is already the intended method.
- Key exchange, host key, cipher, and MAC algorithm lists are all modern (curve25519/ML-KEM/
  X25519 kex, ed25519/rsa-sha2 host keys, AES-GCM/ChaCha20 ciphers, ETM MACs) — no legacy/weak
  algorithms offered. OpenSSH 10.0p2 is current and not affected by known SSH RCEs like
  regreSSHion (CVE-2024-6387), which only affected older 8.5–9.8 releases.

## What this doesn't cover

- **No external/WAN vantage point.** This scan was run from another machine on the same home LAN,
  not from the internet. It tells you what's reachable to anyone already on your home network
  (including a compromised IoT device, a guest on your Wi-Fi, or malware on another machine) — it
  does **not** tell you what, if anything, your router forwards to this host from the internet.
  **Recommended follow-up:** log into your router's admin panel and check the port-forwarding /
  UPnP rules for anything pointing at `192.168.100.26`. If nothing is forwarded, everything above
  is LAN-only exposure (still worth fixing, but much lower risk than internet-facing). If Traefik's
  443/80 are forwarded (likely, since that's the point of a reverse proxy with Let's Encrypt), the
  services listed as unauthenticated above are only exposed if they're *also* forwarded
  individually — check for that specifically, since a misconfigured/legacy port-forward rule for a
  raw service port (rather than just 80/443 to Traefik) is a common way home-lab services end up
  accidentally internet-facing.
- **No UDP scan.** A UDP port scan requires raw-socket privileges (`nmap -sU` needs root) which
  wasn't available non-interactively in this environment. DNS almost certainly also listens on
  UDP/53 (standard for a resolver) — not a new finding, just unconfirmed by this scan.
- **No credential guessing.** Nothing was brute-forced or guessed (SSH password, qBittorrent
  WebUI login, AdGuard admin login, Grafana if present). If you want confidence in password
  strength specifically, that's a deliberate, separate decision to make (e.g. testing your own
  known password against your own account), not something to run unprompted.
- **No web app vulnerability scanning** (e.g. checking for known CVEs in the specific qBittorrent/
  Jellyfin/Profilarr/qui versions running). The internal audit (SSH-based) is better positioned to
  pull exact installed versions from `docker ps`/compose files and cross-reference against known
  CVEs.

## Recommendations (roughly in priority order)

1. **Bind Prometheus, cAdvisor, and node_exporter to `127.0.0.1:` on the host** (or firewall them
   off from other LAN hosts) — Prometheus only needs to reach them over the internal Docker
   network, not have them reachable from your phone or a random LAN device. This is Batch 1 in
   `reports/security-remediation-plan.md` findings #4/#5 — already scoped as safe/non-breaking.
2. **Check whether Profilarr and qui ship any authentication option** (many arr-ecosystem tools
   don't have built-in auth and expect you to put them behind a proxy with `forwardAuth`/basicauth,
   which this repo's Traefik role already has a working pattern for — see the `traefik-auth`
   middleware referenced in `reports/security-remediation-plan.md`). If they don't ship auth, put
   them fully behind Traefik with that basicauth middleware and stop publishing their container
   ports directly to the host.
3. **Disable SSH password authentication** (`PasswordAuthentication no` in `sshd_config`) since a
   key is already the intended login method — removes an entire class of remote-guessing risk for
   negligible convenience cost.
4. **Check your router's port-forwarding/UPnP rules** for `192.168.100.26` — this is the one thing
   that determines whether any of the above is "a device on your home Wi-Fi could see this" versus
   "the entire internet could see this."
5. **For deeper investigation than this pass covered:** an authenticated vulnerability scanner
   against the exposed web apps (e.g. Nikto or OpenVAS/Greenbone for broader web-app checks), and
   checking each running container's image tag against its upstream CVE feed, would both go
   further than this basic recon — worth doing as a next step if you want more assurance than a
   port/auth sweep gives.
</content>
