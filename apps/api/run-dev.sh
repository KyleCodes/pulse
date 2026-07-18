#!/bin/sh
# Host dev run: venv + hot reload. Needs `make up` (or at least postgres) for DB access.
cd "$(dirname "$0")"
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q -r requirements.txt
export DATABASE_URL="${DATABASE_URL:-postgres://pulse:dev@localhost:5432/pulse}"
exec .venv/bin/uvicorn main:app --reload --host 0.0.0.0 --port "${PORT:-8000}"
