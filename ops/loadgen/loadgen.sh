#!/bin/sh
# Background load: randomized events against the local api. Started/stopped by
# `make load` / `make load-stop`. POSIX sh — no bashisms.
API="http://localhost:${API_PORT:-8000}"
SITES="site-a site-b"
PAGES="/ /pricing /checkout /blog/launch /docs"

rand() { awk -v min="$1" -v max="$2" 'BEGIN{srand(); print int(min + rand() * (max - min))}'; }

n=0
while true; do
  for site in $SITES; do
    for page in $PAGES; do
      n=$((n + 1))
      lcp=$(rand 600 3800)
      curl -s -o /dev/null -X POST "$API/events" \
        -H 'content-type: application/json' \
        -d "{\"site_id\":\"$site\",\"page_url\":\"$page\",\"lcp_ms\":$lcp,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"session_id\":\"sess-$n\"}"
    done
  done
  sleep 0.2
done
