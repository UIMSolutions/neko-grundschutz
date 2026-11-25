// Grundschutz web GUI: theme toggle and snackbar messages (also for htmx HX-Trigger events).
(function () {
  "use strict";

  function storedTheme() {
    try { return localStorage.getItem("gs-theme"); } catch (e) { return null; }
  }
  function applyTheme(mode) {
    var dark = mode ? mode === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches;
    document.body.classList.toggle("dark", dark);
    document.body.classList.toggle("light", !dark);
  }
  window.gsToggleTheme = function () {
    var next = document.body.classList.contains("dark") ? "light" : "dark";
    try { localStorage.setItem("gs-theme", next); } catch (e) { /* private mode */ }
    applyTheme(next);
  };

  var timer;
  function snackbar(text, isError) {
    var el = document.getElementById("gs-snackbar");
    if (!el) {
      el = document.createElement("div");
      el.id = "gs-snackbar";
      el.className = "snackbar";
      el.setAttribute("role", "status");
      document.body.appendChild(el);
    }
    el.textContent = text;
    el.classList.toggle("error", !!isError);
    el.classList.add("active");
    clearTimeout(timer);
    timer = setTimeout(function () { el.classList.remove("active"); }, isError ? 8000 : 4000);
  }
  window.gsSnackbar = snackbar;

  // messages rendered by the server (?msg=) are shown once, then removed from the URL
  function showServerMessages() {
    var m = document.querySelector("[data-gs-message]");
    if (m) { snackbar(m.getAttribute("data-gs-message"), false); m.remove(); }
    var url = new URL(window.location.href);
    if (url.searchParams.has("msg")) {
      url.searchParams.delete("msg");
      history.replaceState(history.state, "", url.pathname + (url.search || "") + url.hash);
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyTheme(storedTheme());
    showServerMessages();
  });
  document.addEventListener("htmx:afterSettle", showServerMessages);
  document.addEventListener("gs:message", function (e) { snackbar(e.detail.text, false); });
  document.addEventListener("gs:error", function (e) { snackbar(e.detail.text, true); });
  document.addEventListener("htmx:responseError", function (e) {
    snackbar("Fehler " + e.detail.xhr.status + " – bitte Seite neu laden", true);
  });
  document.addEventListener("htmx:sendError", function () {
    snackbar("Server nicht erreichbar", true);
  });
  // open <dialog> elements: <button data-dialog="#id">
  document.addEventListener("click", function (e) {
    var t = e.target.closest("[data-dialog]");
    if (!t) return;
    var d = document.querySelector(t.getAttribute("data-dialog"));
    if (d) { e.preventDefault(); d.open ? d.close() : d.showModal(); }
  });
})();
