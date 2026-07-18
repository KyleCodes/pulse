# Adding a Service (under 15 minutes, no platform changes)

A service is: **a directory under `apps/` whose build produces a docker image, plus one compose block.** The platform discovers everything else automatically — promtail ships any compose container's stdout to Loki, the Grafana logs panel filters by service name, and `make deploy`/`make rollback` are generic over the tag-var convention.

## The contract

Your service must:
1. Log to **stdout** (JSON or logfmt preferred).
2. Read all config from **env vars** (`DATABASE_URL` is injected if you need the DB).
3. Build into an image named `pulse-<name>:$TAG`.

That's the whole contract. No metrics endpoint, no registration, no platform edits.

## Steps (timed)

**1. Create the app directory (5 min)**

```sh
mkdir apps/reporter        # your service name
```

Add your code and a `Dockerfile`. Any language.

**2. Add the Nx build target (2 min)** — copy from a sibling, change the name:

```jsonc
// apps/reporter/project.json
{
  "name": "reporter",
  "projectType": "application",
  "targets": {
    "build": {
      "executor": "nx:run-commands",
      "options": { "command": "docker build -t pulse-reporter:${TAG:-dev} apps/reporter", "cwd": "{workspaceRoot}" }
    }
  }
}
```

**3. Add the compose block (3 min)** — copy `ops/templates/service.compose.yml` into `docker-compose.yml`, replace `<name>`/`<port>`:

```yaml
  reporter:
    image: pulse-reporter:${REPORTER_TAG:-dev}
    build: apps/reporter
    environment:
      DATABASE_URL: postgres://pulse:dev@postgres:5432/pulse
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped
```

**4. Add the tag pointer and start it (1 min)**

```sh
echo 'REPORTER_TAG=dev' >> .env
docker compose up -d --build reporter
```

## You now have, for free

- Logs in Grafana (Pulse Ops logs panel + Explore, `{compose_service="reporter"}`)
- `make deploy SERVICE=reporter` / `make rollback SERVICE=reporter TAG=…`
- Service-DNS reachability from every other service (`http://reporter:<port>`)
- A restart policy and (if you add a `healthcheck:` line) health-gated dependencies
