CREATE TABLE IF NOT EXISTS web_events
(
    session_id String,
    event_type LowCardinality(String),
    event_timestamp DateTime64(3),
    page String,
    payload String,
    ingested_at DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (event_type, event_timestamp);
