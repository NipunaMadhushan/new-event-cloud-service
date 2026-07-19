const { SESClient, SendEmailCommand } = require("@aws-sdk/client-ses");

const ses = new SESClient({});

const SENDER_EMAIL = process.env.SENDER_EMAIL;
const RECIPIENT_EMAIL = process.env.RECIPIENT_EMAIL;

// Invoked by registration-service (via API Gateway HTTP API) whenever a
// reservation drops an event's seats below its threshold. Body: {eventId,
// eventName?, seatsAvailable}.
exports.handler = async (event) => {
  let body;
  try {
    body = typeof event.body === "string" ? JSON.parse(event.body) : event.body;
  } catch (err) {
    return jsonResponse(400, { message: "Invalid JSON body" });
  }

  const { eventId, eventName, seatsAvailable } = body ?? {};
  if (!eventId || typeof seatsAvailable !== "number") {
    return jsonResponse(400, { message: "eventId and seatsAvailable are required" });
  }

  const label = eventName ?? eventId;
  const subject = `Low seat availability: ${label}`;
  const text = `Event "${label}" (${eventId}) has only ${seatsAvailable} seat(s) remaining.`;

  try {
    await ses.send(new SendEmailCommand({
      Source: SENDER_EMAIL,
      Destination: { ToAddresses: [RECIPIENT_EMAIL] },
      Message: {
        Subject: { Data: subject },
        Body: { Text: { Data: text } }
      }
    }));
  } catch (err) {
    console.error("Failed to send SES notification", err);
    return jsonResponse(502, { message: "Failed to send notification email" });
  }

  return jsonResponse(200, { message: "Notification sent" });
};

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  };
}
