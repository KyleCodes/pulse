# Handoff — api implemented (2026-07-18)

The `agent-api.md` handoff in this dir is **done**. `apps/api/main.py` is the full service; the stub is gone.

## What was built (all inside `apps/api/`)

- **`main.py`** — single-file FastAPI per SPEC.md: `POST /events` (Pydantic validation → 422 on bad shape; one INSERT into `events_queue`, no processing), `GET /config/{site_id}` (404 unknown), `GET /sites/{site_id}/pages` and `GET /sites/{site_id}/trend` (SPEC SQL verbatim), `GET /healthz` (`SELECT 1`). Stateless: psycopg `ConnectionPool` (min 1 / max 5) opened via lifespan; no in-process caches.
- **`requirements.txt`** — `psycopg[binary]` → `psycopg[binary,pool]` (pool is a separate package).
- **Info logs on every endpoint** — `POST /events` dumps the validated payload as JSON; GETs log `site_id`. Format: `%(asctime)s %(levelname)s %(name)s %(message)s` to stdout (shipped to Loki).
- **`post-events.sh [count] [site] [page]`** — POSIX-sh test seeder; posts N events with `lcp_ms = i×100`, `API_HOST` overridable.
- Untouched: Dockerfile, project.json, run-dev.sh, everything outside `apps/api/`.

## How it was verified

1. **Host run** (`make dev SERVICE=api` against compose postgres): test-plan step 2 (`/config/site-a` → 2 experiments; `/config/nope` → 404), step 3 (missing `lcp_ms` → 422), step 4 (four 202s).
2. **Persistence**: `psql` against compose postgres showed the rows in `events_queue` with correct site/page/lcp/session/ts.
3. **Containerized run**: `make build SERVICE=api && docker compose up -d api` → compose healthcheck `healthy`; endpoints re-verified against the container. Gotcha: `make build` must run from the repo root.
4. **Steps 5–6** (after the worker agent landed mid-session): `test-1` returned the exact acceptance values `event_count=4`, `p75_lcp_ms=325`; `trend` returned one correct minute bucket (`count=5`, `p75=400` for a 5-event `test-2` run). Endpoint logs confirmed in `docker compose logs api`.

## Open items

- `/healthz` logs an info line every 5s (compose healthcheck) — steady Loki noise; consider silencing that one line before the Loom recording.
- Test seed data (`test-1`, `test-2`, `wtest-1`, loadgen rows) is in the DB; `make reset` before recording for a clean demo.
