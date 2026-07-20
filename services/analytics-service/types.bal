public type AnalyticsEvent record {|
    string sessionId;
    string eventType;
    string timestamp;
    string page;
    json payload;
|};

public type CollectRequest record {|
    AnalyticsEvent[] events;
|};

public type ErrorDetail record {|
    string message;
|};
