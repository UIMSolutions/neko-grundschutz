/// vibe.d HTTP listener: wires OData, web GUI, static files and health endpoint.
module uim.myfiori.presentation.http.server;

@safe:

import std.file : exists;
import vibe.core.log;
import vibe.data.json;
import vibe.http.fileserver;
import vibe.http.router : URLRouter;
import vibe.http.server;

import uim.myfiori.bootstrap;
import uim.myfiori.presentation.http.exchange;
import uim.myfiori.presentation.odata.service;
import uim.myfiori.presentation.web.controller;

/// Builds the router with all HTTP adapters.
URLRouter buildRouter(DApplicationContainer app) {
  auto router = new URLRouter;

  router.get("/health", (HTTPServerRequest req, HTTPServerResponse res) @safe {
    auto j = Json.emptyObject;
    j["status"] = "UP";
    j["storage"] = app.storage.describe;
    j["auth"] = app.config.authEnabled;
    res.writeJsonBody(j);
  });

  new DODataService(app).register(router);
  new DExchangeApi(app).register(router);
  new DWebController(app).register(router);

  if (app.config.publicDir.exists) {
    auto pub = new HTTPFileServerSettings("/public");
    router.get("/public/*", serveStaticFiles(app.config.publicDir ~ "/", pub));
  }
  // local development: serve the Fiori app (in BTP the approuter serves it)
  if (app.config.frontendDir.exists) {
    auto ui = new HTTPFileServerSettings("/ui");
    router.get("/ui", (HTTPServerRequest req, HTTPServerResponse res) @safe { res.redirect("/ui/index.html"); });
    router.get("/ui/*", serveStaticFiles(app.config.frontendDir ~ "/", ui));
  }
  return router;
}

/// Starts listening; returns the listener (call stopListening() to shut down).
HTTPListener startServer(DApplicationContainer app) {
  auto settings = new HTTPServerSettings;
  settings.port = app.config.port;
  settings.bindAddresses = [app.config.host];
  settings.serverString = "grundschutz";
  settings.maxRequestSize = app.config.maxUploadMegabytes * 1024 * 1024;
  settings.errorPageHandler = (HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error) @safe {
    res.writeBody("Error " ~ () @trusted { import std.conv : to; return error.code.to!string; }() ~ ": " ~ error.message, "text/plain");
  };
  auto listener = listenHTTP(settings, buildRouter(app));
  logInfo("Grundschutz backend listening on http://%s:%d (storage: %s, auth: %s)",
      app.config.host, app.config.port, app.storage.describe, app.config.authEnabled);
  logInfo("  Web GUI : http://%s:%d/web", app.config.host, app.config.port);
  logInfo("  OData v4: http://%s:%d/odata/v4/grundschutz/$metadata", app.config.host, app.config.port);
  logInfo("  Fiori   : http://%s:%d/ui/index.html", app.config.host, app.config.port);
  return listener;
}
