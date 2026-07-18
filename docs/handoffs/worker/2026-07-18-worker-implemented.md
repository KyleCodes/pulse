# Handoff — worker implemented & verified (2026-07-18)

Follow-up to [agent-worker.md](./agent-worker.md). The worker is **done**: stub replaced with the full queue consumer per `apps/worker/SPEC.md`. All acceptance criteria pass.

## What was built

- `apps/worker/main.go` (~160 lines, single file, pgx v5). Loop forever; each iteration is one transaction:
  1. Claim ≤500 rows: `SELECT … FROM events_queue ORDER BY id LIMIT 500 FOR UPDATE SKIP LOCKED`
  2. 0 rows → rollback, sleep 500ms
  3. `CopyFrom` into `lcp_samples` with `bucket_start` = ts truncated to the minute
  4. Per distinct (site_id, page_url), **sorted** (deadlock avoidance), the SPEC's upsert verbatim — `percentile_cont(0.75)` over trailing 60 min, run after step 3 so it sees this tx's inserts
  5. `DELETE FROM events_queue WHERE id = ANY($ids)` — the ack
  6. Commit; full batch → loop immediately (drain mode)
- Errors: rollback (deferred), log `level=error`, exponential backoff 500ms→10s cap, reconnect, never exit. Logs are key=value to stdout (visible in Loki/Grafana).
- No graceful-shutdown machinery: a hard kill mid-tx rolls back and the batch redelivers — safe by construction, so it was deliberately cut.
- `apps/worker/go.mod` + `go.sum`: added `github.com/jackc/pgx/v5` (module now `go 1.25`).
- `apps/worker/Dockerfile`: `golang:1.23-alpine` → `golang:1.25-alpine` (match tidied module), `COPY go.mod ./` → `COPY go.mod go.sum ./` (build broke without it).

Nothing outside `apps/worker/` was touched.

## How it was verified (all against the live compose stack, api already implemented)

| Check | Result |
|---|---|
| `go vet` + `go build` | clean |
| Host run (`run-dev.sh`) against compose postgres | connected, drained pre-queued events immediately |
| Test-plan steps 4–5: POST 4 events (LCP 100/200/300/400) via api → `GET /sites/<id>/pages` | `event_count=4`, **`p75_lcp_ms=325`** exact |
| Test-plan step 6: `GET /sites/<id>/trend` | current-minute bucket, `count=4`, `p75_lcp_ms=325` |
| Queue drained / samples persisted (psql) | `events_queue`=0, `lcp_samples`=4 for the test site |
| Image build + deploy (`nx run worker:build`, `compose up -d worker`) | real worker running in compose |
| Scale: `make scale N=3` | 3 replicas up, 0 error log lines, disjoint batches in logs |
| Failure drill (test-plan step 8): `make load`, stop all workers | 235 events buffered durably in queue |
| Restart workers, stop load | queue → 0; conservation invariant exact: `sum(page_aggregates.event_count) = count(lcp_samples) = 717` — no loss, no double-count across the outage |

Stack left at 1 worker replica, queue empty.

## Remaining project work (from the planning handoff)

Dashboard app → run full `docs/test-plan.md` (9 steps) → commit history + push (remove `initial_notes.md`, `assignment.pdf`) → Loom → README link → email.
