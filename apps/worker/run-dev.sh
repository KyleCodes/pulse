#!/bin/sh
# Host dev run. Needs `make up` (or at least postgres) for DB access.
cd "$(dirname "$0")"
export DATABASE_URL="${DATABASE_URL:-postgres://pulse:dev@localhost:5432/pulse}"
exec go run .
