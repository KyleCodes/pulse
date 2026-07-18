#!/bin/sh
# Host dev run: plain static server. The /api/ proxy only exists in the nginx
# container, so api calls fail here unless you point fetches at :8000 directly.
cd "$(dirname "$0")"
exec python3 -m http.server "${PORT:-8080}"
