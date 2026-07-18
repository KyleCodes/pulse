-- Runs once on a fresh pgdata volume (docker-entrypoint-initdb.d).
-- `make reset` wipes the volume; next `make up` re-runs this.

-- The queue. Producers INSERT; consumers claim with FOR UPDATE SKIP LOCKED and
-- DELETE (the ack) in the same transaction as their writes.
CREATE TABLE events_queue (
  id          bigserial PRIMARY KEY,
  site_id     text        NOT NULL,
  page_url    text        NOT NULL,
  lcp_ms      int         NOT NULL,
  session_id  text,
  ts          timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);

-- Minute-bucketed processed samples: source of truth for p75 and the trend.
CREATE TABLE lcp_samples (
  site_id      text        NOT NULL,
  page_url     text        NOT NULL,
  bucket_start timestamptz NOT NULL,  -- date_trunc('minute', ts)
  lcp_ms       int         NOT NULL
);
CREATE INDEX lcp_samples_key_idx ON lcp_samples (site_id, page_url, bucket_start);
CREATE INDEX lcp_samples_site_bucket_idx ON lcp_samples (site_id, bucket_start);

-- Rolling aggregates, written by the worker, read by the api.
CREATE TABLE page_aggregates (
  site_id     text   NOT NULL,
  page_url    text   NOT NULL,
  event_count bigint NOT NULL DEFAULT 0,
  p75_lcp_ms  int,
  last_seen   timestamptz,
  PRIMARY KEY (site_id, page_url)
);

-- SDK config, seeded. Config write path is out of scope (docs/design.md).
CREATE TABLE site_config (
  site_id       text  PRIMARY KEY,
  sampling_rate real  NOT NULL,
  experiments   jsonb NOT NULL
);

INSERT INTO site_config (site_id, sampling_rate, experiments) VALUES
  ('site-a', 1.0, '[
     {"id": "exp-hero-copy",   "name": "Hero copy rewrite",     "status": "active"},
     {"id": "exp-lazy-images", "name": "Lazy-load hero images", "status": "active"}
   ]'),
  ('site-b', 0.5, '[
     {"id": "exp-checkout-1step", "name": "One-step checkout", "status": "active"}
   ]');
