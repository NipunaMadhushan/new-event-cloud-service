import ballerina/http;
import ballerina/log;
import ballerina/sql;
import ballerinax/jaeger as _;
import ballerinax/prometheus as _;

configurable int servicePort = 8081;

listener http:Listener eventListener = new (servicePort);

final sql:ParameterizedQuery EVENT_COLUMNS = `event_id as eventId, title, venue, event_datetime as eventDatetime,
                        ticket_price as ticketPrice, capacity, seats_available as seatsAvailable`;

// sql:queryConcat splices ParameterizedQuery fragments together as raw SQL — a plain
// `${EVENT_COLUMNS}` interpolation would instead try to bind it as a query parameter.
function selectEventQuery(sql:ParameterizedQuery whereClause) returns sql:ParameterizedQuery
    => sql:queryConcat(`SELECT `, EVENT_COLUMNS, ` FROM events `, whereClause);

// Root-level health check — kept outside the /events base path so it reads as
// a plain /healthz probe endpoint for K8s liveness/readiness checks.
service / on eventListener {

    resource function get healthz() returns http:Ok|http:ServiceUnavailable {
        int|sql:Error result = dbClient->queryRow(`SELECT 1`);
        if result is error {
            log:printError("Database health check failed", result);
            return <http:ServiceUnavailable>{body: {status: "DOWN"}};
        }
        return <http:Ok>{body: {status: "UP"}};
    }
}

service /events on eventListener {

    resource function get .() returns Event[]|http:InternalServerError {
        stream<Event, sql:Error?> resultStream = dbClient->query(selectEventQuery(`ORDER BY event_datetime`));
        Event[]|error events = from Event e in resultStream
            select e;
        if events is error {
            log:printError("Failed to list events", events);
            return <http:InternalServerError>{body: {message: "Failed to list events"}};
        }
        return events;
    }

    resource function get [string eventId]() returns Event|http:NotFound|http:InternalServerError {
        Event|sql:Error result = dbClient->queryRow(selectEventQuery(`WHERE event_id = ${eventId}::uuid`));
        if result is sql:NoRowsError {
            return <http:NotFound>{body: {message: "Event not found"}};
        }
        if result is error {
            log:printError("Failed to fetch event", result);
            return <http:InternalServerError>{body: {message: "Failed to fetch event"}};
        }
        return result;
    }

    resource function post .(@http:Payload EventInput input) returns Event|http:InternalServerError {
        Event|sql:Error result = dbClient->queryRow(sql:queryConcat(`
            INSERT INTO events (title, venue, event_datetime, ticket_price, capacity, seats_available)
            VALUES (${input.title}, ${input.venue}, ${input.eventDatetime}::timestamptz, ${input.ticketPrice}, ${input.capacity}, ${input.seatsAvailable})
            RETURNING `, EVENT_COLUMNS));
        if result is error {
            log:printError("Failed to create event", result);
            return <http:InternalServerError>{body: {message: "Failed to create event"}};
        }
        return result;
    }

    resource function put [string eventId](@http:Payload EventInput input) returns Event|http:NotFound|http:InternalServerError {
        Event|sql:Error result = dbClient->queryRow(sql:queryConcat(`
            UPDATE events
            SET title = ${input.title}, venue = ${input.venue}, event_datetime = ${input.eventDatetime}::timestamptz,
                ticket_price = ${input.ticketPrice}, capacity = ${input.capacity}, seats_available = ${input.seatsAvailable}
            WHERE event_id = ${eventId}::uuid
            RETURNING `, EVENT_COLUMNS));
        if result is sql:NoRowsError {
            return <http:NotFound>{body: {message: "Event not found"}};
        }
        if result is error {
            log:printError("Failed to update event", result);
            return <http:InternalServerError>{body: {message: "Failed to update event"}};
        }
        return result;
    }

    resource function delete [string eventId]() returns http:NoContent|http:NotFound|http:Conflict|http:InternalServerError {
        sql:ExecutionResult|sql:Error result = dbClient->execute(`DELETE FROM events WHERE event_id = ${eventId}::uuid`);
        if result is error {
            if result.message().includes("foreign key") {
                return <http:Conflict>{body: {message: "Cannot delete event with existing programs or registrations"}};
            }
            log:printError("Failed to delete event", result);
            return <http:InternalServerError>{body: {message: "Failed to delete event"}};
        }
        if result.affectedRowCount == 0 {
            return <http:NotFound>{body: {message: "Event not found"}};
        }
        return http:NO_CONTENT;
    }

    // Atomically decrements seatsAvailable in a single conditional UPDATE so concurrent
    // registrations can't oversell seats — no explicit transaction/locking needed.
    resource function post [string eventId]/reserve(@http:Payload ReserveRequest req) returns ReserveResponse|http:NotFound|http:BadRequest|http:InternalServerError {
        if req.ticketCount <= 0 {
            return <http:BadRequest>{body: {message: "ticketCount must be positive"}};
        }

        record {|int seatsAvailable;|}|sql:Error updated = dbClient->queryRow(`
            UPDATE events
            SET seats_available = seats_available - ${req.ticketCount}
            WHERE event_id = ${eventId}::uuid AND seats_available >= ${req.ticketCount}
            RETURNING seats_available AS seatsAvailable
        `);

        if updated is sql:NoRowsError {
            Event|sql:Error existing = dbClient->queryRow(selectEventQuery(`WHERE event_id = ${eventId}::uuid`));
            if existing is sql:NoRowsError {
                return <http:NotFound>{body: {message: "Event not found"}};
            }
            return <http:BadRequest>{body: {message: "Not enough seats available"}};
        }
        if updated is error {
            log:printError("Failed to reserve seats", updated);
            return <http:InternalServerError>{body: {message: "Failed to reserve seats"}};
        }

        return {eventId, seatsAvailable: updated.seatsAvailable, belowThreshold: updated.seatsAvailable < 10};
    }
}
