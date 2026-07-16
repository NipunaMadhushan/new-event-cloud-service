/**
 * Lightweight first-party analytics for the New Event site.
 * No external SDK — batches events client-side and flushes them via
 * navigator.sendBeacon (falling back to fetch keepalive) to the
 * analytics-service, which streams them into ClickHouse.
 *
 * Captures three differentiated, event-specific metric families:
 *   1. session_start      — traffic attribution (referrer/UTM/landing section)
 *   2. cta_click           — registration conversion funnel + video engagement
 *   3. section_engagement  — per-section dwell time + Our Programs track views
 */
(function () {
    "use strict";

    var ENDPOINT = window.ANALYTICS_ENDPOINT || "/api/analytics/collect";
    var FLUSH_INTERVAL_MS = 5000;
    var MIN_DWELL_MS = 1000;

    var SESSION_KEY = "newEvent.sessionId";
    var sessionId = getOrCreateSessionId();

    var queue = [];

    function getOrCreateSessionId() {
        try {
            var existing = window.sessionStorage.getItem(SESSION_KEY);
            if (existing) {
                return existing;
            }
            var id = generateId();
            window.sessionStorage.setItem(SESSION_KEY, id);
            return id;
        } catch (e) {
            // sessionStorage unavailable (e.g. privacy mode) — fall back to an in-memory id.
            return generateId();
        }
    }

    function generateId() {
        if (window.crypto && window.crypto.randomUUID) {
            return window.crypto.randomUUID();
        }
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
            var r = (Math.random() * 16) | 0;
            var v = c === "x" ? r : (r & 0x3) | 0x8;
            return v.toString(16);
        });
    }

    function track(eventType, payload) {
        queue.push({
            sessionId: sessionId,
            eventType: eventType,
            timestamp: new Date().toISOString(),
            page: window.location.pathname,
            payload: payload || {}
        });
        if (queue.length >= 20) {
            flush();
        }
    }

    function flush(useBeaconOnUnload) {
        if (queue.length === 0) {
            return;
        }
        var batch = queue;
        queue = [];
        var body = JSON.stringify({ events: batch });

        if (useBeaconOnUnload && navigator.sendBeacon) {
            var blob = new Blob([body], { type: "application/json" });
            navigator.sendBeacon(ENDPOINT, blob);
            return;
        }

        fetch(ENDPOINT, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: body,
            keepalive: true
        }).catch(function () {
            // Best-effort telemetry — a failed flush should never affect the page.
        });
    }

    // ---- 1. Session / attribution ----------------------------------------

    function captureSessionStart() {
        var params = new URLSearchParams(window.location.search);
        track("session_start", {
            referrer: document.referrer || "direct",
            utmSource: params.get("utm_source"),
            utmMedium: params.get("utm_medium"),
            utmCampaign: params.get("utm_campaign"),
            landingHash: window.location.hash || null,
            viewport: window.innerWidth + "x" + window.innerHeight,
            userAgent: navigator.userAgent
        });
    }

    // ---- 2. CTA conversion funnel + video engagement ----------------------

    function bindCtaTracking() {
        var heroRegisterBtn = document.querySelector("#intro a.btn-danger[href='#register']");
        if (heroRegisterBtn) {
            heroRegisterBtn.addEventListener("click", function () {
                track("cta_click", { target: "register_hero_button", section: "intro" });
            });
        }

        var navRegisterLink = document.querySelector(".navbar-nav a[href='#register']");
        if (navRegisterLink) {
            navRegisterLink.addEventListener("click", function () {
                track("cta_click", { target: "register_nav_link", section: "navbar" });
            });
        }

        var registerForm = document.querySelector("#register form");
        if (registerForm) {
            registerForm.addEventListener("submit", function (event) {
                event.preventDefault();
                track("cta_click", { target: "register_form_submit", section: "register" });
                showRegisterThankYou(registerForm);
            });
        }
    }

    function showRegisterThankYou(form) {
        var notice = document.createElement("p");
        notice.className = "analytics-thank-you";
        notice.style.color = "#fff";
        notice.textContent = "Thanks! This demo form does not submit anywhere — your interest was recorded.";
        form.appendChild(notice);
    }

    function bindVideoTracking() {
        var iframe = document.getElementById("promo-video");
        if (!iframe || !window.YT) {
            return;
        }
        var played = false;
        new window.YT.Player("promo-video", {
            events: {
                onStateChange: function (event) {
                    if (event.data === window.YT.PlayerState.PLAYING && !played) {
                        played = true;
                        track("cta_click", { target: "video_play", section: "video" });
                    }
                }
            }
        });
    }

    function loadYouTubeApiThenBindVideo() {
        if (!document.getElementById("promo-video")) {
            return;
        }
        window.onYouTubeIframeAPIReady = bindVideoTracking;
        var tag = document.createElement("script");
        tag.src = "https://www.youtube.com/iframe_api";
        tag.onerror = function () {
            // No network access to YouTube (e.g. offline dev/test) — skip video tracking silently.
        };
        var firstScript = document.getElementsByTagName("script")[0];
        firstScript.parentNode.insertBefore(tag, firstScript);
    }

    // ---- 3. Section engagement: dwell time + Our Programs track views -----

    function bindSectionDwellTracking() {
        if (!("IntersectionObserver" in window)) {
            return;
        }
        var enteredAt = {};

        var observer = new IntersectionObserver(
            function (entries) {
                entries.forEach(function (entry) {
                    var sectionId = entry.target.id;
                    if (entry.isIntersecting) {
                        enteredAt[sectionId] = Date.now();
                    } else if (enteredAt[sectionId]) {
                        recordDwell(sectionId, enteredAt[sectionId]);
                        delete enteredAt[sectionId];
                    }
                });
            },
            { threshold: 0.5 }
        );

        document.querySelectorAll("section[id]").forEach(function (section) {
            observer.observe(section);
        });

        window.addEventListener("pagehide", function () {
            Object.keys(enteredAt).forEach(function (sectionId) {
                recordDwell(sectionId, enteredAt[sectionId]);
            });
            flush(true);
        });

        function recordDwell(sectionId, startedAt) {
            var dwellMs = Date.now() - startedAt;
            if (dwellMs >= MIN_DWELL_MS) {
                track("section_engagement", { metric: "dwell_time", sectionId: sectionId, dwellMs: dwellMs });
            }
        }
    }

    function bindProgramTrackTracking() {
        document.querySelectorAll("#program a[data-toggle='tab']").forEach(function (tabLink) {
            tabLink.addEventListener("click", function () {
                var trackName = (tabLink.textContent || "").trim();
                track("section_engagement", { metric: "track_view", track: trackName });
            });
        });
    }

    // ---- Boot ---------------------------------------------------------------

    document.addEventListener("DOMContentLoaded", function () {
        captureSessionStart();
        bindCtaTracking();
        bindSectionDwellTracking();
        bindProgramTrackTracking();
        loadYouTubeApiThenBindVideo();
    });

    setInterval(function () {
        flush(false);
    }, FLUSH_INTERVAL_MS);

    document.addEventListener("visibilitychange", function () {
        if (document.visibilityState === "hidden") {
            flush(true);
        }
    });
})();
