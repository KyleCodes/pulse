# Design

Codename **pulse**. One repo, one compose file, three app services, four off-the-shelf infra services.

```
            POST /events              SELECT..FOR UPDATE SKIP LOCKED
  SDK ──────────────► api ──INSERT──► events_queue ◄───────────────┐
                       │                 (postgres)                │
  dashboard ──/api/──► │ reads                                   worker ×N
  (nginx proxy)        ▼                                           │ one tx:
            page_aggregates ◄───────── upsert + delete(ack) ───────┘ samples,
            lcp_samples                                              aggregates,
                                                                     ack
  promtail ──► loki ──► grafana ◄── postgres datasource (queue depth, rates, tables)
  (all container stdout)
```

## Service shapes (one paragraph each)

**api (Python/FastAPI).** Inputs: SDK event POSTs and dashboard/config GETs over HTTP :8000. Outputs: rows inserted into `events_queue` (the enqueue), and JSON read responses served from `site_config`, `page_aggregates`, and `lcp_samples`. State: none in-process — every request is a stateless pass-through to Postgres, so N replicas need nothing but the same `DATABASE_URL`.

**worker (Go).** Inputs: batches claimed from `events_queue` via `SELECT … ORDER BY id LIMIT 500 FOR UPDATE SKIP LOCKED`. Outputs: minute-bucketed rows in `lcp_samples`, upserts into `page_aggregates` (count, p75 via `percentile_cont(0.75)` over the trailing 60 min, last-seen), and the batch delete that is the ack — all in one transaction. State: none in-process; all state is in Postgres, so `--scale worker=N` just works (SKIP LOCKED hands each replica disjoint batches, no coordinator).

**dashboard (static HTML+JS on nginx).** Inputs: user's browser on :8080. Outputs: three views (top pages, p75 trend, active experiments) rendered from api JSON, fetched same-origin through nginx's `/api/` proxy. State: none — it is a static file plus a proxy rule.

**The queue** is a Postgres table. This is the explicit architectural choice the assignment asks for; see the decision table and "least confident" below.

## Stack choices (one rejected alternative each)

| Component | Choice | Rejected alternative | Why rejected |
|---|---|---|---|
| Queue | Postgres `FOR UPDATE SKIP LOCKED` | Kafka/Redpanda | A second stateful system with its own ops surface, for a team of 5 at laptop scale. The Postgres queue gives transactional ack-with-persist (effectively exactly-once, since queue and store share one DB), SQL-queryable depth/lag for free, and N-consumer scaling with no coordinator. The enqueue/consume interface is two SQL statements — swappable for Kafka when scale demands it |
| Deploy artifact | Versioned image tags in the local docker daemon; `.env` tag vars are the pointers | Registry container (`registry:2`) | A registry is a real component to run and explain for zero local benefit — the daemon's image store already is a content-addressed on-disk artifact store. In production the same `make deploy` pushes to a hosted registry; only the push destination changes |
| Observability | Grafana + Loki (logs) + Postgres datasource (SQL panels) | Prometheus + `/metrics` per service | Prometheus adds a scrape contract every service must implement plus another component, and at this scale every operational question (queue depth, oldest unprocessed event, rates, aggregates) is answerable by SQL against the one database. Loki replaces `tail -f` with centralized search. Trigger to add Prometheus: app-level latency/error SLOs or a second host |
| Log shipping | promtail container reading the docker socket | Loki docker logging driver | The driver needs `docker plugin install` on the grader's machine (mutates the host, breaks "make up just works") and a wedged driver can block container starts. Promtail needs only a read-only socket mount |
| Dashboard→API | nginx same-origin proxy | CORS on the api | One nginx location block vs CORS middleware + preflight surface; the proxy also mirrors the production edge shape |
| p75 | SQL `percentile_cont(0.75)` in the worker's transaction | App-side t-digest / streaming estimate | Exact, zero code, already inside the transaction. Approximate structures earn their keep at 100× volume, not here |
| Monorepo build | Nx with `run-commands` targets only | Nx language plugins (`@nx-go`, `@nxlv/python`) | Plugins add setup risk and buy nothing when the contract is "each app has a build target that emits a docker image." Nx stays non-load-bearing: `make up` needs zero Node; only `make deploy` calls `npx nx`, with a raw `docker build` fallback documented |

## The decision I'm least confident about

**Postgres as the queue.** It couples ingest durability and worker throughput to one database, and "use the database as a queue" fails at some scale — table churn, vacuum pressure, lock contention past tens of thousands of events/sec. I chose it anyway because at this team's scale it removes an entire stateful system, makes the queue observable with `SELECT count(*)`, and gives transactional exactly-once semantics that Kafka consumers have to work hard to approximate. The migration seam is explicit: producers call "enqueue" (one INSERT) and consumers call "claim batch / ack" (one SELECT, one DELETE) — swapping those for a Kafka producer/consumer group changes no business logic. If ingest sustains >~5k events/sec or the worker fleet can't drain the backlog, that's the trigger.

## What I deliberately didn't build

| Not built | Trigger to build |
|---|---|
| Prometheus + per-service `/metrics` | Latency/error SLOs, or a second host |
| Dead-letter queue | First poison-pill incident (today: API validation front-stops malformed events; worker errors roll back and retry) |
| CI pipeline | Exists as a described workflow (build → tag → push → repoint) the day the team adds a runner; local `make deploy` is the same verbs |
| Config write path (A/B test editing) | The dashboard needs it; today config is seeded SQL |
| Authn on api/dashboard | First external customer; today it's VPN/laptop-local |
| Automated test suite | CI existing; today `docs/test-plan.md` is executable by a human in ~5 min |
| Multi-host orchestration (k8s/Nomad) | A second host. Compose file is the deployable artifact until then |

## Scaling story (no single-node app bottlenecks)

api is stateless → `docker compose up -d --scale api=N` behind any TCP LB. worker is stateless → `make scale N=4`; SKIP LOCKED partitions work automatically. Postgres is the single stateful node — accepted consciously at this scale, with the queue interface as the escape hatch and read replicas / partitioning as the standard next steps. Nothing else in the system holds state.
