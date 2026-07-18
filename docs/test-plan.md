# Test Plan (human-executable, ~5 min)

Run in order from the repo root. Each step states its expected result. Written before the apps — this is the acceptance scope.

**1. Bring-up** — `make up && docker compose ps`
→ all `Up`; postgres/api/grafana `healthy`; :8080, :3000, :8000/docs respond.

**2. Seeded config** — `curl -s localhost:8000/config/site-a`
→ `sampling_rate: 1.0` + 2 experiments. `…/config/nope` → **404**.

**3. Validation** — POST an event missing `lcp_ms`:
```sh
curl -s -o /dev/null -w '%{http_code}' -X POST localhost:8000/events \
  -H 'content-type: application/json' \
  -d '{"site_id":"t","page_url":"/x","timestamp":"2026-07-18T12:00:00Z","session_id":"s"}'
```
→ **422**, nothing queued.

**4. Ingest** — four events, LCP 100/200/300/400:
```sh
for lcp in 100 200 300 400; do
  curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8000/events \
    -H 'content-type: application/json' \
    -d "{\"site_id\":\"test-1\",\"page_url\":\"/checkout\",\"lcp_ms\":$lcp,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"session_id\":\"s1\"}"
done
```
→ four **202**s.

**5. Pipeline (queue → worker → store → api)** — `sleep 2 && curl -s localhost:8000/sites/test-1/pages`
→ `/checkout`, `event_count: 4`, **`p75_lcp_ms: 325`** — exact: `percentile_cont(0.75)` over [100,200,300,400] interpolates 300 + 0.25·100.

**6. Trend** — `curl -s localhost:8000/sites/test-1/trend`
→ ≥1 bucket (current minute), `count: 4`, `p75_lcp_ms: 325`.

**7. Dashboards**
- :8080 → site `test-1`: table + trend match step 5; site `site-a`: seeded experiments listed.
- Grafana Pulse Ops: queue depth ~0; processing-rate shows the events; logs panel shows api + worker.

**8. Failure drill (no loss)**
```sh
make load
docker compose stop worker     # watch Grafana ~30s: depth + oldest-age climb
docker compose start worker    # depth drains to ~0, counts resume with no gap
make load-stop
```

**9. Deploy + rollback** — make a visible change in `apps/api` (e.g. add a field to `/healthz`):
```sh
make deploy SERVICE=api        # only api recreated; .env API_TAG = git sha
curl -s localhost:8000/healthz # change visible
make rollback SERVICE=api TAG=dev
curl -s localhost:8000/healthz # change gone
```
→ worker/dashboard untouched throughout (`docker compose ps` created-times unchanged).
