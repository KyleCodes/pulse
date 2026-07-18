# pulse

Web-performance monitoring on a minimum viable platform: a FastAPI ingest api, a Go aggregate worker, a static customer dashboard, and an always-on traffic generator — all on docker compose with artifact-based deploys, centralized logs, and a provisioned operator dashboard.

**Docs:** [design](docs/design.md) · [requirements](docs/requirements.md) · [user guide](docs/user-guide.md) · [runbook](docs/runbook.md) · [adding a service](docs/adding-a-service.md) · [test plan](docs/test-plan.md)

Prereqs: **docker + make**. (Node is used only by `make deploy`; every step has a raw-docker fallback in the [user guide](docs/user-guide.md).)

## 1. Build + run everything

```sh
make up        # builds everything, starts the stack ATTACHED — all services' logs stream here
make up D=1    # same, detached (background)
docker compose ps   # expect: postgres/api/grafana healthy, all others Up
```

Attached mode is the point: you watch postgres init, the worker's `batch_done` lines, api request logs, and traffic's `posted total=N` counters interleave in one terminal. Ctrl-C stops the stack.

Images can also be built without starting anything: `make build` (all) or `make build SERVICE=api`.

## 2. View the dashboards

| URL | What you should see |
|---|---|
| http://localhost:8080 | Customer dashboard — with `traffic` running, site-a/site-b counts **rise on every refresh** |
| http://localhost:3000 | Grafana "Pulse Ops" (no login) — queue depth ~0, events/min climbing, live logs from all services |
| http://localhost:8000/docs | API swagger |

The `traffic` service generates load continuously. Throttle it with `docker compose stop traffic` / `start traffic`.

## 3. Verify the pipeline end to end

The 9-step [test plan](docs/test-plan.md) (~5 min) is the full pass. The single most informative check — proves queue → worker → store → api with an exact expected value:

```sh
for lcp in 100 200 300 400; do
  curl -s -o /dev/null -X POST localhost:8000/events -H 'content-type: application/json' \
    -d "{\"site_id\":\"test-1\",\"page_url\":\"/checkout\",\"lcp_ms\":$lcp,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"session_id\":\"s1\"}"
done
sleep 2 && curl -s localhost:8000/sites/test-1/pages
# → event_count: 4, p75_lcp_ms: 325  (exact — percentile interpolation over [100,200,300,400])
```

Then prove the no-loss failure story (this is the runbook scenario): `make demo-failure` — worker stops, watch queue depth climb in Grafana, recover, watch it drain. And prove horizontal scale: `make scale N=3`.

## 4. Deploy / rollback

```sh
make deploy SERVICE=api                  # build pulse-api:<git-sha>, repoint, recreate api only
make rollback SERVICE=api TAG=<sha>      # repoint back to any prior tag, seconds, no rebuild
```

**Where artifacts live:** every build produces an immutable image `pulse-<service>:<tag>` stored in the local docker daemon's content-addressed image store (`docker images pulse-api` lists them — this machine's artifact registry). The compose file never hardcodes a version; it reads tag pointers from `.env` (`API_TAG=…`). *Deploy* = build a new tag + move the pointer + recreate one service. *Rollback* = move the pointer to a tag that already exists. In production the same verbs push/pull a hosted registry; only the storage location changes.

## 5. Dev mode (host, hot reload)

```sh
make dev SERVICE=api        # uvicorn --reload against the compose postgres
make dev SERVICE=worker     # go run
make dev SERVICE=dashboard  # static server on :8080 (no /api proxy on host)
```

Requires `make up` first (postgres must be up on :5432). Stop the containerized twin first if ports clash (`docker compose stop api`).

## 6. Clean slate

```sh
make reset && make up   # wipes the DB volume and re-seeds — do this before recording a demo
```

## Layout

```
apps/        one dir per service (Dockerfile + code + SPEC.md contract)
ops/         platform config as code: schema/seed, promtail, grafana provisioning, templates
docs/        design, requirements, guides, runbook, test plan, build handoffs
docker-compose.yml   the deployable artifact
Makefile             the human interface
```

Time spent: ~2.5h.
