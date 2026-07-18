# Test Plan (human-executable, ~5 minutes)

End-to-end verification by hand. Run steps in order from the repo root; each step states its expected result. Written before the apps — this encodes the system's acceptance scope.

## 1. Bring-up
```sh
make up && docker compose ps
```
**Expect:** all containers `Up`, postgres/api/grafana `healthy`. http://localhost:8080, :3000, :8000/docs all respond.

## 2. Config endpoint (seeded)
```sh
curl -s localhost:8000/config/site-a
```
**Expect:** `{"site_id":"site-a","sampling_rate":1.0,"experiments":[...]}` with 2 experiments. `curl -s -o /dev/null -w '%{http_code}' localhost:8000/config/nope` → `404`.

## 3. Validation rejects malformed events
```sh
curl -s -o /dev/null -w '%{http_code}' -X POST localhost:8000/events \
  -H 'content-type: application/json' \
  -d '{"site_id":"test-1","page_url":"/x","timestamp":"2026-07-18T12:00:00Z","session_id":"s1"}'
```
**Expect:** `422` (missing `lcp_ms`).

## 4. Ingest accepts events
```sh
for lcp in 100 200 300 400; do
  curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8000/events \
    -H 'content-type: application/json' \
    -d "{\"site_id\":\"test-1\",\"page_url\":\"/checkout\",\"lcp_ms\":$lcp,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"session_id\":\"s1\"}"
done
```
**Expect:** four `202`s.

## 5. Pipeline: queue → worker → aggregates
```sh
sleep 2 && curl -s localhost:8000/sites/test-1/pages
```
**Expect:** one entry: `page_url:"/checkout"`, `event_count:4`, **`p75_lcp_ms:325`** (exact — `percentile_cont(0.75)` over [100,200,300,400] interpolates 300 + 0.25·100), recent `last_seen`.

## 6. Trend
```sh
curl -s localhost:8000/sites/test-1/trend
```
**Expect:** ≥1 bucket, current minute, `count:4`, `p75_lcp_ms:325`.

## 7. Dashboards
- http://localhost:8080 → select/enter `test-1` → top-pages row and trend point match step 5; `site-a` shows its seeded experiments.
- Grafana Pulse Ops → queue depth ~0, processing-rate panel shows the 4 events, logs panel shows api + worker lines.

## 8. Failure drill (no data loss)
```sh
make load                        # traffic flowing
docker compose stop worker       # induce the failure
```
Watch Grafana ~30s: **queue depth and oldest-age climb** (events buffering durably, not lost).
```sh
docker compose start worker
```
**Expect:** depth drains to ~0, oldest-age drops, dashboard counts keep rising with no gap. `make load-stop` when done.

## 9. Deploy + rollback drill
```sh
# make a trivial visible change in apps/api (e.g. add a field to /healthz), then:
make deploy SERVICE=api          # only api recreated; .env API_TAG now a git sha
curl -s localhost:8000/healthz   # change visible
make rollback SERVICE=api TAG=dev
curl -s localhost:8000/healthz   # change gone
```
**Expect:** worker/dashboard containers untouched throughout (`docker compose ps` — their created-at unchanged).
