/**
 * Server-side rendered web GUI (Diet templates + Beer CSS + htmx). Also used as the
 * content of the desktop webview (see presentation/gui).
 *
 * Navigation and forms are "boosted" by htmx (AJAX + body swap) and still follow the
 * POST-redirect-GET pattern, so every page also works without JavaScript. Forms marked
 * with `inline=1` (requirement / risk rows) are answered with an HX-Trigger event instead
 * of a redirect. Every form carries a per-session CSRF token.
 *
 * Login: with `login` enabled (and no XSUAA) users sign in on /login with a local account;
 * /setup creates the first administrator. Administrators manage accounts on /web/users.
 */
module uim.myfiori.presentation.web.controller;

@safe:

import std.algorithm : map;
import std.array : array, join;
import std.conv : to, ConvException;
import std.datetime.systime : Clock;
import std.digest.hmac : hmac;
import std.digest.sha : SHA256;
import std.digest : toHexString;
import std.string : indexOf, representation, startsWith, strip;
import std.typecons : Nullable;
import vibe.core.log;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.textfilter.urlencode : urlEncode;

import uim.myfiori.application.dtos;
import uim.myfiori.bootstrap;
import uim.myfiori.domain.exceptions;
import uim.myfiori.infrastructure.security : AuthenticationException, Principal, randomBytes, requiredScope;
import uim.myfiori.presentation.http.auth;
import uim.myfiori.presentation.http.errors;
import uim.myfiori.presentation.web.helpers;
import uim.myfiori.presentation.web.print : renderProjectHtml;

/// Values every page (layout) needs.
struct PageContext {
  string pageTitle;
  string nav;            // active navigation entry
  string msg;
  string err;
  string csrf;
  Principal user;
  bool loginEnabled;     // local accounts: show account menu / logout

  bool isAdmin() const { return user.hasScope("Admin"); }
  bool canEdit() const { return user.hasScope("Editor"); }
  string displayName() const { return user.displayName.length ? user.displayName : user.userName; }
}

class DWebController {
  private DApplicationContainer _app;
  private ubyte[] _csrfSecret;
  private LoginThrottle _throttle;

  this(DApplicationContainer app) {
    _app = app;
    _csrfSecret = randomBytes(32);
  }

  void register(URLRouter r) {
    r.get("/", (HTTPServerRequest req, HTTPServerResponse res) @safe { res.redirect("/web"); });
    // login / logout / first-run setup
    r.get("/login", &loginPage);
    r.post("/login", &login);
    r.post("/logout", &logout);
    r.get("/setup", &setupPage);
    r.post("/setup", &setup);
    // pages
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
    r.post("/web/backups", &guarded!(createBackup, "Admin"));
    r.post("/web/restore", &guarded!(restoreUpload, "Admin"));
    r.post("/web/backups/:name/restore", &guarded!(restoreServerBackup, "Admin"));
    // own account (every logged-in user may change name, e-mail and password)
    r.get("/web/account", &guarded!account);
    r.post("/web/account", &guarded!(updateAccount, "Viewer"));
    r.post("/web/account/password", &guarded!(changeOwnPassword, "Viewer"));
    // user management
    r.get("/web/users", &guarded!(users, "Admin"));
    r.post("/web/users", &guarded!(createUser, "Admin"));
    r.post("/web/users/:id", &guarded!(updateUser, "Admin"));
    r.post("/web/users/:id/password", &guarded!(resetPassword, "Admin"));
    r.post("/web/users/:id/delete", &guarded!(deleteUser, "Admin"));
  }

  // -------------------------------------------------------------- login

  private void loginPage(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    if (!_app.authGuard.loginEnabled) return navigate(req, res, "/web");
    if (!_app.users.hasUsers) return navigate(req, res, "/setup");
    auto next = safeNext(req.query.get("next", "/web"));
    if (sessionPrincipal(_app, req, res).userName.length) return navigate(req, res, next);
    auto pageTitle = "Anmelden";
    auto err = req.query.get("err", "");
    auto msg = req.query.get("msg", "");
    auto userName = req.query.get("user", "");
    res.headers["Cache-Control"] = "no-store";
    res.render!("login.dt", pageTitle, next, err, msg, userName);
  }

  private void login(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto userName = req.form.get("userName", "").strip;
    auto next = safeNext(req.form.get("next", "/web"));
    try {
      if (!_app.authGuard.loginEnabled) throw new ForbiddenException("Lokale Anmeldung ist deaktiviert");
      ensureNotCrossSite(_app.authGuard, req);
      _throttle.check(userName);
      auto user = _app.users.authenticate(userName, req.form.get("password", ""));
      _throttle.succeeded(userName);
      beginSession(req, res, user.ID);
      logInfo("Login: %s", user.userName);
      navigate(req, res, next);
    } catch (Exception e) {
      if (cast(AuthenticationFailedException) e) _throttle.failed(userName);
      auto info = classify(e);
      if (info.status == HTTPStatus.internalServerError) logException(e, "Login failed");
      auto message = info.status == HTTPStatus.internalServerError ? "Interner Fehler" : e.msg;
      navigate(req, res, "/login?next=" ~ urlEncode(next) ~ "&user=" ~ urlEncode(userName)
          ~ "&err=" ~ urlEncode(message));
    }
  }

  private void logout(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto user = sessionPrincipal(_app, req, res);
    if (user.userName.length && req.form.get("csrf", "") == csrfToken(req, user)) {
      endSession(req, res);
      logInfo("Logout: %s", user.userName);
    }
    navigate(req, res, "/login?msg=" ~ urlEncode("Sie wurden abgemeldet"));
  }

  private void setupPage(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    if (!_app.authGuard.loginEnabled || _app.users.hasUsers) return navigate(req, res, "/login");
    auto pageTitle = "Ersteinrichtung";
    auto err = req.query.get("err", "");
    auto msg = "";
    auto next = "/web";
    auto userName = req.query.get("user", "admin");
    res.headers["Cache-Control"] = "no-store";
    res.render!("setup.dt", pageTitle, next, err, msg, userName);
  }

  private void setup(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto userName = req.form.get("userName", "").strip;
    try {
      if (!_app.authGuard.loginEnabled || _app.users.hasUsers)
        throw new ConflictException("Die Ersteinrichtung ist bereits abgeschlossen");
      ensureNotCrossSite(_app.authGuard, req);
      if (req.form.get("password", "") != req.form.get("password2", ""))
        throw new ValidationException("Die Passwörter stimmen nicht überein");
      CreateUserInput input;
      input.userName = userName;
      input.displayName = req.form.get("displayName", "");
      input.email = req.form.get("email", "");
      input.role = "admin";
      input.password = req.form.get("password", "");
      auto user = _app.users.create(input);
      beginSession(req, res, user.ID);
      logInfo("Setup: first administrator '%s' created", user.userName);
      navigate(req, res, "/web?msg=" ~ urlEncode("Administrator " ~ user.userName ~ " angelegt – willkommen!"));
    } catch (Exception e) {
      auto info = classify(e);
      if (info.status == HTTPStatus.internalServerError) logException(e, "Setup failed");
      navigate(req, res, "/setup?user=" ~ urlEncode(userName) ~ "&err="
          ~ urlEncode(info.status == HTTPStatus.internalServerError ? "Interner Fehler" : e.msg));
    }
  }

  // -------------------------------------------------------------- pages

  private void index(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) @trusted {
    auto projects = _app.projects.list;
    auto reports = projects.map!(p => _app.reports.projectReport(p.ID)).array;
    ctx.pageTitle = "Projekte";
    ctx.nav = "projects";
    res.render!("index.dt", ctx, projects, reports);
  }

  private void projectDetail(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) @trusted {
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
    ctx.pageTitle = project.name;
    ctx.nav = "projects";
    res.render!("project.dt", ctx, project, report, objects, requirements, risks, modules, threats,
        objectNames, tab);
  }

  private void catalog(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) @trusted {
    auto modules = _app.catalog.modules;
    CatalogRequirementDto[][string] requirementsByModule;
    foreach (m; modules) requirementsByModule[m.code] = _app.catalog.requirementsOf(m.code);
    auto threats = _app.catalog.threats;
    auto edition = _app.catalogGateway.edition;
    ctx.pageTitle = "Kompendium";
    ctx.nav = "catalog";
    res.render!("catalog.dt", ctx, modules, requirementsByModule, threats, edition);
  }

  private void printProject(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) @trusted {
    auto html = renderProjectHtml(_app.reports.dossier(req.params["id"]), req.query.get("auto", "") == "1");
    res.writeBody(html, "text/html; charset=utf-8");
  }

  private void admin(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) @trusted {
    import uim.myfiori.ports.services : exchangeEntities, importableEntities;
    auto entities = exchangeEntities;
    auto importable = importableEntities;
    auto backups = ctx.isAdmin ? _app.backups.listBackups : null;
    auto storage = _app.storage.describe;
    ctx.pageTitle = "Daten & Sicherung";
    ctx.nav = "admin";
    res.render!("admin.dt", ctx, entities, importable, backups, storage);
  }

  private void importEntities(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto report = _app.exchange.importEntities(req.form.get("entity", ""), "auto", uploaded(req),
        req.form.get("mode", "create"), checked(req, "dryRun"));
    reportRedirect(req, res, report.entity, report);
  }

  private void importProject(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto report = _app.exchange.importProject(uploaded(req), checked(req, "newIds"), checked(req, "dryRun"));
    reportRedirect(req, res, "Projekt", report);
  }

  private void createBackup(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto info = _app.backups.backupToFile(req.form.get("label", "manual"));
    redirect(req, res, "/web/admin", "Datensicherung erstellt: " ~ info.name);
  }

  private void restoreUpload(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    restoreRedirect(req, res, _app.backups.restore(uploaded(req), restoreDryRun(req)));
  }

  private void restoreServerBackup(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    restoreRedirect(req, res, _app.backups.restoreFromFile(req.params["name"], restoreDryRun(req)));
  }

  // -------------------------------------------------------------- account & users

  private void account(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) @trusted {
    ctx.pageTitle = "Mein Konto";
    ctx.nav = "account";
    auto hasAccount = ctx.user.userId.length > 0;
    UserDto me;
    if (hasAccount) me = _app.users.get(ctx.user.userId);
    res.render!("account.dt", ctx, hasAccount, me);
  }

  private void updateAccount(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) {
    UpdateUserInput input;
    input.displayName = opt(req, "displayName");
    input.email = opt(req, "email");
    _app.users.update(ownAccount(ctx), input);
    redirect(req, res, "/web/account", "Konto gespeichert");
  }

  private void changeOwnPassword(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) @trusted {
    requireMatchingPasswords(req);
    _app.users.changeOwnPassword(ownAccount(ctx), req.form.get("current", ""), req.form.get("password", ""));
    redirect(req, res, "/web/account", "Passwort geändert");
  }

  private void users(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) @trusted {
    auto accounts = _app.users.list;
    ctx.pageTitle = "Benutzer";
    ctx.nav = "users";
    res.render!("users.dt", ctx, accounts);
  }

  private void createUser(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) @trusted {
    requireLocalAccounts();
    requireMatchingPasswords(req);
    CreateUserInput input;
    input.userName = req.form.get("userName", "");
    input.displayName = req.form.get("displayName", "");
    input.email = req.form.get("email", "");
    input.role = req.form.get("role", "viewer");
    input.password = req.form.get("password", "");
    input.active = true;
    auto u = _app.users.create(input);
    redirect(req, res, "/web/users", "Benutzer " ~ u.userName ~ " angelegt");
  }

  private void updateUser(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) @trusted {
    auto id = req.params["id"];
    UpdateUserInput input;
    input.displayName = opt(req, "displayName");
    input.email = opt(req, "email");
    input.role = opt(req, "role");
    if ("activeField" in req.form) input.active = checked(req, "active");
    if (id == ctx.user.userId && (!input.active.isNull && !input.active.get))
      throw new ConflictException("Sie können Ihr eigenes Konto nicht deaktivieren");
    auto u = _app.users.update(id, input);
    redirect(req, res, "/web/users", "Benutzer " ~ u.userName ~ " gespeichert");
  }

  private void resetPassword(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) @trusted {
    requireMatchingPasswords(req);
    auto id = req.params["id"];
    _app.users.setPassword(id, req.form.get("password", ""));
    redirect(req, res, "/web/users", "Passwort von " ~ _app.users.get(id).userName ~ " gesetzt");
  }

  private void deleteUser(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) {
    auto id = req.params["id"];
    if (id == ctx.user.userId) throw new ConflictException("Sie können Ihr eigenes Konto nicht löschen");
    auto name = _app.users.get(id).userName;
    _app.users.remove(id);
    redirect(req, res, "/web/users", "Benutzer " ~ name ~ " gelöscht");
  }

  private string ownAccount(ref PageContext ctx) {
    if (ctx.user.userId.length == 0)
      throw new ConflictException("Ohne lokale Anmeldung gibt es kein eigenes Benutzerkonto");
    return ctx.user.userId;
  }

  private void requireLocalAccounts() {
    if (_app.authGuard.enabled)
      throw new ConflictException("Benutzer werden über SAP BTP (XSUAA) verwaltet");
  }

  private static void requireMatchingPasswords(HTTPServerRequest req) @trusted {
    if (req.form.get("password", "") != req.form.get("password2", ""))
      throw new ValidationException("Die Passwörter stimmen nicht überein");
  }

  // -------------------------------------------------------------- commands

  private void createProject(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto f = (string k) => req.form.get(k, "");
    auto p = _app.projects.create(CreateProjectInput(f("name"), f("description"), f("scope"), f("owner"),
        f("approach").length ? f("approach") : "standard"));
    redirect(req, res, projectUrl(p.ID), "Projekt angelegt");
  }

  private void updateProject(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto id = req.params["id"];
    UpdateProjectInput input;
    input.name = opt(req, "name");
    input.description = opt(req, "description");
    input.scope_ = opt(req, "scope");
    input.owner = opt(req, "owner");
    input.approach = opt(req, "approach");
    input.status = opt(req, "status");
    _app.projects.update(id, input);
    redirect(req, res, projectUrl(id, "settings"), "Projekt gespeichert");
  }

  private void deleteProject(HTTPServerRequest req, HTTPServerResponse res, ref PageContext ctx) {
    if (!ctx.isAdmin) throw new ForbiddenException("Projekte löschen erfordert die Rolle Administrator");
    _app.projects.remove(req.params["id"]);
    redirect(req, res, "/web", "Projekt gelöscht");
  }

  private void createObject(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto id = req.params["id"];
    auto f = (string k, string d = "") => req.form.get(k, d);
    _app.targetObjects.create(CreateTargetObjectInput(id, f("name"), f("kind", "itSystem"), f("description"),
        f("confidentiality", "normal"), f("integrity", "normal"), f("availability", "normal"), f("protectionRationale")));
    redirect(req, res, projectUrl(id, "objects"), "Zielobjekt angelegt");
  }

  private void updateObject(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    UpdateTargetObjectInput input;
    input.name = opt(req, "name");
    input.kind = opt(req, "kind");
    input.description = opt(req, "description");
    input.confidentiality = opt(req, "confidentiality");
    input.integrity = opt(req, "integrity");
    input.availability = opt(req, "availability");
    input.protectionRationale = opt(req, "protectionRationale");
    auto o = _app.targetObjects.update(req.params["id"], input);
    redirect(req, res, projectUrl(o.projectId, "objects"), "Schutzbedarf gespeichert");
  }

  private void deleteObject(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto o = _app.targetObjects.get(req.params["id"]);
    _app.targetObjects.remove(o.ID);
    redirect(req, res, projectUrl(o.projectId, "objects"), "Zielobjekt gelöscht");
  }

  private void applyModule(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto o = _app.targetObjects.get(req.params["id"]);
    auto created = _app.requirements.applyModule(o.ID, req.form.get("moduleCode", ""));
    redirect(req, res, projectUrl(o.projectId, "requirements"), created.length.to!string ~ " Anforderungen modelliert");
  }

  private void updateRequirement(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    UpdateRequirementInput input;
    input.status = opt(req, "status");
    input.note = opt(req, "note");
    input.responsible = opt(req, "responsible");
    input.dueDate = opt(req, "dueDate");
    auto r = _app.requirements.update(req.params["id"], input);
    redirect(req, res, projectUrl(r.projectId, "requirements"), r.code ~ " gespeichert");
  }

  private void deleteRequirement(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto r = _app.requirements.get(req.params["id"]);
    _app.requirements.remove(r.ID);
    redirect(req, res, projectUrl(r.projectId, "requirements"), r.code ~ " entfernt");
  }

  private void createRisk(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto id = req.params["id"];
    auto f = (string k, string d = "") => req.form.get(k, d);
    _app.risks.create(CreateRiskInput(f("targetObjectId"), f("threatCode"), f("title"), f("description"),
        number(f("frequency", "1")), number(f("impact", "1")), f("treatment", "open"), f("treatmentNote")));
    redirect(req, res, projectUrl(id, "risks"), "Risiko erfasst");
  }

  private void updateRisk(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    UpdateRiskInput input;
    if (auto v = req.form.get("frequency", null)) input.frequency = number(v);
    if (auto v = req.form.get("impact", null)) input.impact = number(v);
    input.treatment = opt(req, "treatment");
    input.treatmentNote = opt(req, "treatmentNote");
    auto r = _app.risks.update(req.params["id"], input);
    redirect(req, res, projectUrl(r.projectId, "risks"), "Risiko gespeichert");
  }

  private void deleteRisk(HTTPServerRequest req, HTTPServerResponse res, ref PageContext) {
    auto r = _app.risks.get(req.params["id"]);
    _app.risks.remove(r.ID);
    redirect(req, res, projectUrl(r.projectId, "risks"), "Risiko gelöscht");
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

  private static void reportRedirect(HTTPServerRequest req, HTTPServerResponse res, string what, ImportReport r) @trusted {
    import std.format : format;
    auto summary = format("%s: %d Datensätze – %d angelegt, %d aktualisiert, %d übersprungen, %d fehlerhaft",
        what, r.total, r.created, r.updated, r.skipped, r.failed);
    if (r.failed) {
      string details;
      foreach (i, issue; r.issues) {
        if (i == 8) { details ~= " · …"; break; }
        details ~= format(" · Zeile %d%s: %s", issue.row, issue.id.length ? " (" ~ issue.id ~ ")" : "", issue.message);
      }
      navigate(req, res, "/web/admin?err=" ~ urlEncode(summary ~ ". Nichts importiert." ~ details));
    } else
      redirect(req, res, "/web/admin", summary ~ (r.dryRun ? " (Probelauf – nichts gespeichert)" : ""));
  }

  private static void restoreRedirect(HTTPServerRequest req, HTTPServerResponse res, RestoreReport r) @trusted {
    import std.format : format;
    auto counts = format("%d Projekte, %d Zielobjekte, %d Anforderungen, %d Risiken (Sicherung vom %s)",
        r.projects, r.targetObjects, r.requirements, r.risks, r.createdAt);
    if (!r.valid)
      return navigate(req, res, "/web/admin?err=" ~ urlEncode("Sicherung ungültig: " ~ r.issues.join(" · ")));
    if (!r.restored)
      return redirect(req, res, "/web/admin", "Prüfung erfolgreich – " ~ counts
          ~ ". Zum Wiederherstellen „Bestätigen“ ankreuzen.");
    redirect(req, res, "/web/admin", "Wiederhergestellt: " ~ counts ~ ". Vorheriger Stand gesichert als " ~ r.safetyBackup);
  }

  // -------------------------------------------------------------- plumbing

  /**
   * Wraps a handler with authentication, authorization, CSRF check and error handling.
   * `scope_` overrides the default scope (GET: Viewer, otherwise Editor).
   */
  private void guarded(alias handler, string scope_ = "")(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    PageContext ctx;
    ctx.loginEnabled = _app.authGuard.loginEnabled;
    ctx.msg = req.query.get("msg", "");
    ctx.err = req.query.get("err", "");
    res.headers["Cache-Control"] = "no-store";
    try {
      ctx.user = authorize(_app, req, scope_.length ? scope_ : requiredScope(req.method.to!string), res);
      ctx.csrf = csrfToken(req, ctx.user);
      if (req.method == HTTPMethod.POST) {
        if (req.form.get("csrf", "") != ctx.csrf)
          throw new ForbiddenException("Ungültiges oder fehlendes CSRF-Token – bitte Seite neu laden");
        ensureNotCrossSite(_app.authGuard, req);
      }
      handler(req, res, ctx);
    } catch (Exception e) {
      auto info = classify(e);
      if (info.status == HTTPStatus.unauthorized && ctx.loginEnabled) {
        // not (or no longer) logged in: to the login page, then back
        auto back = req.method == HTTPMethod.GET ? req.requestURI : refererPath(req);
        return navigate(req, res, "/login?next=" ~ urlEncode(back));
      }
      if (info.status == HTTPStatus.internalServerError) logException(e, "Web request failed");
      auto message = info.status == HTTPStatus.internalServerError ? "Interner Fehler" : e.msg;
      if (isInline(req)) return trigger(res, "gs:error", message);
      if (req.method == HTTPMethod.POST && info.status != HTTPStatus.unauthorized) {
        auto path = refererPath(req);
        auto q = path.indexOf("?");
        auto tab = req.form.get("tab", "");
        auto target = (q >= 0 ? path[0 .. q] : path) ~ "?" ~ (tab.length ? "tab=" ~ urlEncode(tab) ~ "&" : "");
        navigate(req, res, target ~ "err=" ~ urlEncode(message));
      } else {
        res.statusCode = info.status;
        res.writeBody("<!doctype html><meta charset=utf-8><title>Fehler</title><p>" ~ htmlEscape(message)
            ~ "</p><p><a href=\"/web\">Zur Übersicht</a></p>", "text/html; charset=utf-8");
      }
    }
  }

  /// Per-session CSRF token: HMAC-SHA256(secret, user name | session id).
  string csrfToken(HTTPServerRequest req, Principal user) @trusted {
    auto sid = req.session ? req.session.id : "";
    auto mac = hmac!SHA256((user.userName ~ "|" ~ sid).representation, _csrfSecret);
    return toHexString(mac).idup;
  }

  /// Local part of the Referer ("/web..."), "/web" otherwise.
  private static string refererPath(HTTPServerRequest req) @trusted {
    auto back = req.headers.get("Referer", "/web");
    auto i = back.indexOf("/web");
    return i >= 0 ? back[i .. $] : "/web";
  }

  /// Only local absolute paths are accepted as redirect target after the login.
  private static string safeNext(string next) {
    if (!next.startsWith("/") || next.startsWith("//") || next.indexOf('\\') >= 0 || next.startsWith("/login")
        || next.startsWith("/setup"))
      return "/web";
    return next;
  }

  private static bool isHtmx(HTTPServerRequest req) @trusted { return req.headers.get("HX-Request", "") == "true"; }

  /// Row forms posted by htmx with `inline=1` expect an event instead of a new page.
  private static bool isInline(HTTPServerRequest req) @trusted {
    return isHtmx(req) && req.method == HTTPMethod.POST && req.form.get("inline", "") == "1";
  }

  /// Redirect; htmx requests get a full page navigation (keeps history and title intact).
  private static void navigate(HTTPServerRequest req, HTTPServerResponse res, string url) @trusted {
    if (isHtmx(req) && (url.startsWith("/login") || url.startsWith("/setup"))) {
      res.headers["HX-Redirect"] = url;
      res.writeBody("", "text/plain");
    } else
      res.redirect(url);
  }

  /// Answers an htmx request with a client event (shown as snackbar by /public/app.js).
  private static void trigger(HTTPServerResponse res, string event, string message) @trusted {
    res.headers["HX-Trigger"] = `{"` ~ event ~ `":{"text":"` ~ jsonAscii(message) ~ `"}}`;
    res.writeBody("", "text/plain");
  }

  private static Nullable!string opt(HTTPServerRequest req, string field) @trusted {
    if (auto v = field in req.form) return Nullable!string(*v);
    return Nullable!string.init;
  }

  private static int number(string v) {
    try return v.strip.to!int;
    catch (ConvException) throw new BadRequestException("'" ~ v ~ "' ist keine Zahl");
  }

  private static string projectUrl(string id, string tab = "") {
    return "/web/projects/" ~ urlEncode(id) ~ (tab.length ? "?tab=" ~ tab : "");
  }

  private static void redirect(HTTPServerRequest req, HTTPServerResponse res, string url, string message) @trusted {
    if (isInline(req)) return trigger(res, "gs:message", message);
    res.redirect(url ~ (url.indexOf('?') >= 0 ? "&" : "?") ~ "msg=" ~ urlEncode(message));
  }

  private static string htmlEscape(string s) {
    import std.array : replace;
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
  }
}

/// JSON string content with all non-ASCII characters escaped (HTTP headers are Latin-1).
string jsonAscii(string s) {
  import std.format : format;
  import std.utf : byDchar;
  string r;
  foreach (dchar c; s.byDchar) {
    if (c == '"' || c == '\\') r ~= "\\" ~ cast(char) c;
    else if (c < 0x20) r ~= format("\\u%04x", cast(uint) c);
    else if (c < 0x80) r ~= cast(char) c;
    else if (c < 0x10000) r ~= format("\\u%04x", cast(uint) c);
    else {
      auto v = c - 0x10000;
      r ~= format("\\u%04x\\u%04x", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF));
    }
  }
  return r;
}

unittest {
  assert(jsonAscii("gel\u00f6scht \"x\"") == "gel" ~ `\u00f6` ~ `scht \"x\"`);
}

/// Slows down password guessing: 5 failures per user name lock it for 5 minutes.
struct LoginThrottle {
  private struct Entry { int failures; long last; }
  private Entry[string] _entries;
  enum maxFailures = 5, lockSeconds = 300;

  void check(string userName) {
    import std.string : toLower;
    auto now = Clock.currTime.toUnixTime;
    if (auto e = userName.toLower in _entries)
      if (e.failures >= maxFailures && now - e.last < lockSeconds)
        throw new AuthenticationFailedException("Zu viele Fehlversuche – bitte in einigen Minuten erneut versuchen");
  }

  void failed(string userName) {
    import std.string : toLower;
    auto now = Clock.currTime.toUnixTime;
    auto key = userName.toLower;
    auto e = _entries.get(key, Entry.init);
    if (now - e.last >= lockSeconds) e.failures = 0;
    e.failures++;
    e.last = now;
    _entries[key] = e;
    if (_entries.length > 10_000) _entries = null;   // bound memory
  }

  void succeeded(string userName) {
    import std.string : toLower;
    _entries.remove(userName.toLower);
  }
}
