# Agent Handoff — traffic (generator app)

Implement the 4th service: a continuous traffic generator. Beyond the app itself, this task is the **live drill of the platform's core claim** — a new service in under 15 minutes by following the docs. Treat the docs as the only path.

## Read first (in order)
1. `apps/traffic/SPEC.md` — your contract (two files: `traffic.sh` + `Dockerfile`).
2. `docs/adding-a-service.md` — **follow its steps verbatim**; this task exists partly to prove that doc works.
3. `ops/loadgen/loadgen.sh` — reference loop to adapt (host-side cousin of this app).
4. `apps/api/SPEC.md` §`POST /events` — the payload shape you send.

## Constraints
- Use ONLY the documented adding-a-service path: `project.json` copied from a sibling app, compose block copied from `ops/templates/service.compose.yml`, `TRAFFIC_TAG=dev` appended to `.env`. No other platform edits — if the doc is insufficient, that's a finding to report, not a workaround to invent.
- **Time yourself**: start the clock when you begin, stop at a successful `docker compose up -d --build traffic`. Record the wall time in your completion handoff (`docs/handoffs/traffic-app/`) — it becomes evidence in design.md and the demo.
- POSIX sh only (busybox); no `$RANDOM`, no bashisms. curl failures must not kill the loop.
- Don't touch anything outside `apps/traffic/` except the three documented platform touchpoints above.

## Verify (definition of done)
Run the SPEC's five acceptance checks. The stack is already up (`docker compose ps` to confirm). Then write your completion handoff to `docs/handoffs/traffic-app/` including the timed result and any friction you hit in `adding-a-service.md`.
