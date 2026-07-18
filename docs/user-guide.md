# User Guide

Day-to-day platform usage. Host deps: **docker + make** (Node only for `make deploy`; raw fallback below).

## Start / stop

```sh
make up      # build + start everything, attached: all logs stream to this terminal (Ctrl-C stops)
make up D=1  # detached
make down    # stop (data kept)
make reset   # stop + wipe data; next up re-seeds
```

| URL | What |
|---|---|
| localhost:8080 | Customer dashboard |
| localhost:3000 | Grafana — "Pulse Ops" operator dashboard, no login |
| localhost:8000/docs | API swagger |

## See what's happening

- **Grafana → Pulse Ops**: queue depth, oldest unprocessed event, throughput, live logs from every service. This replaces `tail -f`.
- **Grafana → Explore → Loki**: search any service's logs — `{compose_service="api"}`.
- `make logs` / `docker compose ps`: raw fallback.

## Dev loop (run an app on the host)

```sh
make dev SERVICE=api|worker|dashboard   # hot-reload against the compose postgres
make build [SERVICE=x]                  # build image(s) without deploying
```

Run `make up` first — host dev connects to `localhost:5432`.

## Deploy (no SSH)

```sh
make deploy SERVICE=api
```

Builds `pulse-api:<git-sha>`, repoints `API_TAG` in `.env`, recreates only that container. The docker daemon's image store is the artifact registry — every prior tag stays available.

No-Node fallback: `docker build -t pulse-api:<tag> apps/api`, edit `.env`, `docker compose up -d api`.

## Roll back

```sh
make rollback SERVICE=api TAG=<prior-sha>   # docker images pulse-api  → lists tags
```

Repoint + recreate from the already-built image. Seconds, no rebuild.

## Scale

```sh
make scale N=4      # worker replicas; SKIP LOCKED partitions work automatically
```

## Traffic & failure drill

```sh
make load / load-stop   # background event generator
make demo-failure       # guided worker-outage drill (see runbook.md)
```

## More

- Add a service (<15 min): [adding-a-service.md](./adding-a-service.md)
- Verify the whole system (~5 min): [test-plan.md](./test-plan.md)
