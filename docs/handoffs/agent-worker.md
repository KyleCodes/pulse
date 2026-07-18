# Agent Handoff — worker (Go)

Implement the queue consumer in `apps/worker/main.go`, replacing the heartbeat stub. Single file plus go.mod (add pgx or lib/pq). This service is the stream-processing centerpiece — the transactional claim/persist/ack loop must be exactly as specified.

## Read first (in order)
1. `apps/worker/SPEC.md` — your contract: the 6-step transaction (claim `FOR UPDATE SKIP LOCKED` → insert samples → ordered upserts with `percentile_cont` → delete = ack → commit), batch 500, drain mode, backoff rules.
2. `ops/postgres/initdb/01-schema.sql` — `events_queue`, `lcp_samples`, `page_aggregates` shapes.
3. `docs/design.md` §Service shapes + §least-confident — why the tx semantics matter (crash = rollback = redelivery, no loss).
4. `docs/test-plan.md` **steps 5–6 and 8** — acceptance: exact p75=325, and the failure drill (stop/start worker must lose nothing).
5. `docker-compose.yml` `worker:` block — env (`DATABASE_URL` only), no ports (replicas must scale).

## Constraints
- ALL writes and the queue delete in ONE transaction. Never ack before persist.
- Upserts sorted by (site_id, page_url) — concurrent replicas deadlock otherwise.
- The `percentile_cont` subquery must run after this tx's sample inserts (it must see them).
- Structured key=value logs to stdout (they're shipped to Loki and shown in the demo).
- On DB errors: log, backoff, retry forever. Never exit permanently.
- Don't touch anything outside `apps/worker/`.

## Verify (definition of done)
```sh
make dev SERVICE=worker       # host run against compose postgres (stack is already up)
# POST events via the api (test-plan step 4), confirm step 5: event_count=4, p75_lcp_ms=325
# scale check: make build SERVICE=worker && docker compose up -d worker && make scale N=3  → no errors, disjoint batches
# failure drill: test-plan step 8 — stop worker under load, restart, queue drains, counts exact
```
