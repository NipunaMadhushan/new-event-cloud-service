import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUser = "new_event";
configurable string dbPassword = "new_event_dev_pw";
configurable string dbName = "new_event";

// Ballerina's sql defaults (maxOpenConnections: 15, minIdleConnections: 15)
// assume one client per whole app talking to a roomy DB. We run several pods
// per service (blue+green slots, HPA), each with its own client, against a
// db.t3.micro whose connection budget is much smaller — the defaults alone
// pinned RDS at a flat ~72 idle connections regardless of actual traffic and
// started rejecting new ones ("remaining connection slots are reserved for
// rds_reserved role"). Capped tightly here so N pods stays affordable.
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
