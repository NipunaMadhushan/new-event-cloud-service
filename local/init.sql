CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS events (
    event_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title             TEXT NOT NULL,
    venue             TEXT NOT NULL,
    event_datetime    TIMESTAMPTZ NOT NULL,
    ticket_price      NUMERIC(10, 2) NOT NULL,
    capacity          INTEGER NOT NULL CHECK (capacity >= 0),
    seats_available   INTEGER NOT NULL CHECK (seats_available >= 0)
);

CREATE TABLE IF NOT EXISTS programs (
    program_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id      UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    day           DATE NOT NULL,
    track         TEXT NOT NULL,
    session       TEXT NOT NULL,
    speaker_name  TEXT NOT NULL,
    start_time    TIME NOT NULL,
    end_time      TIME NOT NULL
);

CREATE TABLE IF NOT EXISTS registrations (
    registration_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id         UUID NOT NULL REFERENCES events(event_id),
    name             TEXT NOT NULL,
    email            TEXT NOT NULL,
    ticket_count     INTEGER NOT NULL CHECK (ticket_count > 0),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sample data for local dev/testing
INSERT INTO events (title, venue, event_datetime, ticket_price, capacity, seats_available)
VALUES ('Cloud Native Summit', 'Aberdeen Exhibition Centre', '2026-09-10 09:00:00+01', 49.99, 200, 12)
ON CONFLICT DO NOTHING;

INSERT INTO events (title, venue, event_datetime, ticket_price, capacity, seats_available)
VALUES ('K8s Workshop', 'Robert Gordon University', '2026-10-01 10:00:00+01', 19.99, 50, 50)
ON CONFLICT DO NOTHING;

INSERT INTO programs (event_id, day, track, session, speaker_name, start_time, end_time)
SELECT event_id, '2026-09-10'::date, 'Cloud Computing Track', 'Introduction to Kubernetes', 'Jenny Green', '09:00'::time, '10:00'::time FROM events WHERE title = 'Cloud Native Summit'
UNION ALL
SELECT event_id, '2026-09-10'::date, 'DevOps Track', 'CI/CD with GitHub Actions', 'Johnathan Mark', '10:15'::time, '11:15'::time FROM events WHERE title = 'Cloud Native Summit'
UNION ALL
SELECT event_id, '2026-09-10'::date, 'Security Track', 'Securing Cloud Workloads', 'Elite Hamilton', '11:30'::time, '12:30'::time FROM events WHERE title = 'Cloud Native Summit'
UNION ALL
SELECT event_id, '2026-09-11'::date, 'Cloud Computing Track', 'Serverless Patterns on AWS', 'David Yoon', '09:00'::time, '10:00'::time FROM events WHERE title = 'Cloud Native Summit'
UNION ALL
SELECT event_id, '2026-09-11'::date, 'Data Track', 'Real-Time Analytics with ClickHouse', 'Je Mary Lee', '10:15'::time, '11:15'::time FROM events WHERE title = 'Cloud Native Summit'
UNION ALL
SELECT event_id, '2026-10-01'::date, 'Cloud Computing Track', 'Blue-Green Deployments on EKS', 'Michael Walker', '09:30'::time, '10:30'::time FROM events WHERE title = 'K8s Workshop'
UNION ALL
SELECT event_id, '2026-10-01'::date, 'Observability Track', 'Metrics, Logs & Traces with Grafana', 'Cherry Stella', '10:45'::time, '11:45'::time FROM events WHERE title = 'K8s Workshop';
