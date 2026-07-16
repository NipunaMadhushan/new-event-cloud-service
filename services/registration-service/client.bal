import ballerina/http;

configurable string eventServiceUrl = "http://localhost:8081";

final http:Client eventServiceClient = check new (eventServiceUrl);
