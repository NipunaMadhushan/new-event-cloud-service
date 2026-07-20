import ballerina/http;
import ballerina/log;
import ballerina/sql;
import ballerinax/jaeger as _;

configurable int servicePort = 8083;

listener http:Listener registrationListener = new (servicePort);

final sql:ParameterizedQuery REGISTRATION_COLUMNS = `registration_id as registrationId, event_id as eventId, name, email,
                        ticket_count as ticketCount, created_at as createdAt`;

function selectRegistrationQuery(sql:ParameterizedQuery whereClause) returns sql:ParameterizedQuery
    => sql:queryConcat(`SELECT `, REGISTRATION_COLUMNS, ` FROM registrations `, whereClause);

configurable string notifierUrl = "";

// Calls the API Gateway URL fronting the seat-threshold-notifier Lambda (§7.1 of
// the deployment guide). notifierUrl is blank until that Lambda exists, so this
// stays a no-op logger in local/dev until it's set via Helm.
function notifySeatsLow(string eventId, int seatsAvailable) {
    if notifierUrl == "" {
        log:printInfo(string `Seats low for event ${eventId}: ${seatsAvailable} remaining (notifierUrl not configured)`);
        return;
    }
    http:Client|error notifierClient = new (notifierUrl);
    if notifierClient is error {
        log:printError("Failed to create notifier HTTP client", notifierClient);
        return;
    }
    http:Response|http:ClientError result = notifierClient->post("/", {eventId, seatsAvailable});
    if result is http:ClientError {
        log:printError("Failed to notify seat-threshold Lambda", result);
    }
}

service / on registrationListener {

    resource function get healthz() returns http:Ok|http:ServiceUnavailable {
        int|sql:Error result = dbClient->queryRow(`SELECT 1`);
        if result is error {
            log:printError("Database health check failed", result);
            return <http:ServiceUnavailable>{body: {status: "DOWN"}};
        }
        return <http:Ok>{body: {status: "UP"}};
    }
}

service /registrations on registrationListener {

    resource function get .(string? eventId) returns Registration[]|http:InternalServerError {
        sql:ParameterizedQuery whereClause = eventId is string
            ? `WHERE event_id = ${eventId}::uuid ORDER BY created_at DESC`
            : `ORDER BY created_at DESC`;
        stream<Registration, sql:Error?> resultStream = dbClient->query(selectRegistrationQuery(whereClause));
        Registration[]|error registrations = from Registration r in resultStream
            select r;
        if registrations is error {
            log:printError("Failed to list registrations", registrations);
            return <http:InternalServerError>{body: {message: "Failed to list registrations"}};
        }
        return registrations;
    }

    resource function get [string registrationId]() returns Registration|http:NotFound|http:InternalServerError {
        Registration|sql:Error result = dbClient->queryRow(selectRegistrationQuery(`WHERE registration_id = ${registrationId}::uuid`));
        if result is sql:NoRowsError {
            return <http:NotFound>{body: {message: "Registration not found"}};
        }
        if result is error {
            log:printError("Failed to fetch registration", result);
            return <http:InternalServerError>{body: {message: "Failed to fetch registration"}};
        }
        return result;
    }

    // Reserves seats on event-service first, then persists the registration.
    // Known limitation (no distributed transaction/saga): if the DB insert below fails
    // after a successful reserve call, seats stay decremented with no matching
    // registration row. Acceptable for coursework scope — worth calling out explicitly
    // in the report's design-trade-offs / fault-tolerance discussion.
    resource function post .(@http:Payload RegistrationInput input) returns Registration|http:BadRequest|http:NotFound|http:InternalServerError {
        if input.ticketCount <= 0 {
            return <http:BadRequest>{body: {message: "ticketCount must be positive"}};
        }

        ReserveResponse|http:ClientError reserveResult = eventServiceClient->post(
            string `/events/${input.eventId}/reserve`,
            {ticketCount: input.ticketCount},
            targetType = ReserveResponse
        );

        if reserveResult is http:ApplicationResponseError {
            int statusCode = reserveResult.detail().statusCode;
            if statusCode == http:STATUS_NOT_FOUND {
                return <http:NotFound>{body: {message: "Event not found"}};
            }
            return <http:BadRequest>{body: {message: "Not enough seats available"}};
        }
        if reserveResult is http:ClientError {
            log:printError("Failed to reach event-service", reserveResult);
            return <http:InternalServerError>{body: {message: "Failed to reach event-service to reserve seats"}};
        }

        Registration|sql:Error saved = dbClient->queryRow(sql:queryConcat(`
            INSERT INTO registrations (event_id, name, email, ticket_count)
            VALUES (${input.eventId}::uuid, ${input.name}, ${input.email}, ${input.ticketCount})
            RETURNING `, REGISTRATION_COLUMNS));
        if saved is error {
            log:printError("Failed to save registration after reserving seats", saved);
            return <http:InternalServerError>{body: {message: "Failed to save registration"}};
        }

        if reserveResult.belowThreshold {
            notifySeatsLow(input.eventId, reserveResult.seatsAvailable);
        }

        return saved;
    }
}
