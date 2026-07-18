# Requirements

Requirements analysis for the platform take-home. Derived strictly from the assignment doc; anything beyond it is listed in the [Descope Log](#descope-log).

## Functional requirements

### Platform
- **FR-P1** — `make up` brings up infra + all three services + observability on a laptop via docker compose. Single command, no other host dependencies beyond docker + make.
- **FR-P2** — A 4th service is deployable in under 15 minutes with zero platform changes. Documented with a copy-paste template ([adding-a-service.md](./adding-a-service.md)).
- **FR-P3** — Per-service deploy without SSH: build a versioned image → repoint its tag → recreate that one service. Rollback = repoint the prior tag.
- **FR-P4** — Every service is observable: centralized searchable logs + an operator dashboard (queue depth, throughput, freshness). The assignment mandates "observable"; the form is ours to define.
- **FR-P5** — A failure can be induced and recovered on camera: kill the worker under load → events buffer in the queue → restart → backlog drains with no data loss.
- **FR-P6** — Service discovery and config via compose service-name DNS + runtime env vars. Nothing baked into images.

### Services (as specified by the assignment)
- **FR-S1** — **api (FastAPI)**: `POST /events` accepts `{site_id, page_url, lcp_ms, timestamp, session_id}`, validates, pushes to the queue. `GET /config/{site_id}` returns active experiments + sampling rate from a seeded store.
- **FR-S2** — **worker (Go)**: consumes the queue; computes rolling aggregates per `(site_id, page_url)`: event count, p75 LCP, last-seen timestamp; persists to Postgres.
- **FR-S3** — **dashboard (static HTML+JS)**: calls the API to show top pages by event volume per site, a p75 LCP trend, and active experiments.
- **FR-S4** *(implied by FR-S3 — the dashboard "calls the API")* — the api exposes read endpoints over the aggregate store.
- **FR-S5** *(implied by "trend")* — a trend line requires time-bucketed samples; we bucket per minute.

## Non-functional requirements
- **NFR-1** — Laptop-only, docker compose, one command, no cloud dependencies.
- **NFR-2** — No single-node app bottlenecks: the api is stateless (N replicas fine); the worker scales to N consumers via `SKIP LOCKED` disjoint batches. Postgres is the accepted single stateful node at this scale (documented in design.md).
- **NFR-3** — At-least-once, crash-safe consumption: ack (= delete) happens in the same transaction as persistence. A worker crash rolls back the batch and events are redelivered. Queue + store in one DB makes this effectively exactly-once.
- **NFR-4** — Observability: structured stdout logs shipped to a central searchable sink; a provisioned-as-code Grafana dashboard; healthcheck-gated compose dependencies.
- **NFR-5** — Ease of use: a small Makefile surface; docs a mid-level engineer can follow unaided.
- **NFR-6** — 2–2.5h build budget: platform + docs get the effort; service internals stay minimal. Over-engineering is treated as a failure equal to under-building.
- **NFR-7** — Off-the-shelf only for platform components; zero bespoke infrastructure code.
- **NFR-8** — Artifact-based deploys: versioned images; deploy = repoint + restart; rollback = repoint prior tag. CI is described in docs, not built.
- **NFR-9** — Verification via a human-executable e2e test plan ([test-plan.md](./test-plan.md)): numbered steps with expected outputs. No automated test harness.

## Core entities
| Entity | Shape | Notes |
|---|---|---|
| **Event** | `site_id, page_url, lcp_ms, timestamp, session_id` (+ server-side `received_at`) | Transient: lives in the queue table, deleted on ack |
| **SiteConfig** | `site_id, sampling_rate, experiments jsonb` | Seeded, read-only; config write path out of scope |
| **LcpSample** | `(site_id, page_url, bucket_start, lcp_ms)` | Minute-bucketed processed samples; source of truth for p75 + trend |
| **PageAggregate** | `(site_id, page_url) → event_count, p75_lcp_ms, last_seen` | Written by worker, read by api |

Site and Session are keys/fields, not entities. Experiment lives inside SiteConfig's jsonb.

## API interface per app

### api (the only service with HTTP endpoints)
| Endpoint | Purpose |
|---|---|
| `POST /events` → 202 | Assignment-specified: validate + enqueue (422 on bad shape) |
| `GET /config/{site_id}` | Assignment-specified: `{site_id, sampling_rate, experiments[]}`; 404 unknown |
| `GET /sites/{site_id}/pages` | Dashboard view 1: top pages by event count `[{page_url, event_count, p75_lcp_ms, last_seen}]` |
| `GET /sites/{site_id}/trend` | Dashboard view 2: site-wide per-minute p75 `[{bucket, p75_lcp_ms, count}]`, last 60 min |
| `GET /healthz` | Compose healthcheck (`SELECT 1`) |

Dashboard view 3 (active experiments) reuses `GET /config/{site_id}` — no extra endpoint.

### worker
No HTTP surface. Input: the queue table. Output: `lcp_samples` + `page_aggregates` writes. Health = container running (compose restart policy). Operational visibility via logs (Loki) and SQL panels (Grafana Postgres datasource).

### dashboard
nginx serving static files; same-origin proxy `location /api/ → api:8000`. No CORS, no API of its own.

### platform (developer-facing)
`make up | down | reset | logs | deploy SERVICE= | rollback SERVICE= TAG= | scale N= | load | load-stop | demo-failure`

## Descope Log
Cut deliberately; each row names the trigger that would bring it back.

| Cut | Why | Build trigger |
|---|---|---|
| Prometheus + `/metrics` endpoints | Assignment mandates "observable," not metrics. Grafana's SQL datasource reads queue depth / oldest-age / aggregates directly from Postgres; Loki covers logs | App-level latency/error SLOs, or >1 host |
| Worker HTTP server | Falls out of dropping Prometheus | Same |
| Dead-letter queue | API validation rejects malformed events before the queue; worker failure = rollback + retry, not poison-pill handling | First real poison-pill incident |
| Automated test suite | Distributed stack makes automation costly in budget; replaced by a human test plan | CI existing |
| App-side p75 implementation | p75 computed in SQL (`percentile_cont`) inside the worker's transaction — one less thing to test | A store without percentile support |
| Event idempotency ids | At-least-once + single-DB transaction is already effectively exactly-once | External queue migration |
| Loadgen container | `make load` is a shell curl loop | Sustained load testing |
| Registry service, CI pipeline, config write path, authn | Not specified; not minimum viable | Team growth / multi-host |
