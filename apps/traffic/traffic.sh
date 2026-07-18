#!/bin/sh
# Continuous traffic: randomized events against the api, forever. POSIX sh.
# Contract: apps/traffic/SPEC.md. Reference: ops/loadgen/loadgen.sh.
API="${API_URL:-http://api:8000}"
SITES="site-a site-b"
PAGES="/ /pricing /checkout /blog/launch /docs"

# Uniform 600-3800. /dev/urandom, not awk srand() — srand reseeds per second,
# so a sub-second burst would get identical values.
rand_lcp() { echo $((600 + $(od -An -tu2 -N2 /dev/urandom) % 3200)); }

n=0
while true; do
  for site in $SITES; do
    for page in $PAGES; do
      n=$((n + 1))
      curl -s -o /dev/null -X POST "$API/events" \
        -H 'content-type: application/json' \
        -d "{\"site_id\":\"$site\",\"page_url\":\"$page\",\"lcp_ms\":$(rand_lcp),\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"session_id\":\"sess-$n\"}"
      [ $((n % 100)) -eq 0 ] && echo "msg=posted total=$n"
    done
  done
  sleep 0.5
done
