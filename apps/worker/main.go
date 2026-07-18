// pulse worker — queue consumer. Contract: apps/worker/SPEC.md.
// Claim → persist samples → upsert aggregates → delete (ack), all in one tx.
package main

import (
	"context"
	"log"
	"os"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"
)

const (
	batchSize  = 500
	idleSleep  = 500 * time.Millisecond
	maxBackoff = 10 * time.Second
)

const upsertSQL = `
INSERT INTO page_aggregates (site_id, page_url, event_count, p75_lcp_ms, last_seen)
VALUES ($1, $2, $3, (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY lcp_ms)
                     FROM lcp_samples WHERE site_id=$1 AND page_url=$2
                       AND bucket_start > now() - interval '60 minutes'), $4)
ON CONFLICT (site_id, page_url) DO UPDATE SET
  event_count = page_aggregates.event_count + EXCLUDED.event_count,
  p75_lcp_ms  = EXCLUDED.p75_lcp_ms,
  last_seen   = GREATEST(page_aggregates.last_seen, EXCLUDED.last_seen)`

type event struct {
	id      int64
	siteID  string
	pageURL string
	lcpMS   int
	ts      time.Time
}

func main() {
	log.SetOutput(os.Stdout)
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		log.Fatal(`level=fatal msg="DATABASE_URL not set"`)
	}
	log.Printf("level=info msg=\"worker started\" batch_size=%d", batchSize)

	ctx := context.Background()
	backoff := idleSleep
	var conn *pgx.Conn
	for {
		if conn == nil || conn.IsClosed() {
			c, err := pgx.Connect(ctx, url)
			if err != nil {
				log.Printf("level=error msg=connect_failed err=%q backoff=%s", err, backoff)
				time.Sleep(backoff)
				backoff = min(backoff*2, maxBackoff)
				continue
			}
			conn = c
			log.Printf("level=info msg=connected")
		}
		n, err := processBatch(ctx, conn)
		if err != nil {
			log.Printf("level=error msg=batch_failed err=%q backoff=%s", err, backoff)
			time.Sleep(backoff)
			backoff = min(backoff*2, maxBackoff)
			continue
		}
		backoff = idleSleep
		if n < batchSize { // not a full batch: no backlog, idle briefly. Full: drain mode.
			time.Sleep(idleSleep)
		}
	}
}

func processBatch(ctx context.Context, conn *pgx.Conn) (int, error) {
	start := time.Now()
	tx, err := conn.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx) // no-op after Commit; the rollback-on-any-error guarantee

	rows, err := tx.Query(ctx,
		`SELECT id, site_id, page_url, lcp_ms, ts FROM events_queue
		 ORDER BY id LIMIT $1 FOR UPDATE SKIP LOCKED`, batchSize)
	if err != nil {
		return 0, err
	}
	events, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (event, error) {
		var e event
		err := row.Scan(&e.id, &e.siteID, &e.pageURL, &e.lcpMS, &e.ts)
		return e, err
	})
	if err != nil {
		return 0, err
	}
	if len(events) == 0 {
		return 0, nil
	}

	_, err = tx.CopyFrom(ctx, pgx.Identifier{"lcp_samples"},
		[]string{"site_id", "page_url", "bucket_start", "lcp_ms"},
		pgx.CopyFromSlice(len(events), func(i int) ([]any, error) {
			e := events[i]
			return []any{e.siteID, e.pageURL, e.ts.Truncate(time.Minute), e.lcpMS}, nil
		}))
	if err != nil {
		return 0, err
	}

	type agg struct {
		count int
		maxTS time.Time
	}
	byKey := map[[2]string]*agg{}
	ids := make([]int64, len(events))
	for i, e := range events {
		ids[i] = e.id
		k := [2]string{e.siteID, e.pageURL}
		a := byKey[k]
		if a == nil {
			a = &agg{}
			byKey[k] = a
		}
		a.count++
		if e.ts.After(a.maxTS) {
			a.maxTS = e.ts
		}
	}
	keys := make([][2]string, 0, len(byKey))
	for k := range byKey {
		keys = append(keys, k)
	}
	// Sorted upserts: replicas lock page_aggregates rows in the same order → no deadlocks.
	sort.Slice(keys, func(i, j int) bool {
		if keys[i][0] != keys[j][0] {
			return keys[i][0] < keys[j][0]
		}
		return keys[i][1] < keys[j][1]
	})
	for _, k := range keys {
		a := byKey[k]
		if _, err := tx.Exec(ctx, upsertSQL, k[0], k[1], a.count, a.maxTS); err != nil {
			return 0, err
		}
	}

	if _, err := tx.Exec(ctx, `DELETE FROM events_queue WHERE id = ANY($1)`, ids); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	log.Printf("level=info msg=batch_done batch_size=%d pages=%d duration_ms=%d",
		len(events), len(keys), time.Since(start).Milliseconds())
	return len(events), nil
}
