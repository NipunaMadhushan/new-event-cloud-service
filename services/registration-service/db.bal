import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUser = "new_event";
configurable string dbPassword = "new_event_dev_pw";
configurable string dbName = "new_event";

// See event-service/db.bal for why this is capped explicitly — Ballerina's
// sql defaults (15 max / 15 min idle connections per client) exhausted
// db.t3.micro's connection budget once multiple pods/services were running.
final postgresql:Client dbClient = check new (
    host = dbHost,
    port = dbPort,
    username = dbUser,
    password = dbPassword,
    database = dbName,
    connectionPool = {
        maxOpenConnections: 3,
        minIdleConnections: 1,
        maxConnectionLifeTime: 1800
    }
);
