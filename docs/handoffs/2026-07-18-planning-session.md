# Handoff — Planning Session (2026-07-18)

Platform take-home ("pulse"). Planning and platform scaffold are **done and verified**; app implementation is the remaining work, divided across three agents.

## Current state (all verified, stack running)

- `make up` brings up the full 7-service stack: postgres (healthy), loki, promtail, grafana (healthy), api (healthy), worker, dashboard.
- All three app images build via `npx nx run-many -t build` (nx 20.8.4, run-commands targets only — no language plugins).
- All three apps run on host via `apps/<name>/run-dev.sh` (`make dev SERVICE=x`). Go + nx were installed on this machine during the session.
- Log shipping confirmed: worker stdout is queryable in Loki via Grafana.
- Dashboard→api nginx proxy confirmed (`localhost:8080/api/healthz`).
- Schema + seed applied on fresh volume (2 sites in `site_config`).
- Apps are **stubs**: api serves only `/healthz`; worker logs heartbeats; dashboard is a placeholder page. Full contracts live in each `apps/<name>/SPEC.md`.

## Key decisions (rationale in docs/design.md)

- **Queue = Postgres `FOR UPDATE SKIP LOCKED`** (`events_queue` table). Ack = delete in the same tx as persistence → effectively exactly-once. This is the declared least-confident decision.
- **Artifacts = versioned image tags in the local docker daemon**; `.env` tag vars are the deploy/rollback pointers (`make deploy` / `make rollback`). No registry service.
- **Observability = Grafana + Loki + Postgres-datasource SQL panels.** No Prometheus, no `/metrics` — descoped deliberately (see docs/requirements.md Descope Log).
- **Worker has no HTTP surface.** p75 computed in SQL (`percentile_cont`), not app code.
- **Trend** requires minute-bucketed samples (`lcp_samples`) — implied by the assignment, easy to miss.
- Verification = human test plan (docs/test-plan.md), not an automated suite.

## Remaining work (in order)

1. Implement the three apps per their SPECs (parallel agents — see agent-*.md in this dir).
2. Run docs/test-plan.md end-to-end; fix until all 9 steps pass.
3. Commit history + push to public GitHub repo. **Remove/ignore `initial_notes.md` first (private interview notes) and `assignment.pdf`.**
4. Record Loom: deploy (`make deploy SERVICE=api`), observability tour (Grafana Pulse Ops), failure drill (`make demo-failure`), recovery. Runbook = script.
5. Link Loom in README; email brian@coframe.com the repo link.

## Gotchas

- Compose healthcheck for api uses `python -c urllib` (no curl in slim image) — keep `/healthz` fast and dependency-free.
- Worker replicas: no `ports`/`container_name` on the worker service — required for `make scale`.
- `.env` is committed by design (tag pointers + ports); `.env.tmp` is the sed scratch file, gitignored.
- macOS + Linux both: Makefile avoids `sed -i`; loadgen script is POSIX sh (no `$RANDOM`).
- Time budget: ~1h spent on planning/platform. Apps + docs polish + Loom must fit the remaining ~1.5h.
