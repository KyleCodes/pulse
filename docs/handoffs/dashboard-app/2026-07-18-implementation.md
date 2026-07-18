# Handoff — dashboard implemented (2026-07-18)

The dashboard stub in `apps/dashboard/index.html` is replaced with the full implementation per `apps/dashboard/SPEC.md`. Image rebuilt (`pulse-dashboard:dev`) and the container recreated. Test-plan step 7 passes. Nothing outside `apps/dashboard/` was touched; `nginx.conf` and `Dockerfile` are unchanged.

## What was built

One file, ~120 lines, vanilla JS, inline style/script, no libraries.

- **Site selector**: text input (default `site-a`) + Load button inside a `<form>` — submit handler gives Enter-key support for free.
- **Three sections**, each an independent fetch through a shared wrapper (`load(path, container, render, notFoundMsg)`): 404 → per-section message, non-OK → `error: HTTP n`, network failure → caught and shown. No `Promise.all`, so sections fail independently — required because test sites (e.g. `test-1`) have pages/trend data but 404 on config.
  1. Top pages — `GET /api/sites/{site}/pages` → table (page_url, events, p75, last seen).
  2. Trend — `GET /api/sites/{site}/trend` → bar divs in a flex row, height scaled to max p75, `title` tooltip per bucket. Bars over SVG polyline: no coordinate math, and a single bucket still renders visibly.
  3. Experiments — `GET /api/config/{site}` → sampling rate + `name — status` list; 404 → "unknown site".
- **5s refresh**: `setInterval`; `clearInterval` before starting a new one on site change (prevents stacked timers). URLs use `encodeURIComponent(site)`.
- **Safety**: DOM built with `createElement` + `textContent` — hostile `page_url` values can't inject markup. Null `p75_lcp_ms`/`last_seen` render as `—`.

Deliberately skipped (throwaway-quality budget per the assignment): AbortController, spinners, axes/labels, gap-filling missing minute buckets, retries, any real CSS.

## How it was verified

Stack was already up; api and worker were found **already implemented** (not stubs as the planning handoff assumed), so full data acceptance ran, not just error paths.

1. `make build SERVICE=dashboard && docker compose up -d dashboard` — clean build, container recreated.
2. Endpoint checks through the proxy: page 200, `/api/healthz` 200, `/api/config/nope` 404.
3. Seeded `test-1` per test-plan step 4 (four events, 100/200/300/400ms) → step 5/6 outputs confirmed via curl: `/checkout`, `p75_lcp_ms: 325`, trend buckets present.
4. Headless Chrome (`--dump-dom --virtual-time-budget=4000`) against `localhost:8080`:
   - **site-a**: pages table populated, trend bar with tooltip, both seeded experiments + sampling rate rendered.
   - **test-1** (via a temporary copy of the page defaulting to `test-1`, docker-cp'd into the container and removed after): `/checkout | 8 | 325` row, two trend bars (`n=4` each), experiments section shows "unknown site" while the other sections render — independent failure confirmed. (Count was 8, not 4: step 4 had been run once before this session; p75 is 325 either way.)

## Remaining work (from the planning handoff)

Dashboard is done. Next per `docs/handoffs/2026-07-18-planning-session.md`: run the full 9-step test plan end-to-end, commit + push (remove/ignore `initial_notes.md` and `assignment.pdf` first), record the Loom, email the repo link.
