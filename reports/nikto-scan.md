# Nikto Web Scan — Home Server (192.168.100.26)

_Generated: 2026-08-30 — run locally via `docker run alpine/nikto` against each exposed HTTP(S)
port found by the earlier nmap scan (`reports/external-recon.md`). Each scan capped at 45s
(`-maxtime 45s`) to keep this a "basic tests" pass rather than an exhaustive one._

## ⚠️ Incident during this scan: Profilarr (port 6868) appears to have hung

The nikto scan against port 6868 never completed — it hung before even printing its target
banner, unlike every other port which responded within seconds. Manual follow-up confirmed the
service is no longer responding to **any** request, including a plain `GET /` that had worked
fine minutes earlier:

- `HEAD /` — timed out, 0 bytes, 6s
- `OPTIONS /` — timed out, 0 bytes, 6s
- `GET /nonexistent-path` — timed out, 0 bytes, 6s
- `GET /` (recovery check, after the above) — **also** timed out, 0 bytes, 6s

**Likely cause**: Profilarr's `santiagosayshey/profilarr` image runs on `gunicorn`, which showed
no `Server:` banner and returned instantly to a bare `GET /` before this scan but not after. This
looks like a single-worker (or otherwise low-concurrency) WSGI server that got wedged handling an
unusual request — `HEAD`/`OPTIONS`/a 404 path are all normal, unremarkable HTTP traffic, not an
exploit or flood. That a handful of ordinary requests from a vulnerability scanner can apparently
take the whole service down is itself the finding: **combined with having zero authentication and
being directly published to the LAN (`0.0.0.0:6868`, confirmed in `reports/internal-server-audit.md`),
this service can be trivially knocked offline by anything that probes it — a scanner, a bot, or
even an accidental request from another tool on your network.**

Per your instruction, **the container was not restarted** — you said you'd check on it later. If
it's still unresponsive when you look, `docker restart profilarr` on the server should recover it;
no data loss is expected since gunicorn hanging doesn't imply corruption, just an unresponsive
process.

**Recommendation**: put Profilarr behind Traefik's existing basicauth pattern (see
`reports/security-remediation-plan.md`) and drop its direct host-port publish — this closes both
the "no auth" and "trivially wedgeable, and reachable by anyone on the LAN" problems at once. It
may also be worth checking upstream whether Profilarr's Docker image supports a `--workers`/
`--timeout` gunicorn setting, since the underlying fragility is separate from the auth gap.

---

## Results by port

| Port | Service | Nikto findings |
|---|---|---|
| 80 | AdGuard Home | Missing `X-Frame-Options`, `X-XSS-Protection`, `X-Content-Type-Options` headers. Confirms admin login page at `/login.html` (already known — setup completed, login required). |
| 6868 | Profilarr | **Scan did not complete — see incident above.** |
| 7476 | qui | Missing the same three security headers. No other issues found in the 45s window. |
| 8080 | qBittorrent WebUI | Scan hit the 45s time cap after 1 item; noted `cross-origin-opener-policy` header present (this is actually a *good* modern security header nikto's older signature set flags as merely "uncommon" — combined with the CSP/`X-Frame-Options`/`X-Content-Type-Options`/`X-XSS-Protection` headers seen in the earlier curl pass, qBittorrent's WebUI is the best-hardened HTTP response header set of anything scanned here). |
| 8081 | cAdvisor | Missing the same three security headers; confirms unauthenticated redirect to `/containers/` (already flagged as High in `reports/security-audit.md`). |
| 8096 | Jellyfin (Kestrel) | Missing the same three security headers; redirects to `web/`. Nikto's `/web/: This might be interesting` note is a generic signature match on any `/web/` path, not a specific vulnerability — Jellyfin's own client lives there by design. |
| 9090 | Prometheus | Missing the same three security headers; confirms unauthenticated redirect to `/query` (already flagged as High). |
| 443 | Traefik (TLS) | Missing `Strict-Transport-Security` (HSTS) and `Expect-CT` headers. Hostname/cert mismatch noted (`192.168.100.26` vs. `TRAEFIK DEFAULT CERT`) — expected and not a real issue, since Traefik's real certs are only served for the correct `Host`/SNI of an actual routed domain, not a raw IP. Scan hit the 45s time cap. |

## Scope gap worth knowing about: Traefik-fronted-only services weren't reached

Several containers (`grafana`, `gotify`, `loki`, `promtail`, `mylar`, `portracker`, `prowlarr`,
`kavita`, `radarr`, `seerr`, `sonarr`, `uptime_kuma`, per `reports/internal-server-audit.md`'s
container inventory) publish **no direct host port at all** — they're reachable only through
Traefik via their actual hostname (e.g. `grafana.media.brianphiri.digital`), using SNI/Host-header
routing. Scanning the bare IP on 443, as this pass did, only ever reaches Traefik's default
fallback certificate/vhost — none of those backend apps were actually exercised by this scan.

**If you want nikto (or further testing) to actually reach those**, I'd need either the real
hostnames (to pass via `-vhost`/a `Host:` header, resolving to `192.168.100.26`) or to test them
one at a time by name. Given several of those are Traefik-fronted with presumably no built-in auth
of their own (e.g. `portracker`, `gotify`), that's a reasonable next step if you want the same
level of scrutiny applied to the reverse-proxied surface, not just the directly-published one.

## What this run didn't do

- No deep/unbounded nikto run (`-maxtime` was capped at 45s per port to keep this a quick pass;
  several scans hit that cap before finishing their full plugin set — a longer run would go
  further, at the cost of more time and, per the incident above, some risk to fragile services).
- No authenticated scanning (nikto tested each service unauthenticated only, matching this repo's
  actual current exposure).
- No scanning of the Traefik-fronted-only services (see scope gap above).
</content>
