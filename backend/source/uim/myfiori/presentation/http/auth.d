/// Request authentication / authorization helpers for HTTP adapters.
module uim.myfiori.presentation.http.auth;

@safe:

import std.datetime.systime : Clock;
import std.string : indexOf, toLower;
import vibe.http.common : HTTPMethod;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import uim.myfiori.bootstrap : DApplicationContainer;
import uim.myfiori.domain.exceptions : EntityNotFoundException;
import uim.myfiori.infrastructure.security;
import uim.myfiori.presentation.http.errors;

/// Session keys of a login session.
enum SessionKeys : string {
  userId = "gs.userId",
  lastSeen = "gs.lastSeen",
}

/**
 * Identifies the caller:
 *  - XSUAA bound: validated bearer token,
 *  - local login enabled: user of the session cookie (reloaded on every request, so role
 *    changes and deactivation take effect immediately),
 *  - otherwise the local principal with all scopes (development / desktop).
 * Throws AuthenticationException if nobody is logged in.
 */
Principal authenticate(DApplicationContainer app, HTTPServerRequest req, HTTPServerResponse res = null) {
  auto guard = app.authGuard;
  if (!guard.loginEnabled) return guard.authenticate(req.headers.get("Authorization", ""));
  auto p = sessionPrincipal(app, req, res);
  if (p.userName.length == 0) throw new AuthenticationException("Nicht angemeldet");
  return p;
}

/// Authenticates the request and checks the scope; throws on failure.
Principal authorize(DApplicationContainer app, HTTPServerRequest req, string scope_, HTTPServerResponse res = null) {
  auto principal = authenticate(app, req, res);
  if (!principal.hasScope(scope_))
    throw new ForbiddenException("Keine Berechtigung (Rolle '" ~ scope_ ~ "' erforderlich)");
  return principal;
}

/// Principal of the current login session, Principal.init if there is none (or it expired).
Principal sessionPrincipal(DApplicationContainer app, HTTPServerRequest req, HTTPServerResponse res = null) @trusted {
  if (!req.session) return Principal.init;
  auto id = req.session.get!string(SessionKeys.userId, "");
  if (id.length == 0) return Principal.init;
  auto now = Clock.currTime.toUnixTime;
  auto lastSeen = req.session.get!long(SessionKeys.lastSeen, 0);
  if (now - lastSeen > app.authGuard.sessionMinutes * 60L) {
    endSession(req, res);
    return Principal.init;
  }
  try {
    auto u = app.users.get(id);
    if (!u.active) { endSession(req, res); return Principal.init; }
    req.session.set(SessionKeys.lastSeen, now);
    return Principal(u.userName, u.email, u.scopes.dup, u.ID, u.displayName);
  } catch (EntityNotFoundException) {
    endSession(req, res);
    return Principal.init;
  }
}

/// Starts a fresh session for the user (new id: prevents session fixation).
void beginSession(HTTPServerRequest req, HTTPServerResponse res, string userId) @trusted {
  if (req.session) res.terminateSession();
  req.session = res.startSession();
  req.session.set(SessionKeys.userId, userId);
  req.session.set(SessionKeys.lastSeen, Clock.currTime.toUnixTime);
}

void endSession(HTTPServerRequest req, HTTPServerResponse res) @trusted {
  if (!req.session) return;
  if (res !is null) res.terminateSession();
  else req.session.remove(SessionKeys.userId);
  req.session = typeof(req.session).init;
}

/**
 * Cross-site request protection for cookie / unauthenticated mode. Without a bearer token any
 * web page could otherwise POST to http://127.0.0.1:8080 (e.g. /api/restore). Writing requests
 * are rejected when the browser reports a foreign Origin or a cross-site fetch. With XSUAA
 * authentication the bearer token (which browsers never attach automatically) prevents CSRF.
 */
void ensureNotCrossSite(DAuthGuard guard, HTTPServerRequest req) @trusted {
  if (guard.enabled) return;
  if (req.method == HTTPMethod.GET || req.method == HTTPMethod.HEAD || req.method == HTTPMethod.OPTIONS) return;
  auto origin = req.headers.get("Origin", "");
  if (origin.length && origin != "null") {
    auto p = origin.indexOf("://");
    auto originHost = p >= 0 ? origin[p + 3 .. $] : origin;
    if (originHost.toLower != req.headers.get("Host", "").toLower)
      throw new ForbiddenException("Cross-site request rejected (Origin " ~ origin ~ ")");
  } else if (origin == "null" || req.headers.get("Sec-Fetch-Site", "") == "cross-site") {
    throw new ForbiddenException("Cross-site request rejected");
  }
}
