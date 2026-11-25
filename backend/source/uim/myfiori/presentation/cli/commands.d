/**
 * Command-line interface. Uses the same use cases as OData and web GUI.
 * Run `grundschutz help` for the command reference.
 */
module uim.myfiori.presentation.cli.commands;

@safe:

import std.algorithm : filter, map, startsWith;
import std.array : array, join;
import std.conv : to, ConvException;
import std.format : format;
import std.stdio : stdout, stderr;
import vibe.data.json;

import uim.myfiori.application.dtos;
import uim.myfiori.bootstrap;
import uim.myfiori.domain.exceptions;
import uim.myfiori.appinfo : appVersion;
import uim.myfiori.presentation.cli.print : renderProjectMarkdown;
import uim.myfiori.presentation.web.print : renderProjectHtml;
import uim.myfiori.presentation.cli.args;
import uim.myfiori.presentation.cli.table;
import uim.myfiori.presentation.http.errors : BadRequestException;
import uim.myfiori.presentation.http.exchange : delimiterOf;
import uim.myfiori.presentation.odata.model : toODataJson, reportToJson;
import uim.myfiori.presentation.web.helpers : de, percent, shortId;


enum helpText = `grundschutz ` ~ appVersion ~ ` – BSI IT-Grundschutz project management

Usage: grundschutz [global options] <command> [arguments] [options]

Server
  serve                                  start HTTP server (OData v4, web GUI, Fiori app)
  gui                                    start server and open the web GUI in a webview window

Projects
  project list
  project show <id>
  project create --name N [--scope S] [--description D] [--owner O] [--approach basic|standard|core]
  project update <id> [--name N] [--scope S] [--description D] [--owner O] [--approach A]
                      [--status planned|inProgress|completed|archived]
  project delete <id> --yes
  project print <id> [--format markdown|html] [--output FILE]
  project export <id> [--output FILE]          project with target objects, requirements, risks
  project import --input FILE [--new-ids] [--dry-run]

Target objects (Zielobjekte)
  object list [--project ID]
  object create --project ID --name N [--kind K] [--description D]
                [--c normal|high|veryHigh] [--i ...] [--a ...] [--rationale R]
  object update <id> [--name N] [--kind K] [--c ..] [--i ..] [--a ..] [--rationale R]
  object delete <id>
    kinds: businessProcess, application, itSystem, icsSystem, iotSystem, room, building,
           network, communicationLink

Requirements (IT-Grundschutz-Check)
  requirement list [--project ID] [--object ID] [--status S]
  requirement apply --object ID --module CODE      apply a Kompendium module (e.g. SYS.1.1)
  requirement set <id> [--status open|yes|partially|no|dispensable] [--note N]
                       [--responsible R] [--due YYYY-MM-DD]
  requirement delete <id>

Risks (BSI-Standard 200-3)
  risk list [--project ID] [--object ID]
  risk create --object ID --threat "G 0.xx" --title T [--description D]
              [--frequency 1-4] [--impact 1-4] [--treatment open|avoid|reduce|transfer|accept] [--note N]
  risk update <id> [--frequency 1-4] [--impact 1-4] [--treatment T] [--note N]
  risk delete <id>

Reporting & catalog
  report <projectId>
  catalog modules | catalog requirements <MODULE> | catalog threats

Import / export (entities: projects, targetObjects, requirements, risks; export also modules, threats)
  export <entity> [--format csv|json] [--project ID] [--delimiter comma|semicolon|tab] [--output FILE]
  import <entity> --input FILE [--format auto|csv|json] [--mode create|upsert|skip] [--dry-run]
                  [--project ID]           assign target objects to / restrict rows to this project
    imports are all-or-nothing; all business rules apply

Backup & restore (complete data set, SHA-256 checksum)
  backup [--label L]                     write a backup into the backup directory
  backup --output FILE                   write a backup to FILE ("-" = stdout)
  backup list                            list backups in the backup directory
  restore <FILE|backup-name> [--dry-run] [--yes]
    without --yes the backup is only validated; before restoring, the current state is backed up

Global options
  --json              machine readable output
  --data FILE         JSON data file (default from config / GS_DATA_FILE)
  --memory            volatile in-memory storage
  --config DIR        configuration directory (default: config)
  --host H --port P   listener for serve/gui
  --no-browser        gui: start the server without opening a window

IDs may be abbreviated to any unique prefix (e.g. the first 8 characters).
`;

/// Callback used to run the HTTP server (injected by app.d to keep the CLI testable).
/// Signals a failed import whose report was already printed.
private class ImportFailed : Exception { this() @safe pure nothrow { super("import failed"); } }

private enum exchangeEntityList = "projects, targetObjects, requirements, risks, modules, threats";

alias ServerRunner = int delegate(DApplicationContainer app, bool openGui) @safe;

class DCommandLine {
  private DApplicationContainer _app;
  private void delegate(string) @safe _out;
  private ServerRunner _server;
  private bool _json;

  this(DApplicationContainer app, ServerRunner server = null, void delegate(string) @safe output = null) {
    _app = app;
    _server = server;
    _out = output !is null ? output : (string s) @trusted { stdout.write(s); };
  }

  /// Executes one command; returns the process exit code.
  int run(CliArgs a) {
    _json = a.flag("json");
    try {
      if (a.positional.length == 0 || a.flag("help") || a.positional[0] == "help") { print(helpText); return 0; }
      switch (a.positional[0]) {
        case "version": print(appVersion ~ "\n"); return 0;
        case "serve": return serve(false);
        case "gui": return serve(!a.flag("no-browser"));
        case "project": projectCommand(a); return 0;
        case "object": objectCommand(a); return 0;
        case "requirement": requirementCommand(a); return 0;
        case "risk": riskCommand(a); return 0;
        case "report": report(a); return 0;
        case "catalog": catalogCommand(a); return 0;
        case "backup": backup(a); return 0;
        case "restore": return restore(a);
        case "export": exportCommand(a); return 0;
        case "import": return importCommand(a);
        default: throw new BadRequestException("Unknown command '" ~ a.positional[0] ~ "' (see 'grundschutz help')");
      }
    } catch (ImportFailed) {
      return 4;
    } catch (BadRequestException e) {
      error(e.msg); return 2;
    } catch (EntityNotFoundException e) {
      error(e.msg); return 3;
    } catch (DomainException e) {
      error(e.msg); return 4;
    } catch (Exception e) {
      error("Unexpected error: " ~ e.msg); return 1;
    }
  }

  private int serve(bool gui) {
    if (_server is null) throw new BadRequestException("Server mode is not available");
    return _server(_app, gui);
  }

  // -------------------------------------------------------------- projects

  private void projectCommand(CliArgs a) {
    auto sub = a.arg(1, "project sub-command (list|show|create|update|delete)");
    switch (sub) {
      case "list":
        auto items = _app.projects.list;
        if (_json) return printJson(items);
        print(renderTable(["ID", "Name", "Vorgehen", "Status", "Erfüllung"], items.map!(p => [shortId(p.ID), p.name,
            de(p.approach), de(p.status), percent(_app.reports.projectReport(p.ID).complianceDegree)]).array));
        return;
      case "show":
        auto p = _app.projects.get(resolveProject(a.arg(2, "project id")));
        if (_json) return printJson(p);
        print(format("ID:           %s\nName:         %s\nScope:        %s\nBeschreibung: %s\nVerantwortl.: %s\nVorgehen:     %s-Absicherung\nStatus:       %s\nAngelegt:     %s\nGeändert:     %s\n",
            p.ID, p.name, p.scope_, p.description, p.owner, de(p.approach), de(p.status), p.createdAt, p.modifiedAt));
        return;
      case "create":
        auto p = _app.projects.create(CreateProjectInput(a.required("name"), a.opt("description"), a.opt("scope"),
            a.opt("owner"), a.opt("approach", "standard")));
        return created("Project", p.ID, p);
      case "update":
        UpdateProjectInput u;
        setIf(u.name, a, "name"); setIf(u.description, a, "description"); setIf(u.scope_, a, "scope");
        setIf(u.owner, a, "owner"); setIf(u.approach, a, "approach"); setIf(u.status, a, "status");
        auto p = _app.projects.update(resolveProject(a.arg(2, "project id")), u);
        return done("Project updated", p);
      case "print":
        auto dossier = _app.reports.dossier(resolveProject(a.arg(2, "project id")));
        auto fmt = a.opt("format", "markdown");
        if (fmt != "markdown" && fmt != "html") throw new BadRequestException("--format must be markdown or html");
        return output(a, fmt == "html" ? renderProjectHtml(dossier) : renderProjectMarkdown(dossier));
      case "export":
        return output(a, _app.exchange.exportProject(resolveProject(a.arg(2, "project id"))));
      case "import":
        auto report = _app.exchange.importProject(input(a), a.flag("new-ids"), a.flag("dry-run"));
        printReport(report);
        if (report.failed) throw new ImportFailed;
        return;
      case "delete":
        auto id = resolveProject(a.arg(2, "project id"));
        if (!a.flag("yes")) throw new BadRequestException("Deleting a project removes all its data; confirm with --yes");
        _app.projects.remove(id);
        return done("Project deleted: " ~ id);
      default: throw new BadRequestException("Unknown project sub-command '" ~ sub ~ "'");
    }
  }

  // -------------------------------------------------------------- target objects

  private void objectCommand(CliArgs a) {
    auto sub = a.arg(1, "object sub-command (list|create|update|delete)");
    switch (sub) {
      case "list":
        auto items = _app.targetObjects.list(a.flag("project") ? resolveProject(a.opt("project")) : "");
        if (_json) return printJson(items);
        print(renderTable(["ID", "Name", "Typ", "V", "I", "A", "Max"], items.map!(o => [shortId(o.ID), o.name,
            de(o.kind), de(o.confidentiality), de(o.integrity), de(o.availability), de(o.protectionLevel)]).array));
        return;
      case "create":
        auto o = _app.targetObjects.create(CreateTargetObjectInput(resolveProject(a.required("project")),
            a.required("name"), a.opt("kind", "itSystem"), a.opt("description"), a.opt("c", "normal"),
            a.opt("i", "normal"), a.opt("a", "normal"), a.opt("rationale")));
        return created("Target object", o.ID, o);
      case "update":
        UpdateTargetObjectInput u;
        setIf(u.name, a, "name"); setIf(u.kind, a, "kind"); setIf(u.description, a, "description");
        setIf(u.confidentiality, a, "c"); setIf(u.integrity, a, "i"); setIf(u.availability, a, "a");
        setIf(u.protectionRationale, a, "rationale");
        return done("Target object updated", _app.targetObjects.update(resolveObject(a.arg(2, "object id")), u));
      case "delete":
        auto id = resolveObject(a.arg(2, "object id"));
        _app.targetObjects.remove(id);
        return done("Target object deleted: " ~ id);
      default: throw new BadRequestException("Unknown object sub-command '" ~ sub ~ "'");
    }
  }

  // -------------------------------------------------------------- requirements

  private void requirementCommand(CliArgs a) {
    auto sub = a.arg(1, "requirement sub-command (list|apply|set|delete)");
    switch (sub) {
      case "list":
        auto items = _app.requirements.list(a.flag("project") ? resolveProject(a.opt("project")) : "",
            a.flag("object") ? resolveObject(a.opt("object")) : "");
        if (a.flag("status")) items = items.filter!(r => r.status == a.opt("status")).array;
        if (_json) return printJson(items);
        print(renderTable(["ID", "Code", "Titel", "Art", "Status", "Verantw."], items.map!(r => [shortId(r.ID), r.code,
            r.title, de(r.level), de(r.status), r.responsible]).array));
        return;
      case "apply":
        auto items = _app.requirements.applyModule(resolveObject(a.required("object")), a.required("module"));
        if (_json) return printJson(items);
        return done(format("%d requirements created from %s", items.length, a.opt("module")));
      case "set":
        UpdateRequirementInput u;
        setIf(u.status, a, "status"); setIf(u.note, a, "note"); setIf(u.responsible, a, "responsible");
        setIf(u.dueDate, a, "due"); setIf(u.title, a, "title");
        auto r = _app.requirements.update(resolveRequirement(a.arg(2, "requirement id")), u);
        return done(r.code ~ ": " ~ de(r.status), r);
      case "delete":
        auto id = resolveRequirement(a.arg(2, "requirement id"));
        _app.requirements.remove(id);
        return done("Requirement deleted: " ~ id);
      default: throw new BadRequestException("Unknown requirement sub-command '" ~ sub ~ "'");
    }
  }

  // -------------------------------------------------------------- risks

  private void riskCommand(CliArgs a) {
    auto sub = a.arg(1, "risk sub-command (list|create|update|delete)");
    switch (sub) {
      case "list":
        auto items = _app.risks.list(a.flag("project") ? resolveProject(a.opt("project")) : "",
            a.flag("object") ? resolveObject(a.opt("object")) : "");
        if (_json) return printJson(items);
        print(renderTable(["ID", "Gefährdung", "Titel", "H", "S", "Risiko", "Behandlung"], items.map!(r => [shortId(r.ID),
            r.threatCode, r.title, r.frequency.to!string, r.impact.to!string, de(r.level), de(r.treatment)]).array));
        return;
      case "create":
        auto r = _app.risks.create(CreateRiskInput(resolveObject(a.required("object")), a.required("threat"),
            a.required("title"), a.opt("description"), number(a.opt("frequency", "1")), number(a.opt("impact", "1")),
            a.opt("treatment", "open"), a.opt("note")));
        return created("Risk (" ~ de(r.level) ~ ")", r.ID, r);
      case "update":
        UpdateRiskInput u;
        if (a.flag("frequency")) u.frequency = number(a.opt("frequency"));
        if (a.flag("impact")) u.impact = number(a.opt("impact"));
        setIf(u.treatment, a, "treatment"); setIf(u.treatmentNote, a, "note"); setIf(u.title, a, "title");
        setIf(u.description, a, "description");
        auto r = _app.risks.update(resolveRisk(a.arg(2, "risk id")), u);
        return done("Risk updated: " ~ de(r.level) ~ ", " ~ de(r.treatment), r);
      case "delete":
        auto id = resolveRisk(a.arg(2, "risk id"));
        _app.risks.remove(id);
        return done("Risk deleted: " ~ id);
      default: throw new BadRequestException("Unknown risk sub-command '" ~ sub ~ "'");
    }
  }

  // -------------------------------------------------------------- report / catalog / backup

  private void report(CliArgs a) @trusted {
    auto r = _app.reports.projectReport(resolveProject(a.arg(1, "project id")));
    if (_json) { print(reportToJson(r).toPrettyString ~ "\n"); return; }
    print(format("Projekt:          %s (%s-Absicherung, %s)\n", r.project.name, de(r.project.approach), de(r.project.status)));
    print(format("Zielobjekte:      %d\n", r.targetObjectCount));
    print(format("Schutzbedarf:     V %s / I %s / A %s  → %s\n", de(r.confidentiality), de(r.integrity),
        de(r.availability), de(r.protectionLevel)));
    print(format("Risikoanalyse:    %s\n", r.objectsRequiringRiskAnalysis.length ? r.objectsRequiringRiskAnalysis.join(", ") : "–"));
    print(format("Anforderungen:    %d relevant: %d ja, %d teilweise, %d nein, %d offen, %d entbehrlich\n",
        r.requirementsTotal, r.requirementsFulfilled, r.requirementsPartially, r.requirementsNotFulfilled,
        r.requirementsOpen, r.requirementsDispensable));
    print(format("Erfüllungsgrad:   %s\n", percent(r.complianceDegree)));
    print(format("Basis-Absich.:    %s\n", r.basicProtectionAchieved ? "erreicht" : r.basicRequirementsOpen.to!string ~ " Basis-Anforderungen offen"));
    print(format("Risiken:          %d (gering %d, mittel %d, hoch %d, sehr hoch %d; unbehandelt %d)\n",
        r.risksTotal, r.risksLow, r.risksMedium, r.risksHigh, r.risksVeryHigh, r.risksUntreated));
  }

  private void catalogCommand(CliArgs a) {
    auto sub = a.arg(1, "catalog sub-command (modules|requirements|threats)");
    switch (sub) {
      case "modules":
        auto m = _app.catalog.modules;
        if (_json) return printJson(m);
        print(renderTable(["Code", "Titel", "Schicht", "Anf."], m.map!(x => [x.code, x.title, x.layer, x.requirementCount.to!string]).array));
        return;
      case "requirements":
        auto r = _app.catalog.requirementsOf(a.arg(2, "module code"));
        if (_json) return printJson(r);
        print(renderTable(["Code", "Titel", "Art"], r.map!(x => [x.code, x.title, de(x.level)]).array, 90));
        return;
      case "threats":
        auto t = _app.catalog.threats;
        if (_json) return printJson(t);
        print(renderTable(["Code", "Titel"], t.map!(x => [x.code, x.title]).array, 90));
        return;
      default: throw new BadRequestException("Unknown catalog sub-command '" ~ sub ~ "'");
    }
  }

  // -------------------------------------------------------------- import / export / backup

  private void exportCommand(CliArgs a) {
    auto entity = a.arg(1, "entity (" ~ exchangeEntityList ~ ")");
    auto delimiter = a.opt("delimiter", ",");
    output(a, _app.exchange.exportEntities(entity, a.opt("format", "json"),
        a.flag("project") ? resolveProject(a.opt("project")) : "", delimiterOf(delimiter)));
  }

  private int importCommand(CliArgs a) {
    auto report = _app.exchange.importEntities(a.arg(1, "entity"), a.opt("format", "auto"), input(a),
        a.opt("mode", "create"), a.flag("dry-run"), a.flag("project") ? resolveProject(a.opt("project")) : "");
    printReport(report);
    return report.failed ? 4 : 0;
  }

  private void backup(CliArgs a) @trusted {
    if (a.positional.length > 1 && a.positional[1] == "list") {
      auto list = _app.backups.listBackups;
      if (_json) return printJsonValue(serializeToJson(list));
      print(renderTable(["Name", "Zeitpunkt", "Größe"], list.map!(b => [b.name, b.createdAt,
          format("%.1f KB", b.size / 1024.0)]).array, 80));
      return;
    }
    if (a.flag("output")) {
      output(a, _app.backups.createBackup);
      if (a.opt("output") != "-") done("Backup written: " ~ a.opt("output"));
      return;
    }
    auto info = _app.backups.backupToFile(a.opt("label", "cli"));
    if (_json) return printJsonValue(serializeToJson(info));
    done("Backup written: " ~ _app.config.backupDir ~ "/" ~ info.name);
  }

  private int restore(CliArgs a) @trusted {
    import std.file : exists, readText;
    auto source = a.arg(1, "backup file or name");
    auto dryRun = a.flag("dry-run") || !a.flag("yes");
    auto report = source.exists ? _app.backups.restore(readText(source), dryRun)
                                : _app.backups.restoreFromFile(source, dryRun);
    if (_json) { printJsonValue(serializeToJson(report)); return report.valid ? 0 : 4; }
    print(format("Backup:       %s (version %s)
Content:      %d projects, %d target objects, %d requirements, %d risks
",
        report.createdAt, report.applicationVersion, report.projects, report.targetObjects, report.requirements, report.risks));
    foreach (issue; report.issues) print("  ✗ " ~ issue ~ "
");
    if (!report.valid) { print("Result:       INVALID – nothing restored
"); return 4; }
    if (report.restored) print("Result:       restored. Previous state saved as " ~ report.safetyBackup ~ "
");
    else print("Result:       valid" ~ (a.flag("dry-run") ? " (dry run)" : " – add --yes to replace the current data") ~ "
");
    return 0;
  }

  private void printReport(ImportReport r) @trusted {
    if (_json) return printJsonValue(serializeToJson(r));
    print(format("%s: %d rows – %d created, %d updated, %d skipped, %d failed%s
", r.entity, r.total, r.created,
        r.updated, r.skipped, r.failed, r.committed ? "" : r.dryRun ? " (dry run, nothing saved)" : " – nothing imported"));
    if (r.issues.length)
      print(renderTable(["Row", "ID", "Problem"], r.issues.map!(i => [i.row.to!string, shortId(i.id), i.message]).array, 100));
  }

  /// Reads --input FILE ("-" = stdin).
  private static string input(CliArgs a) @trusted {
    import std.file : readText;
    import std.stdio : stdin, KeepTerminator;
    auto path = a.required("input");
    if (path == "-") {
      string text;
      foreach (line; stdin.byLine(KeepTerminator.yes)) text ~= line;
      return text;
    }
    return readText(path);
  }

  /// Writes to --output FILE or stdout.
  private void output(CliArgs a, string content) @trusted {
    import std.file : write;
    auto path = a.opt("output", "-");
    if (path == "-") { print(content); if (content.length && content[$ - 1] != '\n') print("\n"); }
    else write(path, content);
  }

  private void printJsonValue(Json j) @trusted { print(j.toPrettyString ~ "\n"); }

  // -------------------------------------------------------------- id resolution (unique prefix)

  private string resolveProject(string p) { return resolve("Project", p, _app.projects.list.map!(x => x.ID).array); }
  private string resolveObject(string p) { return resolve("TargetObject", p, _app.targetObjects.list.map!(x => x.ID).array); }
  private string resolveRequirement(string p) { return resolve("Requirement", p, _app.requirements.list.map!(x => x.ID).array); }
  private string resolveRisk(string p) { return resolve("Risk", p, _app.risks.list.map!(x => x.ID).array); }

  private static string resolve(string entity, string prefix, string[] ids) {
    if (prefix.length == 0) throw new BadRequestException(entity ~ " id is required");
    string[] hits;
    foreach (id; ids) {
      if (id == prefix) return id;
      if (id.startsWith(prefix)) hits ~= id;
    }
    if (hits.length == 1) return hits[0];
    if (hits.length > 1) throw new BadRequestException(format("%s id prefix '%s' is ambiguous (%d matches)", entity, prefix, hits.length));
    throw new EntityNotFoundException(entity, prefix);
  }

  // -------------------------------------------------------------- output helpers

  private void print(string s) { _out(s); }

  private void error(string msg) @trusted {
    if (_json) {
      auto j = Json.emptyObject;
      j["error"] = msg;
      _out(j.toString ~ "\n");
    } else stderr.writeln("error: ", msg);
  }

  private void printJson(T)(T value) @trusted {
    static if (is(T : U[], U)) {
      auto arr = Json.emptyArray;
      foreach (v; value) arr ~= toODataJson(v);
      print(arr.toPrettyString ~ "\n");
    } else print(toODataJson(value).toPrettyString ~ "\n");
  }

  private void created(T)(string what, string id, T dto) {
    if (_json) return printJson(dto);
    print(what ~ " created: " ~ id ~ "\n");
  }

  private void done(T)(string message, T dto) {
    if (_json) return printJson(dto);
    print(message ~ "\n");
  }

  private void done(string message) @trusted {
    if (_json) {
      auto j = Json.emptyObject;
      j["result"] = message;
      print(j.toString ~ "\n");
    } else print(message ~ "\n");
  }

  private static void setIf(N)(ref N field, CliArgs a, string name) {
    if (a.flag(name)) field = a.opt(name);
  }

  private static int number(string v) {
    try return v.to!int;
    catch (ConvException) throw new BadRequestException("'" ~ v ~ "' is not a number");
  }
}
