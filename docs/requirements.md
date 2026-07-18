# Requirements

Derived strictly from the assignment. Anything we chose *not* to build is in the [descope log](#descope-log).

## Functional

**Platform**
- `make up` brings up infra + all services + observability on a laptop. Only host deps: docker, make.
- A 4th service deploys in <15 min with zero platform changes ([documented](./adding-a-service.md)).
- Deploy without SSH: build versioned image → repoint tag → recreate one service. Rollback = repoint prior tag.
- Every service observable: centralized searchable logs + operator dashboard (queue depth, throughput, freshness).
- A failure can be induced and recovered on camera: kill worker under load → events buffer → restart → drain, no loss.
- Config via compose service-name DNS + runtime env vars. Nothing baked into images.

**Services** (as specified)
- **api** (FastAPI): `POST /events` validates `{site_id, page_url, lcp_ms, timestamp, session_id}` and enqueues. `GET /config/{site_id}` returns sampling rate + active experiments.
- **worker** (Go): consumes the queue; per `(site_id, page_url)` computes event count, p75 LCP, last-seen; persists to Postgres.
- **dashboard** (static HTML+JS): shows top pages by volume, p75 LCP trend, active experiments — via the api.
- *Implied:* the api needs read endpoints over the aggregates (the dashboard "calls the API"), and a trend needs time-bucketed samples (we bucket per minute).

## Non-functional

- No single-node app bottlenecks: api is stateless; workers scale to N via `SKIP LOCKED`. Postgres is the one accepted stateful node at this scale.
- No event loss: ack (= queue delete) commits in the same transaction as persistence. Crash ⇒ rollback ⇒ redelivery.
- Off-the-shelf platform components only; zero bespoke infra code.
- Artifact-based deploys; CI described in docs, not built.
- Verification = human-executable [test plan](./test-plan.md) with exact expected outputs.
- ~2.5h budget: platform + docs get the effort; app internals stay minimal.

## Entities

| Entity | Shape | Notes |
|---|---|---|
| Event | `site_id, page_url, lcp_ms, timestamp, session_id` | Transient — queue row, deleted on ack |
| SiteConfig | `site_id, sampling_rate, experiments` | Seeded, read-only |
| LcpSample | `(site_id, page_url, bucket_start, lcp_ms)` | Minute-bucketed; source of truth for p75 + trend |
| PageAggregate | `(site_id, page_url) → count, p75, last_seen` | Written by worker, read by api |

## API surface

| Endpoint | Purpose |
|---|---|
| `POST /events` → 202 | Validate + enqueue (422 on bad shape) |
| `GET /config/{site_id}` | Sampling rate + experiments (404 unknown) |
| `GET /sites/{site_id}/pages` | Top pages by count, with p75 + last-seen |
| `GET /sites/{site_id}/trend` | Per-minute p75, last 60 min |
| `GET /healthz` | Compose healthcheck |

The worker has **no HTTP surface** (health = process, visibility = logs + SQL panels). The dashboard is static files behind nginx with a same-origin `/api/` proxy.

## Descope log

| Not built | Why | Trigger to build |
|---|---|---|
| Prometheus + `/metrics` | Every operational question here is answerable in SQL against the one DB; Loki covers logs | Latency/error SLOs, or >1 host |
| Dead-letter queue | API validation front-stops bad events; worker errors roll back and retry | First poison-pill incident |
| Automated test suite | Replaced by a 5-min human test plan | CI existing |
| App-side p75 code | `percentile_cont` in SQL, inside the worker's tx | A store without percentiles |
| Idempotency ids | Single-DB transactional ack is already effectively exactly-once | External queue migration |
| Registry service, CI, config write path, auth | Not minimum viable | Team growth / multi-host |
