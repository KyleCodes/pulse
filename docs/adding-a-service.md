# Adding a Service (<15 min, no platform changes)

A service is **a directory under `apps/` that builds into a docker image, plus one compose block**. The platform picks up everything else: promtail ships any container's stdout to Loki, the Grafana logs panel filters by service name, and `make deploy`/`rollback` are generic over the tag-var convention.

## The contract

1. Log to **stdout**.
2. Config from **env vars** only (`DATABASE_URL` if you need the DB).
3. Image named `pulse-<name>:$TAG`.

That's all. No metrics endpoint, no registration, no platform edits.

## Steps

**1.** Create `apps/<name>/` with your code + Dockerfile. Any language. *(~5 min)*

**2.** Copy a sibling's `project.json`, change the name: *(~2 min)*

```jsonc
{
  "name": "<name>",
  "projectType": "application",
  "targets": {
    "build": {
      "executor": "nx:run-commands",
      "options": { "command": "docker build -t pulse-<name>:${TAG:-dev} apps/<name>", "cwd": "{workspaceRoot}" }
    }
  }
}
```

**3.** Copy the block from `ops/templates/service.compose.yml` into `docker-compose.yml`, fill in the name/port. *(~3 min)*

**4.** Register the tag pointer and start: *(~1 min)*

```sh
echo '<NAME>_TAG=dev' >> .env
docker compose up -d --build <name>
```

## What you get for free

- Centralized logs in Grafana (`{compose_service="<name>"}`)
- `make deploy SERVICE=<name>` and `make rollback SERVICE=<name> TAG=…`
- Service-DNS reachability (`http://<name>:<port>`) from every other service
- Restart policy; health-gated dependencies if you add a `healthcheck:`
