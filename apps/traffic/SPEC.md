# traffic — implementation spec

Continuous traffic generator: POSTs randomized events to the api forever so the dashboard and Grafana always have fresh data. Stupid simple — one POSIX shell script in a curl image. This is also the platform's 4th service: implement it by following `docs/adding-a-service.md` verbatim.

## Files (exactly two, plus the contract's project.json)
- `traffic.sh` — the whole app. Adapt the loop from `ops/loadgen/loadgen.sh` (the reference implementation):
  - POST to `${API_URL:-http://api:8000}/events` — compose DNS, overridable by env.
  - Sites `site-a` and `site-b`, ~5 fixed page URLs, `lcp_ms` randomized 600–3800 via awk `rand()` (busybox sh has no `$RANDOM`), `timestamp` = now UTC ISO8601, `session_id` = counter-based.
  - ~10–25 events/sec total: one burst across all site×page combos, then `sleep 0.2`.
  - curl failures are non-fatal (`-s -o /dev/null`, no `set -e` on the request) — the loop must survive api restarts and `demo-failure` drills, and recover on its own.
  - Every ~100 events, log one key=value line to stdout: `msg=posted total=N` (Loki picks it up automatically).
- `Dockerfile` — `FROM curlimages/curl:latest`, COPY `traffic.sh`, `CMD ["sh", "/traffic.sh"]` (or ENTRYPOINT equivalent).

## Runtime contract
- Env: `API_URL` only. No DATABASE_URL — this app speaks HTTP only.
- Compose block from `ops/templates/service.compose.yml`: **no ports**, `restart: unless-stopped`, `depends_on: api: condition: service_healthy`, image `pulse-traffic:${TRAFFIC_TAG:-dev}`, `build: apps/traffic`. Plus `TRAFFIC_TAG=dev` in `.env` and a `project.json` copied from a sibling app.
- Runs forever. Throttle = `docker compose stop traffic` / `start traffic`.

## Acceptance
1. `docker compose up -d --build traffic` → container stays up.
2. Two dashboard refreshes (:8080) ~10s apart → `event_count` visibly rising for site-a and site-b.
3. Grafana "Events processed per minute" climbs; queue depth stays near 0 (worker keeps up).
4. Loki has the summary logs: `{compose_service="traffic"}` in Grafana Explore.
5. `docker compose stop traffic` halts growth; `start` resumes.
