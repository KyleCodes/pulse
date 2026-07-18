# worker — implementation spec

Go, single `main.go`, `pgx` (or database/sql + lib/pq). No HTTP server at all. Acceptance = `docs/test-plan.md` steps 5–6 and 8.

## Runtime contract
- Env: `DATABASE_URL`. Log structured lines to stdout (level, msg, batch_size, duration — simple `log.Printf` with key=value is fine).
- Stateless: all state in Postgres. Multiple replicas must be safe concurrently (they are, by construction below).
- On DB connection failure: log and retry with backoff; never exit permanently (compose `restart: unless-stopped` is a backstop, not the strategy).

## The consume loop (the whole program)
Loop forever; each iteration is **one transaction**:

1. `SELECT id, site_id, page_url, lcp_ms, ts FROM events_queue ORDER BY id LIMIT 500 FOR UPDATE SKIP LOCKED`
2. If 0 rows: commit/rollback, sleep 500ms, continue.
3. `INSERT INTO lcp_samples (site_id, page_url, bucket_start, lcp_ms)` for every row, with `bucket_start = date_trunc('minute', ts)`. Batch insert (COPY or multi-VALUES).
4. For each distinct `(site_id, page_url)` in the batch, **sorted by key** (deadlock avoidance across replicas), upsert:
   ```sql
   INSERT INTO page_aggregates (site_id, page_url, event_count, p75_lcp_ms, last_seen)
   VALUES ($1, $2, $n, (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY lcp_ms)
                        FROM lcp_samples WHERE site_id=$1 AND page_url=$2
                          AND bucket_start > now() - interval '60 minutes'), $max_ts)
   ON CONFLICT (site_id, page_url) DO UPDATE SET
     event_count = page_aggregates.event_count + EXCLUDED.event_count,
     p75_lcp_ms  = EXCLUDED.p75_lcp_ms,
     last_seen   = GREATEST(page_aggregates.last_seen, EXCLUDED.last_seen);
   ```
   where `$n` / `$max_ts` are the batch's per-key count and max ts. (The percentile subquery sees this tx's own inserts — run it after step 3.)
5. `DELETE FROM events_queue WHERE id = ANY($claimed_ids)` — **the ack**.
6. `COMMIT`. If the batch was full (500), loop immediately (drain mode); else sleep 500ms.

Crash anywhere ⇒ rollback ⇒ events redelivered. Ack-with-persist in one tx ⇒ no loss, no partial application.

## Dockerfile
Multi-stage: `golang:1.23` build → `gcr.io/distroless/static` or `alpine` runtime. Static binary, `CMD ["/worker"]`.
