# Runbook: Worker outage (event backlog growing)

The failure demonstrated in the recording. Applies any time events are being ingested but aggregates stop updating.

## Symptoms

- Grafana **Pulse Ops → Queue depth** climbing instead of hovering near 0.
- **Oldest unprocessed event age** climbing linearly (seconds since the oldest queued event arrived).
- Customer dashboard shows stale `last_seen` / counts not moving while traffic is flowing.
- No data is being lost — events are accumulating durably in `events_queue`.

## Diagnose (2 minutes)

1. `docker compose ps` — is `worker` running? `Exit`/`Restarting` → it's down or crash-looping.
2. Grafana → Pulse Ops → **Logs** panel, filter service `worker` (or Explore: `{compose_service="worker"}`). Look for panics, connection errors to `postgres:5432`, or silence (no batch logs = not consuming).
3. If worker is up but depth still climbs: ingest rate exceeds drain rate → scale (below).

## Remediate

| Cause | Action |
|---|---|
| Worker stopped/crashed | `docker compose start worker` (or `docker compose up -d worker`) |
| Crash-looping on a bad deploy | `make rollback SERVICE=worker TAG=<last-good>` (`docker images pulse-worker` lists tags) |
| Healthy but can't keep up | `make scale N=4` — workers partition automatically via `SKIP LOCKED` |
| Postgres down (everything red) | `docker compose restart postgres`; healthchecks gate dependents back up |

## Verify recovery

1. **Queue depth** falls to ~0; **oldest age** drops to ~0.
2. Worker logs show batches processing again.
3. Customer dashboard counts/last-seen move again.
4. **No loss check:** every event that was queued during the outage is now counted — the worker's ack (queue delete) commits in the same transaction as the aggregate write, so a crash can never drop a claimed batch; it is redelivered.

## Why this failure is safe by design

The queue is a Postgres table. A dead consumer means events buffer durably; recovery is "start consuming again." There is no ack-before-persist window and no in-memory queue to lose. Worst case on crash is a re-processed batch that was rolled back — never a lost one.
