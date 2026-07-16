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
