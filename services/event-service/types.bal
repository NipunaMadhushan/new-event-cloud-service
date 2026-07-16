// Shape accepted on create/update — client never supplies eventId, that's DB-generated.
public type EventInput record {|
    string title;
    string venue;
    string eventDatetime;
    decimal ticketPrice;
    int capacity;
    int seatsAvailable;
|};

public type Event record {|
    *EventInput;
    string eventId;
|};

public type ReserveRequest record {|
    int ticketCount;
|};

public type ReserveResponse record {|
    string eventId;
    int seatsAvailable;
    boolean belowThreshold;
|};

public type ErrorDetail record {|
    string message;
|};
