public type ProgramInput record {|
    string eventId;
    string day;
    string track;
    string session;
    string speakerName;
    string startTime;
    string endTime;
|};

public type Program record {|
    *ProgramInput;
    string programId;
|};

public type ErrorDetail record {|
    string message;
|};
