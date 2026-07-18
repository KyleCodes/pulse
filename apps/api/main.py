# pulse api — contract: apps/api/SPEC.md. Stateless: every request hits Postgres.
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, HTTPException
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("api")

pool = ConnectionPool(
    os.environ["DATABASE_URL"], min_size=1, max_size=5, open=False
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    pool.open()
    yield
    pool.close()


app = FastAPI(title="pulse-api", lifespan=lifespan)


class Event(BaseModel):
    site_id: str
    page_url: str
    lcp_ms: int
    timestamp: datetime
    session_id: str | None = None


@app.post("/events", status_code=202)
def ingest(event: Event):
    log.info("POST /events %s", event.model_dump_json())
    with pool.connection() as conn:
        conn.execute(
            "INSERT INTO events_queue (site_id, page_url, lcp_ms, session_id, ts)"
            " VALUES (%s, %s, %s, %s, %s)",
            (event.site_id, event.page_url, event.lcp_ms, event.session_id, event.timestamp),
        )
    return {"queued": True}


@app.get("/config/{site_id}")
def config(site_id: str):
    log.info("GET /config site_id=%s", site_id)
    with pool.connection() as conn:
        row = conn.execute(
            "SELECT site_id, sampling_rate, experiments FROM site_config WHERE site_id = %s",
            (site_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="unknown site")
    return {"site_id": row[0], "sampling_rate": row[1], "experiments": row[2]}


@app.get("/sites/{site_id}/pages")
def pages(site_id: str):
    log.info("GET /sites/pages site_id=%s", site_id)
    with pool.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            return cur.execute(
                "SELECT page_url, event_count, p75_lcp_ms, last_seen"
                " FROM page_aggregates WHERE site_id = %s"
                " ORDER BY event_count DESC LIMIT 20",
                (site_id,),
            ).fetchall()


@app.get("/sites/{site_id}/trend")
def trend(site_id: str):
    log.info("GET /sites/trend site_id=%s", site_id)
    with pool.connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            return cur.execute(
                "SELECT bucket_start AS bucket, count(*) AS count,"
                " percentile_cont(0.75) WITHIN GROUP (ORDER BY lcp_ms) AS p75_lcp_ms"
                " FROM lcp_samples"
                " WHERE site_id = %s AND bucket_start > now() - interval '60 minutes'"
                " GROUP BY 1 ORDER BY 1",
                (site_id,),
            ).fetchall()


@app.get("/healthz")
def healthz():
    log.info("GET /healthz")
    with pool.connection() as conn:
        conn.execute("SELECT 1")
    return {"ok": True}
