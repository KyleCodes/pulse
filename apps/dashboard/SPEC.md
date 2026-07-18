# dashboard — implementation spec

Static HTML + vanilla JS on nginx. Throwaway quality is fine; no SPA, no framework, no build step. Acceptance = `docs/test-plan.md` step 7.

## Files
- `index.html` — the whole app (inline `<script>`/`<style>` fine).
- `nginx.conf` — serve static; proxy `/api/` to the api service (same-origin, no CORS):
  ```nginx
  server {
    listen 80;
    location /api/ { proxy_pass http://api:8000/; }
    location / { root /usr/share/nginx/html; index index.html; }
  }
  ```
- `Dockerfile` — `FROM nginx:alpine`, copy nginx.conf to `/etc/nginx/conf.d/default.conf`, index.html to `/usr/share/nginx/html/`.

## Behavior
- Site selector: text input defaulting to `site-a` + a Load button (site-b and test sites must be reachable too).
- Three sections, fetched on load / on site change, refreshed every 5s:
  1. **Top pages** — `GET /api/sites/{site}/pages` → table: page_url, event_count, p75_lcp_ms, last_seen.
  2. **p75 LCP trend** — `GET /api/sites/{site}/trend` → minimal line/bar rendering (inline SVG or divs; no chart library).
  3. **Active experiments** — `GET /api/config/{site}` → list name + status + sampling rate; show "unknown site" on 404.
- Zero styling effort beyond readable (system font, one table border).
