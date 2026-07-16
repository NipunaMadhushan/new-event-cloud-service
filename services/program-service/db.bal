import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUser = "new_event";
configurable string dbPassword = "new_event_dev_pw";
configurable string dbName = "new_event";

final postgresql:Client dbClient = check new (
    host = dbHost,
    port = dbPort,
    username = dbUser,
    password = dbPassword,
    database = dbName
);
