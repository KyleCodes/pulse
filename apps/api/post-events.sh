#!/bin/sh
# Post N test events to the api. Usage: ./post-events.sh [count] [site_id] [page_url]
# POSIX sh (no $RANDOM). Defaults match docs/test-plan.md step 4.
COUNT="${1:-4}"
SITE="${2:-test-1}"
PAGE="${3:-/checkout}"
HOST="${API_HOST:-localhost:8000}"

i=1
while [ "$i" -le "$COUNT" ]; do
  LCP=$((i * 100))
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://$HOST/events" \
    -H 'content-type: application/json' \
    -d "{\"site_id\":\"$SITE\",\"page_url\":\"$PAGE\",\"lcp_ms\":$LCP,\"timestamp\":\"$TS\",\"session_id\":\"s-$i\"}")
  echo "event $i: lcp_ms=$LCP -> $CODE"
  i=$((i + 1))
done
