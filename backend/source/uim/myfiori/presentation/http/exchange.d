/**
 * HTTP API for file based data exchange (not part of the OData model):
 *
 *   GET  /api/export/{entity}?format=csv|json&projectId=&delimiter=comma|semicolon|tab   Viewer
 *   POST /api/import/{entity}?format=auto|csv|json&mode=create|upsert|skip&dryRun=true&projectId=   Editor
 *   GET  /api/projects/{id}/export                                       Viewer
 *   POST /api/projects/import?newIds=true&dryRun=true                    Editor
 *   GET  /api/backup                       download a complete backup    Admin
 *   POST /api/restore?dryRun=true          restore from request body     Admin
 *   GET  /api/backups                      server-side backups           Admin
 *   POST /api/backups?label=               create server-side backup     Admin
 *   GET  /api/backups/{name}               download server-side backup   Admin
 *   POST /api/backups/{name}/restore?dryRun=true                         Admin
 */
module uim.myfiori.presentation.http.exchange;

@safe:

import std.conv : to;
import std.datetime.systime : Clock;
import std.string : replace;
import vibe.core.log;
import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server;

import uim.myfiori.bootstrap;
import uim.myfiori.infrastructure.security : requiredScope;
import uim.myfiori.presentation.http.auth;
import uim.myfiori.presentation.http.errors;

class DExchangeApi {
  private DApplicationContainer _app;

  this(DApplicationContainer app) { _app = app; }

  void register(URLRouter r) {
    r.get("/api/export/:entity", &guarded!(exportEntities, "Viewer"));
    r.post("/api/import/:entity", &guarded!(importEntities, "Editor"));
    r.get("/api/projects/:id/export", &guarded!(exportProject, "Viewer"));
    r.post("/api/projects/import", &guarded!(importProject, "Editor"));
    r.get("/api/backup", &guarded!(downloadBackup, "Admin"));
    r.post("/api/restore", &guarded!(restoreUpload, "Admin"));
    r.get("/api/backups", &guarded!(listBackups, "Admin"));
    r.post("/api/backups", &guarded!(createBackup, "Admin"));
    r.get("/api/backups/:name", &guarded!(downloadServerBackup, "Admin"));
    r.post("/api/backups/:name/restore", &guarded!(restoreServerBackup, "Admin"));
  }

  // -------------------------------------------------------------- handlers

  private void exportEntities(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto entity = req.params["entity"];
    auto format = req.query.get("format", "json");
    auto delimiter = req.query.get("delimiter", ",");
    auto content = _app.exchange.exportEntities(entity, format, req.query.get("projectId", ""), delimiterOf(delimiter));
    auto bom = format == "csv" && req.query.get("bom", "true") != "false";
    download(res, (bom ? "\xEF\xBB\xBF" : "") ~ content, fileName(entity, format), contentType(format));
  }

  private void importEntities(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto report = _app.exchange.importEntities(req.params["entity"], req.query.get("format", "auto"), body_(req),
        req.query.get("mode", "create"), flag(req, "dryRun"), req.query.get("projectId", ""));
    res.writeJsonBody(serializeToJson(report), report.failed ? HTTPStatus.unprocessableEntity : HTTPStatus.ok);
  }

  private void exportProject(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto id = req.params["id"];
    auto name = _app.projects.get(id).name;
    download(res, _app.exchange.exportProject(id), "grundschutz-project-" ~ slug(name) ~ ".json", contentType("json"));
  }

  private void importProject(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto report = _app.exchange.importProject(body_(req), flag(req, "newIds"), flag(req, "dryRun"));
    res.writeJsonBody(serializeToJson(report), report.failed ? HTTPStatus.unprocessableEntity : HTTPStatus.ok);
  }

  private void downloadBackup(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto stamp = Clock.currTime.toUTC.toISOString[0 .. 15];
    download(res, _app.backups.createBackup, "grundschutz-backup-" ~ stamp ~ "Z.json", contentType("json"));
  }

  private void restoreUpload(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto report = _app.backups.restore(body_(req), flag(req, "dryRun"));
    res.writeJsonBody(serializeToJson(report), report.valid ? HTTPStatus.ok : HTTPStatus.unprocessableEntity);
  }

  private void listBackups(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    res.writeJsonBody(serializeToJson(_app.backups.listBackups));
  }

  private void createBackup(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    res.writeJsonBody(serializeToJson(_app.backups.backupToFile(req.query.get("label", "manual"))), HTTPStatus.created);
  }

  private void downloadServerBackup(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto name = req.params["name"];
    download(res, _app.backups.readBackup(name), name, contentType("json"));
  }

  private void restoreServerBackup(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto report = _app.backups.restoreFromFile(req.params["name"], flag(req, "dryRun"));
    res.writeJsonBody(serializeToJson(report), report.valid ? HTTPStatus.ok : HTTPStatus.unprocessableEntity);
  }

  // -------------------------------------------------------------- plumbing

  private void guarded(alias handler, string scope_)(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    res.headers["Cache-Control"] = "no-store";
    try {
      authorize(_app, req, scope_, res);
      ensureNotCrossSite(_app.authGuard, req);
      handler(req, res);
    } catch (Exception e) {
      auto info = classify(e);
      if (info.status == HTTPStatus.internalServerError) logException(e, "API request failed");
      auto err = Json.emptyObject;
      err["code"] = info.code;
      err["message"] = info.status == HTTPStatus.internalServerError ? "Internal server error" : e.msg;
      auto doc = Json.emptyObject;
      doc["error"] = err;
      res.writeJsonBody(doc, info.status);
    }
  }

  private static string body_(HTTPServerRequest req) @trusted {
    import vibe.stream.operations : readAllUTF8;
    auto text = req.bodyReader.readAllUTF8;
    if (text.length == 0) throw new BadRequestException("Request body is empty");
    return text;
  }

  private static bool flag(HTTPServerRequest req, string name) @trusted {
    auto v = req.query.get(name, "false");
    return v == "true" || v == "1";
  }

  private static void download(HTTPServerResponse res, string content, string name, string type) @trusted {
    res.headers["Content-Disposition"] = `attachment; filename="` ~ name ~ `"`;
    res.writeBody(content, type);
  }
}

/// "comma" | "semicolon" | "tab" or the character itself (URL-encoded, e.g. %3B).
char delimiterOf(string v) {
  switch (v) {
    case "", "comma", ",": return ',';
    case "semicolon", ";": return ';';
    case "tab", "\t": return '\t';
    default: throw new BadRequestException("Invalid delimiter '" ~ v ~ "' (comma, semicolon, tab)");
  }
}

string contentType(string format) {
  return format == "csv" ? "text/csv; charset=utf-8" : "application/json; charset=utf-8";
}

string fileName(string entity, string format) {
  import std.datetime.systime : Clock;
  return "grundschutz-" ~ entity ~ "-" ~ Clock.currTime.toUTC.toISOExtString[0 .. 10] ~ "." ~ format;
}

/// File name friendly version of a title.
string slug(string s) {
  import std.array : appender;
  import std.uni : isAlphaNum, toLower;
  auto r = appender!string;
  bool dash;
  foreach (dchar c; s) {
    if (c < 128 && isAlphaNum(c)) { r ~= toLower(c); dash = false; }
    else if (!dash && r.data.length) { r ~= '-'; dash = true; }
  }
  auto v = r.data;
  while (v.length && v[$ - 1] == '-') v = v[0 .. $ - 1];
  return v.length ? (v.length > 40 ? v[0 .. 40] : v) : "project";
}

unittest {
  assert(slug("ISMS Musterstadt 2026!") == "isms-musterstadt-2026");
  assert(slug("ÄÖÜ") == "project");
}
