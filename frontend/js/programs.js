/**
 * Renders the "Our Programs" tabs from real program-service data (guideline:
 * microservices must be integrated with the frontend, not just demoed via Postman).
 * Groups sessions by day into Bootstrap tabs, sessions sorted by start time.
 */
(function () {
    "use strict";

    var PROGRAMS_ENDPOINT = window.PROGRAMS_ENDPOINT || "/api/programs";

    function escapeHtml(value) {
        var div = document.createElement("div");
        div.textContent = value == null ? "" : String(value);
        return div.innerHTML;
    }

    function formatTime(hhmmss) {
        if (!hhmmss) {
            return "";
        }
        var parts = hhmmss.split(":");
        var hour = parseInt(parts[0], 10);
        var minute = parts[1];
        var suffix = hour >= 12 ? "PM" : "AM";
        var hour12 = hour % 12 === 0 ? 12 : hour % 12;
        return hour12 + "." + minute + " " + suffix;
    }

    function formatDay(dayStr) {
        var date = new Date(dayStr);
        if (isNaN(date.getTime())) {
            return dayStr;
        }
        return date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
    }

    function trackTabClick(dayLabel) {
        if (window.NewEventAnalytics) {
            window.NewEventAnalytics.track("click", { target: "program_day_tab", section: "program", day: dayLabel });
        }
    }

    function render(programs) {
        var tabNav = document.getElementById("programTabs");
        var tabContent = document.getElementById("programTabContent");
        if (!tabNav || !tabContent) {
            return;
        }

        tabNav.innerHTML = "";
        tabContent.innerHTML = "";

        if (!programs.length) {
            tabContent.innerHTML = "<p>Programme details will be published soon.</p>";
            return;
        }

        var byDay = {};
        var days = [];
        programs.forEach(function (p) {
            if (!byDay[p.day]) {
                byDay[p.day] = [];
                days.push(p.day);
            }
            byDay[p.day].push(p);
        });
        days.sort();

        days.forEach(function (day, dayIndex) {
            var dayLabel = formatDay(day);
            var tabId = "program-day-" + dayIndex;

            var li = document.createElement("li");
            if (dayIndex === 0) {
                li.className = "active";
            }
            var link = document.createElement("a");
            link.href = "#" + tabId;
            link.setAttribute("role", "tab");
            link.setAttribute("data-toggle", "tab");
            link.textContent = dayLabel.toUpperCase();
            link.addEventListener("click", function () {
                trackTabClick(dayLabel);
            });
            li.appendChild(link);
            tabNav.appendChild(li);

            var pane = document.createElement("div");
            pane.setAttribute("role", "tabpanel");
            pane.className = "tab-pane" + (dayIndex === 0 ? " active" : "");
            pane.id = tabId;

            var sessions = byDay[day].slice().sort(function (a, b) {
                return (a.startTime || "").localeCompare(b.startTime || "");
            });

            sessions.forEach(function (session, i) {
                var row = document.createElement("div");
                row.className = "col-md-12 col-sm-12";
                row.innerHTML =
                    "<h6>" +
                    "<span><i class=\"fa fa-clock-o\"></i> " + formatTime(session.startTime) + " - " + formatTime(session.endTime) + "</span> " +
                    "<span><i class=\"fa fa-tag\"></i> " + escapeHtml(session.track) + "</span>" +
                    "</h6>" +
                    "<h3>" + escapeHtml(session.session) + "</h3>" +
                    "<h4>By " + escapeHtml(session.speakerName) + "</h4>";
                pane.appendChild(row);

                if (i < sessions.length - 1) {
                    var divider = document.createElement("div");
                    divider.className = "program-divider col-md-12 col-sm-12";
                    pane.appendChild(divider);
                }
            });

            tabContent.appendChild(pane);
        });
    }

    function loadPrograms() {
        var tabContent = document.getElementById("programTabContent");
        fetch(PROGRAMS_ENDPOINT)
            .then(function (res) {
                if (!res.ok) {
                    throw new Error("Failed to load programs");
                }
                return res.json();
            })
            .then(render)
            .catch(function () {
                if (tabContent) {
                    tabContent.innerHTML = "<p>Unable to load the programme right now — please refresh.</p>";
                }
            });
    }

    document.addEventListener("DOMContentLoaded", loadPrograms);
})();
