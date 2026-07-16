public type RegistrationInput record {|
    string eventId;
    string name;
    string email;
    int ticketCount;
|};

public type Registration record {|
    *RegistrationInput;
    string registrationId;
    string createdAt;
|};

// Mirrors event-service's response shape for POST /events/{eventId}/reserve.
// Duplicated deliberately — each microservice owns its own view of the contract
// rather than sharing a library, so the two can evolve independently.
public type ReserveResponse record {|
    string eventId;
    int seatsAvailable;
    boolean belowThreshold;
|};

public type ErrorDetail record {|
    string message;
|};
