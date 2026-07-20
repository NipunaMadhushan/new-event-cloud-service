import ballerina/http;

configurable string clickhouseHost = "localhost";
configurable int clickhousePort = 8123;
configurable string clickhouseUser = "default";
configurable string clickhousePassword = "clickhouse_dev_pw";

// Talks to ClickHouse's HTTP interface directly (same approach as the
// clickhouse-quicksight-export Lambda) rather than a native driver — there's
// no first-party Ballerina ClickHouse connector, and the HTTP interface lets
// ClickHouse itself parse the inserted JSON, so no manual SQL escaping here.
final http:Client clickhouseClient = check new (
    string `http://${clickhouseHost}:${clickhousePort}`,
    auth = {
        username: clickhouseUser,
        password: clickhousePassword
    }
);
