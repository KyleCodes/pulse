# pulse

Minimum viable platform for a web-performance-monitoring product: three services (FastAPI ingest api, Go aggregate worker, static dashboard) on a docker-compose platform with artifact-based deploys, centralized logs, and a provisioned operator dashboard.

**Loom walkthrough:** _link pending_

## Quickstart

```sh
make up
```

| URL | What |
|---|---|
| http://localhost:8080 | Customer dashboard |
| http://localhost:3000 | Grafana — "Pulse Ops" operator dashboard (no login) |
| http://localhost:8000/docs | API |

Prereqs: docker, make. (Node only for `make deploy`; fallback documented.)

## Docs

| Doc | Contents |
|---|---|
| [docs/design.md](docs/design.md) | Architecture, stack decisions + rejected alternatives, least-confident decision, deliberately-not-built |
| [docs/requirements.md](docs/requirements.md) | Functional/non-functional requirements, entities, API surfaces, descope log |
| [docs/user-guide.md](docs/user-guide.md) | Day-to-day platform usage: deploy, rollback, scale, logs |
| [docs/runbook.md](docs/runbook.md) | Worker-outage runbook (the failure demonstrated in the recording) |
| [docs/adding-a-service.md](docs/adding-a-service.md) | Add a 4th service in <15 min, no platform changes |
| [docs/test-plan.md](docs/test-plan.md) | Human-executable e2e verification (~5 min) |

## Layout

```
apps/        one directory per service: Dockerfile + project.json (+ SPEC.md contract)
ops/         platform config as code: schema/seed, promtail, grafana provisioning, templates
docs/        all documentation (markdown)
docker-compose.yml   the deployable artifact
Makefile             the human interface (up/deploy/rollback/scale/load/demo-failure)
```

Time spent: ~2.5h (tracked per the assignment's ask).
