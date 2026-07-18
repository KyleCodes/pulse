# Agent Handoff — dashboard (static HTML+JS)

Implement the customer dashboard in `apps/dashboard/index.html`, replacing the stub. One file, vanilla JS, inline style/script. Explicitly throwaway quality — no framework, no chart library, minimal CSS. The assignment warns against polishing this.

## Read first (in order)
1. `apps/dashboard/SPEC.md` — your contract: three sections (top pages table, p75 trend, active experiments), site selector, 5s refresh. `nginx.conf` and `Dockerfile` already exist — do not change them.
2. `apps/api/SPEC.md` §Endpoints — the JSON shapes you consume (`/api/sites/{site}/pages`, `/api/sites/{site}/trend`, `/api/config/{site}`).
3. `docs/test-plan.md` **step 7** — acceptance: test-1 data visible, site-a shows seeded experiments.

## Constraints
- All fetches same-origin through `/api/...` (nginx proxies to the api service). No CORS, no absolute URLs.
- Trend rendering: inline SVG polyline or bar divs — anything readable; do not add a library.
- Handle 404 (unknown site) and empty states without breaking.
- Don't touch anything outside `apps/dashboard/`.

## Verify (definition of done)
```sh
make build SERVICE=dashboard && docker compose up -d dashboard
# open localhost:8080 — needs api (+ worker for aggregates) running; stack is already up.
# seed data via docs/test-plan.md step 4, then check step 7: tables populate, experiments listed for site-a.
```
