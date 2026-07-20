import ballerina/http;
import ballerina/lang.value;
import ballerina/log;
import ballerinax/jaeger as _;

configurable int servicePort = 8084;

listener http:Listener analyticsListener = new (servicePort);

// Both query strings are fixed/constant (no user input), so they're
// hand-encoded once here rather than pulling in the `ballerina/url` module.
const string INSERT_PATH = "/?query=INSERT%20INTO%20web_events%20FORMAT%20JSONEachRow&date_time_input_format=best_effort";
const string HEALTH_PATH = "/?query=SELECT%201";

service / on analyticsListener {

    resource function get healthz() returns http:Ok|http:ServiceUnavailable {
        http:Response|http:ClientError result = clickhouseClient->get(HEALTH_PATH);
        if result is http:ClientError {
            log:printError("ClickHouse health check failed", result);
            return <http:ServiceUnavailable>{body: {status: "DOWN"}};
        }
        return <http:Ok>{body: {status: "UP"}};
    }
}

service /analytics on analyticsListener {

    // Best-effort ingestion: analytics.js fires this via sendBeacon/fetch-keepalive
    // and never inspects the response, so failures here are logged, not surfaced
    // to the browser. Writes straight into ClickHouse's web_events table — see
    // helm/clickhouse/values.yaml for the schema.
    resource function post collect(@http:Payload CollectRequest req) returns http:Accepted|http:InternalServerError {
        if req.events.length() == 0 {
            return http:ACCEPTED;
        }

        string body = "";
        foreach AnalyticsEvent event in req.events {
            map<json> row = {
                "session_id": event.sessionId,
                "event_type": event.eventType,
                "event_timestamp": event.timestamp,
                "page": event.page,
                "payload": value:toJsonString(event.payload)
            };
            body += value:toJsonString(row) + "\n";
        }

        http:Response|http:ClientError result = clickhouseClient->post(INSERT_PATH, body, mediaType = "text/plain");
        if result is http:ClientError {
            log:printError("Failed to write analytics batch to ClickHouse", result);
            return <http:InternalServerError>{body: {message: "Failed to record events"}};
        }
        if result.statusCode >= 400 {
            var errorText = result.getTextPayload();
            log:printError(string `ClickHouse rejected analytics batch (status ${result.statusCode}): ${errorText is string ? errorText : "unknown"}`);
            return <http:InternalServerError>{body: {message: "Failed to record events"}};
        }
        return http:ACCEPTED;
    }
}
