import ballerina/http;
import ballerina/log;
import ballerina/sql;
import ballerinax/jaeger as _;
import ballerinax/prometheus as _;

configurable int servicePort = 8082;

listener http:Listener programListener = new (servicePort);

final sql:ParameterizedQuery PROGRAM_COLUMNS = `program_id as programId, event_id as eventId, day, track, session,
                        speaker_name as speakerName, start_time as startTime, end_time as endTime`;

function selectProgramQuery(sql:ParameterizedQuery whereClause) returns sql:ParameterizedQuery
    => sql:queryConcat(`SELECT `, PROGRAM_COLUMNS, ` FROM programs `, whereClause);

service / on programListener {

    resource function get healthz() returns http:Ok|http:ServiceUnavailable {
        int|sql:Error result = dbClient->queryRow(`SELECT 1`);
        if result is error {
            log:printError("Database health check failed", result);
            return <http:ServiceUnavailable>{body: {status: "DOWN"}};
        }
        return <http:Ok>{body: {status: "UP"}};
    }
}

service /programs on programListener {

    // Optional ?eventId= query filter — maps automatically from the query string.
    resource function get .(string? eventId) returns Program[]|http:InternalServerError {
        sql:ParameterizedQuery whereClause = eventId is string
            ? `WHERE event_id = ${eventId}::uuid ORDER BY day, start_time`
            : `ORDER BY day, start_time`;
        stream<Program, sql:Error?> resultStream = dbClient->query(selectProgramQuery(whereClause));
        Program[]|error programs = from Program p in resultStream
            select p;
        if programs is error {
            log:printError("Failed to list programs", programs);
            return <http:InternalServerError>{body: {message: "Failed to list programs"}};
        }
        return programs;
    }

    resource function get [string programId]() returns Program|http:NotFound|http:InternalServerError {
        Program|sql:Error result = dbClient->queryRow(selectProgramQuery(`WHERE program_id = ${programId}::uuid`));
        if result is sql:NoRowsError {
            return <http:NotFound>{body: {message: "Program not found"}};
        }
        if result is error {
            log:printError("Failed to fetch program", result);
            return <http:InternalServerError>{body: {message: "Failed to fetch program"}};
        }
        return result;
    }

    resource function post .(@http:Payload ProgramInput input) returns Program|http:BadRequest|http:InternalServerError {
        Program|sql:Error result = dbClient->queryRow(sql:queryConcat(`
            INSERT INTO programs (event_id, day, track, session, speaker_name, start_time, end_time)
            VALUES (${input.eventId}::uuid, ${input.day}::date, ${input.track}, ${input.session}, ${input.speakerName}, ${input.startTime}::time, ${input.endTime}::time)
            RETURNING `, PROGRAM_COLUMNS));
        if result is sql:Error {
            log:printError("Failed to create program", result);
            if result.message().includes("foreign key") {
                return <http:BadRequest>{body: {message: "eventId does not exist"}};
            }
            return <http:InternalServerError>{body: {message: "Failed to create program"}};
        }
        return result;
    }

    resource function put [string programId](@http:Payload ProgramInput input) returns Program|http:NotFound|http:BadRequest|http:InternalServerError {
        Program|sql:Error result = dbClient->queryRow(sql:queryConcat(`
            UPDATE programs
            SET event_id = ${input.eventId}::uuid, day = ${input.day}::date, track = ${input.track}, session = ${input.session},
                speaker_name = ${input.speakerName}, start_time = ${input.startTime}::time, end_time = ${input.endTime}::time
            WHERE program_id = ${programId}::uuid
            RETURNING `, PROGRAM_COLUMNS));
        if result is sql:NoRowsError {
            return <http:NotFound>{body: {message: "Program not found"}};
        }
        if result is sql:Error {
            log:printError("Failed to update program", result);
            if result.message().includes("foreign key") {
                return <http:BadRequest>{body: {message: "eventId does not exist"}};
            }
            return <http:InternalServerError>{body: {message: "Failed to update program"}};
        }
        return result;
    }

    resource function delete [string programId]() returns http:NoContent|http:NotFound|http:InternalServerError {
        sql:ExecutionResult|sql:Error result = dbClient->execute(`DELETE FROM programs WHERE program_id = ${programId}::uuid`);
        if result is error {
            log:printError("Failed to delete program", result);
            return <http:InternalServerError>{body: {message: "Failed to delete program"}};
        }
        if result.affectedRowCount == 0 {
            return <http:NotFound>{body: {message: "Program not found"}};
        }
        return http:NO_CONTENT;
    }
}
