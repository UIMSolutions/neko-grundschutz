/**
 * Server-side rendered web GUI (Diet templates + daisyUI). Also used as the
 * content of the desktop webview (see presentation/gui).
 * Forms use the POST-redirect-GET pattern and carry a per-user CSRF token.
 */
module uim.myfiori.presentation.web.controller;

@safe:

import std.algorithm : filter, map;
import std.array : array, join;
import std.conv : to, ConvException;
import std.digest.hmac : hmac;
import std.digest.sha : SHA256;
import std.digest : toHexString;
import std.string : representation, strip;
import std.typecons : Nullable;
import vibe.core.log;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.textfilter.urlencode : urlEncode;

import uim.myfiori.application.dtos;
import uim.myfiori.bootstrap;
import uim.myfiori.infrastructure.security : Principal, requiredScope;
import uim.myfiori.presentation.http.auth;
import uim.myfiori.presentation.http.errors;
import uim.myfiori.presentation.web.helpers;
import uim.myfiori.presentation.web.print : renderProjectHtml;

class DWebController {
  private DApplicationContainer _app;
  private ubyte[] _csrfSecret;

  this(DApplicationContainer app) {
    import std.random : uniform;
    _app = app;
    foreach (i; 0 .. 32) _csrfSecret ~= cast(ubyte) uniform(0, 256);
  }

  void register(URLRouter r) {
    r.get("/", (HTTPServerRequest req, HTTPServerResponse res) @safe { res.redirect("/web"); });
    r.get("/web", &guarded!index);
    r.get("/web/catalog", &guarded!catalog);
    r.post("/web/projects", &guarded!createProject);
    r.get("/web/projects/:id", &guarded!projectDetail);
    r.post("/web/projects/:id", &guarded!updateProject);
    r.post("/web/projects/:id/delete", &guarded!deleteProject);
    r.post("/web/projects/:id/objects", &guarded!createObject);
    r.post("/web/projects/:id/risks", &guarded!createRisk);
    r.post("/web/objects/:id", &guarded!updateObject);
    r.post("/web/objects/:id/delete", &guarded!deleteObject);
    r.post("/web/objects/:id/modules", &guarded!applyModule);
    r.post("/web/requirements/:id", &guarded!updateRequirement);
    r.post("/web/requirements/:id/delete", &guarded!deleteRequirement);
    r.post("/web/risks/:id", &guarded!updateRisk);
    r.post("/web/risks/:id/delete", &guarded!deleteRisk);
    // print, import / export, backup / restore
    r.get("/web/projects/:id/print", &guarded!printProject);
    r.get("/web/admin", &guarded!admin);
    r.post("/web/import", &guarded!importEntities);
    r.post("/web/import-project", &guarded!importProject);
    r.post("/web/backups", &guarded!createBackup);
    r.post("/web/restore", &guarded!restoreUpload);
    r.post("/web/backups/:name/restore", &guarded!restoreServerBackup);
  }

  // -------------------------------------------------------------- pages

  private void index(HTTPServerRequest req, HTTPServerResponse res, Principal user) @trusted {
    auto projects = _app.projects.list;
    auto reports = projects.map!(p => _app.reports.projectReport(p.ID)).array;
    auto pageTitle = "Projekte";
    auto msg = req.query.get("msg", "");
    auto err = req.query.get("err", "");
    auto csrf = csrfToken(user);
    auto userName = user.userName;
    res.render!("index.dt", pageTitle, projects, reports, msg, err, csrf, userName);
  }

  private void projectDetail(HTTPServerRequest req, HTTPServerResponse res, Principal user) @trusted {
    auto id = req.params["id"];
    auto project = _app.projects.get(id);
    auto report = _app.reports.projectReport(id);
    auto objects = _app.targetObjects.list(id);
    auto requirements = _app.requirements.list(id);
    auto risks = _app.risks.list(id);
    auto modules = _app.catalog.modules;
    auto threats = _app.catalog.threats;
    string[string] objectNames;
    foreach (o; objects) objectNames[o.ID] = o.name;
    auto tab = req.query.get("tab", "objects");
    auto pageTitle = project.name;
    auto msg = req.query.get("msg", "");
    auto err = req.query.get("err", "");
    auto csrf = csrfToken(user);
    auto userName = user.userName;
    res.render!("project.dt", pageTitle, project, report, objects, requirements, risks, modules, threats,
        objectNames, tab, msg, err, csrf, userName);
  }

  private void catalog(HTTPServerRequest req, HTTPServerResponse res, Principal user) @trusted {
    auto modules = _app.catalog.modules;
    CatalogRequirementDto[][string] requirementsByModule;
    foreach (m; modules) requirementsByModule[m.code] = _app.catalog.requirementsOf(m.code);
    auto threats = _app.catalog.threats;
    auto edition = _app.catalogGateway.edition;
    auto pageTitle = "Kompendium";
    auto msg = "";
    auto err = "";
    auto csrf = csrfToken(user);
    auto userName = user.userName;
    res.render!("catalog.dt", pageTitle, modules, requirementsByModule, threats, edition, msg, err, csrf, userName);
  }

  private void printProject(HTTPServerRequest req, HTTPServerResponse res, Principal) @trusted {
    auto html = renderProjectHtml(_app.reports.dossier(req.params["id"]), req.query.get("auto", "") == "1");
    res.writeBody(html, "text/html; charset=utf-8");
  }

  private void admin(HTTPServerRequest req, HTTPServerResponse res, Principal user) @trusted {
    import uim.myfiori.ports.services : exchangeEntities, importableEntities;
    auto entities = exchangeEntities;
    auto importable = importableEntities;
    auto isAdmin = user.hasScope("Admin");
    auto backups = isAdmin ? _app.backups.listBackups : null;
    auto storage = _app.storage.describe;
    auto pageTitle = "Administration";
    auto msg = req.query.get("msg", "");
    auto err = req.query.get("err", "");
    auto csrf = csrfToken(user);
    auto userName = user.userName;
    res.render!("admin.dt", pageTitle, entities, importable, isAdmin, backups, storage, msg, err, csrf, userName);
  }

  private void importEntities(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto report = _app.exchange.importEntities(req.form.get("entity", ""), "auto", uploaded(req),
        req.form.get("mode", "create"), checked(req, "dryRun"));
    reportRedirect(res, report.entity, report);
  }

  private void importProject(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto report = _app.exchange.importProject(uploaded(req), checked(req, "newIds"), checked(req, "dryRun"));
    reportRedirect(res, "Projekt", report);
  }

  private void createBackup(HTTPServerRequest req, HTTPServerResponse res, Principal user) {
    requireAdmin(user);
    auto info = _app.backups.backupToFile(req.form.get("label", "manual"));
    redirect(res, "/web/admin", "Datensicherung erstellt: " ~ info.name);
  }

  private void restoreUpload(HTTPServerRequest req, HTTPServerResponse res, Principal user) {
    requireAdmin(user);
    restoreRedirect(req, res, _app.backups.restore(uploaded(req), restoreDryRun(req)));
  }

  private void restoreServerBackup(HTTPServerRequest req, HTTPServerResponse res, Principal user) {
    requireAdmin(user);
    restoreRedirect(req, res, _app.backups.restoreFromFile(req.params["name"], restoreDryRun(req)));
  }

  // -------------------------------------------------------------- commands

  private void createProject(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto f = (string k) => req.form.get(k, "");
    auto p = _app.projects.create(CreateProjectInput(f("name"), f("description"), f("scope"), f("owner"),
        f("approach").length ? f("approach") : "standard"));
    redirect(res, projectUrl(p.ID), "Projekt angelegt");
  }

  private void updateProject(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto id = req.params["id"];
    UpdateProjectInput input;
    input.name = opt(req, "name");
    input.description = opt(req, "description");
    input.scope_ = opt(req, "scope");
    input.owner = opt(req, "owner");
    input.approach = opt(req, "approach");
    input.status = opt(req, "status");
    _app.projects.update(id, input);
    redirect(res, projectUrl(id, "settings"), "Projekt gespeichert");
  }

  private void deleteProject(HTTPServerRequest req, HTTPServerResponse res, Principal user) {
    if (!user.hasScope("Admin")) throw new ForbiddenException("Deleting projects requires the Admin role");
    _app.projects.remove(req.params["id"]);
    redirect(res, "/web", "Projekt gelöscht");
  }

  private void createObject(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto id = req.params["id"];
    auto f = (string k, string d = "") => req.form.get(k, d);
    _app.targetObjects.create(CreateTargetObjectInput(id, f("name"), f("kind", "itSystem"), f("description"),
        f("confidentiality", "normal"), f("integrity", "normal"), f("availability", "normal"), f("protectionRationale")));
    redirect(res, projectUrl(id, "objects"), "Zielobjekt angelegt");
  }

  private void updateObject(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    UpdateTargetObjectInput input;
    input.name = opt(req, "name");
    input.kind = opt(req, "kind");
    input.description = opt(req, "description");
    input.confidentiality = opt(req, "confidentiality");
    input.integrity = opt(req, "integrity");
    input.availability = opt(req, "availability");
    input.protectionRationale = opt(req, "protectionRationale");
    auto o = _app.targetObjects.update(req.params["id"], input);
    redirect(res, projectUrl(o.projectId, "objects"), "Schutzbedarf gespeichert");
  }

  private void deleteObject(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto o = _app.targetObjects.get(req.params["id"]);
    _app.targetObjects.remove(o.ID);
    redirect(res, projectUrl(o.projectId, "objects"), "Zielobjekt gelöscht");
  }

  private void applyModule(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto o = _app.targetObjects.get(req.params["id"]);
    auto created = _app.requirements.applyModule(o.ID, req.form.get("moduleCode", ""));
    redirect(res, projectUrl(o.projectId, "requirements"), created.length.to!string ~ " Anforderungen modelliert");
  }

  private void updateRequirement(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    UpdateRequirementInput input;
    input.status = opt(req, "status");
    input.note = opt(req, "note");
    input.responsible = opt(req, "responsible");
    input.dueDate = opt(req, "dueDate");
    auto r = _app.requirements.update(req.params["id"], input);
    redirect(res, projectUrl(r.projectId, "requirements"), r.code ~ " gespeichert");
  }

  private void deleteRequirement(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto r = _app.requirements.get(req.params["id"]);
    _app.requirements.remove(r.ID);
    redirect(res, projectUrl(r.projectId, "requirements"), r.code ~ " entfernt");
  }

  private void createRisk(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto id = req.params["id"];
    auto f = (string k, string d = "") => req.form.get(k, d);
    _app.risks.create(CreateRiskInput(f("targetObjectId"), f("threatCode"), f("title"), f("description"),
        number(f("frequency", "1")), number(f("impact", "1")), f("treatment", "open"), f("treatmentNote")));
    redirect(res, projectUrl(id, "risks"), "Risiko erfasst");
  }

  private void updateRisk(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    UpdateRiskInput input;
    if (auto v = req.form.get("frequency", null)) input.frequency = number(v);
    if (auto v = req.form.get("impact", null)) input.impact = number(v);
    input.treatment = opt(req, "treatment");
    input.treatmentNote = opt(req, "treatmentNote");
    auto r = _app.risks.update(req.params["id"], input);
    redirect(res, projectUrl(r.projectId, "risks"), "Risiko gespeichert");
  }

  private void deleteRisk(HTTPServerRequest req, HTTPServerResponse res, Principal) {
    auto r = _app.risks.get(req.params["id"]);
    _app.risks.remove(r.ID);
    redirect(res, projectUrl(r.projectId, "risks"), "Risiko gelöscht");
  }

  // -------------------------------------------------------------- exchange helpers

  private static string uploaded(HTTPServerRequest req) @trusted {
    import std.file : readText;
    auto part = "file" in req.files;
    if (part is null) throw new BadRequestException("Bitte eine Datei auswählen");
    return readText(part.tempPath.toString);
  }

  private static bool checked(HTTPServerRequest req, string field) @trusted {
    return req.form.get(field, "") == "on" || req.form.get(field, "") == "true";
  }

  /// A restore is only executed when explicitly confirmed; otherwise it is a dry run.
  private static bool restoreDryRun(HTTPServerRequest req) @trusted {
    return checked(req, "dryRun") || !checked(req, "confirm");
  }

  private static void requireAdmin(Principal user) {
    if (!user.hasScope("Admin")) throw new ForbiddenException("Backup und Restore erfordern die Rolle Administrator");
  }

  private static void reportRedirect(HTTPServerResponse res, string what, ImportReport r) @trusted {
    import std.format : format;
    auto summary = format("%s: %d Datensätze – %d angelegt, %d aktualisiert, %d übersprungen, %d fehlerhaft",
        what, r.total, r.created, r.updated, r.skipped, r.failed);
    if (r.failed) {
      string details;
      foreach (i, issue; r.issues) {
        if (i == 8) { details ~= " · …"; break; }
        details ~= format(" · Zeile %d%s: %s", issue.row, issue.id.length ? " (" ~ issue.id ~ ")" : "", issue.message);
      }
      res.redirect("/web/admin?err=" ~ urlEncode(summary ~ ". Nichts importiert." ~ details));
    } else
      redirect(res, "/web/admin", summary ~ (r.dryRun ? " (Probelauf – nichts gespeichert)" : ""));
  }

  private static void restoreRedirect(HTTPServerRequest req, HTTPServerResponse res, RestoreReport r) @trusted {
    import std.format : format;
    auto counts = format("%d Projekte, %d Zielobjekte, %d Anforderungen, %d Risiken (Sicherung vom %s)",
        r.projects, r.targetObjects, r.requirements, r.risks, r.createdAt);
    if (!r.valid) {
      res.redirect("/web/admin?err=" ~ urlEncode("Sicherung ungültig: " ~ r.issues.join(" · ")));
      return;
    }
    if (!r.restored) {
      redirect(res, "/web/admin", "Prüfung erfolgreich – " ~ counts
          ~ ". Zum Wiederherstellen „Bestätigen“ ankreuzen.");
      return;
    }
    redirect(res, "/web/admin", "Wiederhergestellt: " ~ counts ~ ". Vorheriger Stand gesichert als " ~ r.safetyBackup);
  }

  // -------------------------------------------------------------- plumbing

  /// Wraps a handler with authentication, authorization, CSRF check and error handling.
  private void guarded(alias handler)(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    Principal user;
    try {
      user = authorize(_app.authGuard, req, requiredScope(req.method.to!string));
      if (req.method == HTTPMethod.POST && req.form.get("csrf", "") != csrfToken(user))
        throw new ForbiddenException("Invalid or missing CSRF token — please reload the page");
      handler(req, res, user);
    } catch (Exception e) {
      auto info = classify(e);
      if (info.status == HTTPStatus.internalServerError) logException(e, "Web request failed");
      auto message = info.status == HTTPStatus.internalServerError ? "Interner Fehler" : e.msg;
      if (req.method == HTTPMethod.POST && info.status != HTTPStatus.unauthorized) {
        auto back = req.headers.get("Referer", "/web");
        // only redirect to local pages
        import std.string : indexOf;
        auto path = back.indexOf("/web") >= 0 ? back[back.indexOf("/web") .. $] : "/web";
        auto q = path.indexOf("?");
        auto tab = req.form.get("tab", "");
        auto target = (q >= 0 ? path[0 .. q] : path) ~ "?" ~ (tab.length ? "tab=" ~ urlEncode(tab) ~ "&" : "");
        res.redirect(target ~ "err=" ~ urlEncode(message));
      } else {
        res.statusCode = info.status;
        res.writeBody("<!doctype html><meta charset=utf-8><title>Fehler</title><p>" ~ htmlEscape(message)
            ~ "</p><p><a href=\"/web\">Zur Übersicht</a></p>", "text/html; charset=utf-8");
      }
    }
  }

  /// Per-user CSRF token: HMAC-SHA256(secret, user name).
  string csrfToken(Principal user) {
    auto mac = hmac!SHA256(user.userName.representation, _csrfSecret);
    return toHexString(mac).idup;
  }

  private static Nullable!string opt(HTTPServerRequest req, string field) @trusted {
    if (auto v = field in req.form) return Nullable!string(*v);
    return Nullable!string.init;
  }

  private static int number(string v) {
    try return v.strip.to!int;
    catch (ConvException) throw new BadRequestException("'" ~ v ~ "' is not a number");
  }

  private static string projectUrl(string id, string tab = "") {
    return "/web/projects/" ~ urlEncode(id) ~ (tab.length ? "?tab=" ~ tab : "");
  }

  private static void redirect(HTTPServerResponse res, string url, string message) @trusted {
    import std.string : indexOf;
    res.redirect(url ~ (url.indexOf('?') >= 0 ? "&" : "?") ~ "msg=" ~ urlEncode(message));
  }

  private static string htmlEscape(string s) {
    import std.array : replace;
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
  }
}
