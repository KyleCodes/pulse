# Design

```
            POST /events              SELECT … FOR UPDATE SKIP LOCKED
  SDK ──────────────► api ──INSERT──► events_queue ◄───────────────┐
                       │                (postgres)                 │
  dashboard ──/api/──► │ reads                                   worker ×N
  (nginx proxy)        ▼                                           │  one tx:
            page_aggregates ◄──── upsert + delete(ack) ────────────┘  samples,
            lcp_samples                                               aggregates,
                                                                      ack
  promtail ──► loki ──► grafana ◄── postgres datasource (depth, rates, tables)
  (all container stdout)
```

## Service shapes

**api** (FastAPI). In: event POSTs and read GETs on :8000. Out: one INSERT into `events_queue` per event; JSON reads from `site_config`, `page_aggregates`, `lcp_samples`. State: none — every request passes through to Postgres, so N replicas need nothing but the same `DATABASE_URL`.

**worker** (Go). In: batches of ≤500 claimed with `FOR UPDATE SKIP LOCKED`. Out — all in **one transaction**: minute-bucketed rows into `lcp_samples`, key-sorted upserts into `page_aggregates` (count, `percentile_cont(0.75)` over trailing 60 min, last-seen), then the batch DELETE, which *is* the ack. State: none in-process; `--scale worker=N` just works — SKIP LOCKED hands replicas disjoint batches with no coordinator.

**dashboard** (static HTML+JS on nginx). In: a browser on :8080. Out: three views (top pages, p75 trend, experiments) rendered from api JSON, fetched same-origin via nginx's `/api/` proxy. State: none.

**The queue** is a Postgres table — the assignment's required architectural choice, defended below.

## Decisions (one rejected alternative each)

| Component | Chose | Over | Because |
|---|---|---|---|
| Queue | Postgres `SKIP LOCKED` | Kafka/Redpanda | No second stateful system at 5-person scale. Transactional ack-with-persist = effectively exactly-once; depth/lag queryable in SQL; N consumers free. Interface is 2 SQL statements — swappable later |
| Deploy artifact | Image tags in local docker daemon, `.env` vars as pointers | Registry container | The daemon already is a content-addressed artifact store. Prod = same verbs, push to a hosted registry |
| Observability | Grafana + Loki + Postgres-datasource SQL panels | Prometheus + `/metrics` | Every ops question here is a SQL query away; one less component and no per-service scrape contract. Loki replaces `tail -f` with search |
| Log shipping | promtail reading the docker socket | Loki logging driver | Driver requires a host `docker plugin install` and can wedge container starts; promtail needs one read-only mount |
| Dashboard→api | nginx same-origin proxy | CORS | One config line, no preflight surface, mirrors a real edge |
| p75 | SQL `percentile_cont` | t-digest / app-side | Exact, zero code, already inside the tx. Approximation earns its keep at 100×, not here |
| Monorepo build | Nx `run-commands` only | Nx language plugins | Contract is just "build target → docker image". Nx is non-load-bearing: `make up` needs zero Node |

## Least-confident decision

**Postgres as the queue.** It couples ingest durability to the app database, and DB-as-queue fails at scale (table churn, vacuum pressure, contention past ~thousands of events/sec). Chosen anyway: it deletes an entire stateful system, makes the queue observable with `SELECT count(*)`, and gives exactly-once semantics Kafka consumers must work hard to approximate. The migration seam is explicit — enqueue is one INSERT, consume is claim-batch + ack — so swapping in Kafka changes no business logic. Trigger: sustained multi-k events/sec or a worker fleet that can't drain.

## Deliberately not built

See the [descope log](./requirements.md#descope-log) — Prometheus, DLQ, automated tests, registry, CI, config write path, auth — each with its build trigger.

## Scaling

api: stateless, `--scale api=N` behind any LB. worker: `make scale N=4`, partitioning is automatic. Postgres is the single stateful node — accepted consciously, with the queue seam as the escape hatch and read replicas/partitioning as the standard next steps. Nothing else holds state.
