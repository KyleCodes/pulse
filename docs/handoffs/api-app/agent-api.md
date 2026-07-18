# Agent Handoff — api (FastAPI)

Implement the full api service in `apps/api/main.py`, replacing the stub. Single file. Speed over polish; the platform, not the app, is graded.

## Read first (in order)
1. `apps/api/SPEC.md` — your contract: exact routes, SQL, status codes, Dockerfile shape (Dockerfile already exists and is fine).
2. `ops/postgres/initdb/01-schema.sql` — the tables you insert into / read from, and the seeded sites.
3. `docs/test-plan.md` **steps 2–6** — your acceptance tests, with exact expected values (`p75_lcp_ms: 325` for the 4-event case).
4. `docker-compose.yml` `api:` block — env you receive (`DATABASE_URL`, `PORT`), healthcheck that calls `/healthz`.

## Constraints
- Stateless; no in-process caches. Every request hits Postgres (psycopg pool).
- Keep `/healthz` dependency-free and fast (compose healthcheck hits it every 5s via `python -c urllib`).
- Don't touch anything outside `apps/api/`. The platform is frozen.
- `POST /events` inserts into `events_queue` only — no processing; the worker owns everything downstream.

## Verify (definition of done)
```sh
make dev SERVICE=api          # host run against compose postgres (stack is already up)
# run docs/test-plan.md steps 2–4 (config, 422, ingest). Step 5–6 need the worker;
# until it's done, verify rows land: docker compose exec postgres psql -U pulse -d pulse -c 'select count(*) from events_queue'
make build SERVICE=api && docker compose up -d api   # containerized run, healthcheck goes healthy
```
