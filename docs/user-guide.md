# User Guide

Day-to-day platform usage for the engineering team. Prereqs: **docker + make**. Node is needed only by `make deploy` (Nx); every Nx call has a raw fallback listed below.

## Bring the stack up / down

```sh
make up        # build + start everything; prints URLs when ready
make down      # stop everything (data kept)
make reset     # stop + wipe data; next `make up` re-seeds a fresh DB
```

URLs after `make up`:

| URL | What |
|---|---|
| http://localhost:8080 | Customer dashboard |
| http://localhost:3000 | Grafana (operator dashboard "Pulse Ops", no login needed) |
| http://localhost:8000/docs | API (FastAPI swagger) |

## See what's happening

- **Grafana → Pulse Ops** — queue depth, oldest unprocessed event age, processing rate, top pages, and live logs from every service. This replaces `tail -f`.
- **Grafana → Explore → Loki** — search any service's logs: `{compose_service="api"}`.
- `make logs` — raw `docker compose logs -f` if Grafana is down.
- `docker compose ps` — health of every container.

## Run an app on the host (dev loop)

```sh
make dev SERVICE=api        # hot-reload uvicorn against the compose postgres
make dev SERVICE=worker     # go run
make dev SERVICE=dashboard  # static server on :8080 (no /api proxy in host dev)
```

Each app has an `apps/<name>/run-dev.sh` (what `make dev` calls via nx). Run `make up` first — host dev connects to the compose postgres on `localhost:5432`. `make build` (or `make build SERVICE=x`) builds the docker images without deploying.

## Deploy a service (no SSH)

```sh
make deploy SERVICE=api
```

This builds `pulse-api:<git-sha>`, repoints `API_TAG` in `.env`, and recreates only the api container. Other services are untouched. The image store in the local docker daemon is the artifact registry; every previously built tag remains available.

Raw fallback (no Node): `TAG=abc123 docker build -t pulse-api:abc123 apps/api`, edit `.env`, `docker compose up -d api`.

## Roll back

```sh
make rollback SERVICE=api TAG=<previous-sha>   # list tags: docker images pulse-api
```

Repoints the tag var and recreates the service from the already-built image. Seconds, no rebuild.

## Scale the worker

```sh
make scale N=4
```

Workers claim disjoint batches via `SKIP LOCKED`; no coordination or config needed. The api can be scaled the same way behind a load balancer (`docker compose up -d --scale api=3` — add an LB first, ports conflict otherwise).

## Generate traffic / rehearse a failure

```sh
make load          # background loop POSTing randomized events
make load-stop
make demo-failure  # guided worker-outage drill (see runbook.md)
```

## Add a new service

See [adding-a-service.md](./adding-a-service.md) — copy a template, four small steps, under 15 minutes, no platform changes.

## Verify the system

Run [test-plan.md](./test-plan.md) top to bottom (~5 minutes, copy-paste).
