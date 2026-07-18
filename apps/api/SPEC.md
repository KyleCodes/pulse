# api — implementation spec

FastAPI, single `main.py`, vibe-code quality is fine. Acceptance = `docs/test-plan.md` steps 2–6.

## Runtime contract
- Env: `DATABASE_URL` (postgres), `PORT` (8000). Listen on `0.0.0.0:$PORT`.
- Log to stdout (uvicorn default is fine; JSON access logs unnecessary).
- Stateless: no in-process caches; every request hits Postgres.
- Deps: `fastapi`, `uvicorn`, `psycopg[binary]` (or psycopg2-binary). Use a small connection pool.

## Endpoints
| Route | Behavior |
|---|---|
| `POST /events` | Body `{site_id: str, page_url: str, lcp_ms: int, timestamp: datetime, session_id: str}` — all required except session_id (nullable ok). Pydantic-validate (422 on bad shape). `INSERT INTO events_queue (site_id, page_url, lcp_ms, session_id, ts) VALUES (...)`. Return **202** `{"queued": true}` |
| `GET /config/{site_id}` | `SELECT * FROM site_config WHERE site_id=$1` → `{site_id, sampling_rate, experiments}` (experiments = the jsonb array as-is). **404** if unknown |
| `GET /sites/{site_id}/pages` | `SELECT page_url, event_count, p75_lcp_ms, last_seen FROM page_aggregates WHERE site_id=$1 ORDER BY event_count DESC LIMIT 20` → JSON array |
| `GET /sites/{site_id}/trend` | `SELECT bucket_start AS bucket, count(*) AS count, percentile_cont(0.75) WITHIN GROUP (ORDER BY lcp_ms) AS p75_lcp_ms FROM lcp_samples WHERE site_id=$1 AND bucket_start > now() - interval '60 minutes' GROUP BY 1 ORDER BY 1` → JSON array |
| `GET /healthz` | `SELECT 1`; 200 `{"ok": true}`. Compose healthcheck calls this via python urllib — no curl in the image |

## Dockerfile
`python:3.12-slim`, install deps, copy `main.py`, `CMD uvicorn main:app --host 0.0.0.0 --port 8000`. No build stage needed.
