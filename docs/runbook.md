# Runbook — Worker outage (backlog growing)

The failure shown in the recording. Applies whenever events are ingesting but aggregates stop updating.

**Key fact: no data is being lost.** Events buffer durably in `events_queue`; the worker's ack commits in the same transaction as its writes, so a crash can only cause redelivery, never loss.

## Symptoms

- Grafana **Pulse Ops**: *Queue depth* climbing instead of ~0; *Oldest unprocessed event age* climbing linearly.
- Customer dashboard: counts / last-seen frozen while traffic flows.

## Diagnose (~2 min)

1. `docker compose ps` — worker `Exit`/`Restarting`? It's down or crash-looping.
2. Grafana logs panel, service `worker` (or Explore: `{compose_service="worker"}`) — panics, DB connection errors, or silence (no `batch_done` lines = not consuming).
3. Worker up but depth still climbing? Ingest exceeds drain rate → scale.

## Remediate

| Cause | Action |
|---|---|
| Stopped / crashed | `docker compose start worker` |
| Bad deploy crash-looping | `make rollback SERVICE=worker TAG=<last-good>` |
| Can't keep up | `make scale N=4` |
| Postgres down (everything red) | `docker compose restart postgres` — healthchecks gate dependents back up |

## Verify recovery

1. Queue depth → ~0; oldest age → ~0.
2. Worker logs show `batch_done` again.
3. Dashboard counts moving; every event queued during the outage is now counted (transactional ack guarantees it).
