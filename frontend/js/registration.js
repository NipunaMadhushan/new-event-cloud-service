/**
 * Wires the "Register Here" form to the real backend: populates the event
 * dropdown from event-service and submits registrations to registration-service,
 * both reached through the same-origin /api/* proxy (see nginx.conf) so no
 * CORS setup is needed.
 */
(function () {
    "use strict";

    var EVENTS_ENDPOINT = window.EVENTS_ENDPOINT || "/api/events";
    var REGISTRATIONS_ENDPOINT = window.REGISTRATIONS_ENDPOINT || "/api/registrations";

    function loadEvents(selectEl) {
        fetch(EVENTS_ENDPOINT)
            .then(function (res) {
                if (!res.ok) {
                    throw new Error("Failed to load events");
                }
                return res.json();
            })
            .then(function (events) {
                events.forEach(function (evt) {
                    var option = document.createElement("option");
                    option.value = evt.eventId;
                    if (evt.seatsAvailable > 0) {
                        option.textContent = evt.title + " — " + evt.seatsAvailable + " seats left";
                    } else {
                        option.textContent = evt.title + " — SOLD OUT";
                        option.disabled = true;
                    }
                    selectEl.appendChild(option);
                });
            })
            .catch(function () {
                var option = document.createElement("option");
                option.textContent = "Unable to load events right now — please refresh";
                option.disabled = true;
                selectEl.appendChild(option);
            });
    }

    function setStatus(el, message, isError) {
        el.textContent = message;
        el.style.color = isError ? "#ff4d4f" : "#3adb76";
    }

    function bindRegisterForm() {
        var form = document.getElementById("registerForm");
        var select = document.getElementById("eventId");
        var status = document.getElementById("registerStatus");
        if (!form || !select || !status) {
            return;
        }

        loadEvents(select);

        form.addEventListener("submit", function (event) {
            event.preventDefault();

            var payload = {
                eventId: select.value,
                name: document.getElementById("regName").value.trim(),
                email: document.getElementById("regEmail").value.trim(),
                ticketCount: parseInt(document.getElementById("ticketCount").value, 10)
            };

            if (!payload.eventId) {
                setStatus(status, "Please select an event.", true);
                return;
            }
            if (!payload.ticketCount || payload.ticketCount < 1) {
                setStatus(status, "Ticket count must be at least 1.", true);
                return;
            }

            setStatus(status, "Submitting…", false);

            fetch(REGISTRATIONS_ENDPOINT, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(payload)
            })
                .then(function (res) {
                    return res.json().then(function (body) {
                        return { ok: res.ok, body: body };
                    });
                })
                .then(function (result) {
                    if (result.ok) {
                        setStatus(status, "You're registered! A confirmation would be sent to " + payload.email + ".", false);
                        form.reset();
                    } else {
                        setStatus(status, result.body.message || "Registration failed.", true);
                    }
                })
                .catch(function () {
                    setStatus(status, "Network error — please try again.", true);
                });
        });
    }

    document.addEventListener("DOMContentLoaded", bindRegisterForm);
})();
