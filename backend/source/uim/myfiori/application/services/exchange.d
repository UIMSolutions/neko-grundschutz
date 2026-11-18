/// Import / export of entities (JSON, CSV) and of complete projects (JSON bundle).
module uim.myfiori.application.services.exchange;

@safe:

import std.algorithm : canFind, map;
import std.array : array, join;
import std.conv : to, ConvException;
import std.datetime.systime : Clock;
import std.string : strip, toLower;
import std.traits : FieldNameTuple;
import std.typecons : Nullable;
import std.uuid : randomUUID;
import vibe.data.json;

import uim.myfiori.application.dtos;
import uim.myfiori.application.services.csv;
import uim.myfiori.domain.exceptions;
import uim.myfiori.ports.services;
import uim.myfiori.ports.storages : ITransactionManager;
import uim.myfiori.ports.usecases;

enum exportFormat = "grundschutz-export";
enum projectBundleFormat = "grundschutz-project";
enum exchangeFormatVersion = 1;

class DExchangeService : IExchangeService {
  private IProjectUseCases _projects;
  private ITargetObjectUseCases _objects;
  private IRequirementUseCases _requirements;
  private IRiskUseCases _risks;
  private ICatalogService _catalog;
  private ITransactionManager _tx;
  private string _appVersion;

  this(IProjectUseCases projects, ITargetObjectUseCases objects, IRequirementUseCases requirements,
      IRiskUseCases risks, ICatalogService catalog, ITransactionManager tx, string appVersion) {
    _projects = projects;
    _objects = objects;
    _requirements = requirements;
    _risks = risks;
    _catalog = catalog;
    _tx = tx;
    _appVersion = appVersion;
  }

  // ================================================================== export

  string exportEntities(string entity, string format, string projectId = "", char delimiter = ',') {
    checkFormat(format, false);
    switch (entity) {
      case "projects":
        return render(projectId.length ? [_projects.get(projectId)] : _projects.list, entity, format, delimiter);
      case "targetObjects": return render(_objects.list(projectId), entity, format, delimiter);
      case "requirements": return render(_requirements.list(projectId), entity, format, delimiter);
      case "risks": return render(_risks.list(projectId), entity, format, delimiter);
      case "modules": return render(_catalog.modules, entity, format, delimiter);
      case "threats": return render(_catalog.threats, entity, format, delimiter);
      default: throw new ValidationException(unknownEntity(entity));
    }
  }

  string exportProject(string projectId) @trusted {
    auto doc = header(projectBundleFormat);
    doc["project"] = toJson(_projects.get(projectId));
    doc["targetObjects"] = toJsonArray(_objects.list(projectId));
    doc["requirements"] = toJsonArray(_requirements.list(projectId));
    doc["risks"] = toJsonArray(_risks.list(projectId));
    return doc.toPrettyString;
  }

  private string render(T)(T[] dtos, string entity, string format, char delimiter) @trusted {
    if (format == "csv")
      return writeCsv(columns!T, dtos.map!(d => cells(d)).array, delimiter);
    auto doc = header(exportFormat);
    doc["entity"] = entity;
    doc["count"] = dtos.length;
    doc["items"] = toJsonArray(dtos);
    return doc.toPrettyString;
  }

  private Json header(string format) @trusted {
    auto doc = Json.emptyObject;
    doc["format"] = format;
    doc["formatVersion"] = exchangeFormatVersion;
    doc["application"] = "grundschutz " ~ _appVersion;
    doc["exportedAt"] = Clock.currTime.toUTC.toISOExtString;
    return doc;
  }

  // ================================================================== import

  ImportReport importEntities(string entity, string format, string content, string mode = "create",
      bool dryRun = false, string projectId = "") {
    if (projectId.length) _projects.get(projectId);   // 404 for unknown projects
    if (!importableEntities.canFind(entity))
      throw new ValidationException(entity ~ " cannot be imported; importable: " ~ importableEntities.join(", "));
    if (!["create", "upsert", "skip"].canFind(mode))
      throw new ValidationException("Invalid import mode '" ~ mode ~ "' (create, upsert, skip)");
    checkFormat(format, true);
    bool csv;
    auto items = parseItems(entity, format, content, csv);

    ImportReport rep;
    rep.entity = entity;
    rep.dryRun = dryRun;
    rep.total = cast(int) items.length;
    transaction(rep, dryRun, {
      foreach (i, item; items) {
        auto row = cast(int) i + (csv ? 2 : 1);
        try {
          if (projectId.length) scopeToProject(entity, item, projectId);
          final switch (importRow(entity, item, mode)) {
            case Outcome.created: rep.created++; break;
            case Outcome.updated: rep.updated++; break;
            case Outcome.skipped: rep.skipped++; break;
          }
        } catch (Exception e) {
          rep.failed++;
          rep.issues ~= ImportIssue(row, text(item, "ID"), e.msg);
        }
      }
    });
    return rep;
  }

  ImportReport importProject(string content, bool newIds = false, bool dryRun = false) @trusted {
    Json doc;
    try doc = parseJsonString(content);
    catch (Exception e) throw new ValidationException("Project file is not valid JSON: " ~ e.msg);
    if (doc.type != Json.Type.object || doc["format"].opt!string != projectBundleFormat)
      throw new ValidationException("Not a project export (format must be '" ~ projectBundleFormat ~ "')");
    if (doc["formatVersion"].opt!long(0) > exchangeFormatVersion)
      throw new ValidationException("Project export format version is newer than supported");

    auto project = doc["project"];
    auto objects = arrayOf(doc, "targetObjects");
    auto requirements = arrayOf(doc, "requirements");
    auto risks = arrayOf(doc, "risks");

    string[string] ids;   // old id -> new id
    string map(string old) {
      if (!newIds || old.length == 0) return old;
      if (auto n = old in ids) return *n;
      return ids[old] = randomUUID.toString;
    }

    ImportReport rep;
    rep.entity = "project";
    rep.dryRun = dryRun;
    rep.total = cast(int) (1 + objects.length + requirements.length + risks.length);
    int row;
    void attempt(Json item, void delegate() @safe action) {
      row++;
      try { action(); rep.created++; }
      catch (Exception e) {
        rep.failed++;
        rep.issues ~= ImportIssue(row, text(item, "ID"), e.msg);
      }
    }

    transaction(rep, dryRun, {
      string projectId;
      attempt(project, {
        if (!newIds && text(project, "ID").length && exists("projects", text(project, "ID")))
          throw new ConflictException("Project '" ~ text(project, "ID") ~ "' already exists – import with new ids to create a copy");
        auto p = _projects.create(CreateProjectInput(text(project, "name"), text(project, "description"),
            text(project, "scope"), text(project, "owner"), text(project, "approach", "standard"), map(text(project, "ID"))));
        projectId = p.ID;
      });
      if (projectId.length == 0) return;
      foreach (o; objects) attempt(o, { createObject(o, projectId, map(text(o, "ID"))); });
      foreach (q; requirements) attempt(q, { createRequirement(q, map(text(q, "targetObjectId")), map(text(q, "ID"))); });
      foreach (k; risks) attempt(k, { createRisk(k, map(text(k, "targetObjectId")), map(text(k, "ID"))); });
      // status last: an archived project would reject its children
      row = 1;
      try applyStatus(projectId, text(project, "status", "planned"));
      catch (Exception e) { rep.failed++; rep.issues ~= ImportIssue(1, projectId, e.msg); }
    });
    return rep;
  }

  // ------------------------------------------------------------------ rows

  private enum Outcome { created, updated, skipped }

  private Outcome importRow(string entity, Json it, string mode) {
    auto id = text(it, "ID");
    if (id.length && exists(entity, id)) {
      if (mode == "skip") return Outcome.skipped;
      if (mode == "create") throw new ConflictException("'" ~ id ~ "' already exists (use mode upsert or skip)");
      update(entity, id, it);
      return Outcome.updated;
    }
    switch (entity) {
      case "projects":
        auto p = _projects.create(CreateProjectInput(text(it, "name"), text(it, "description"), text(it, "scope"),
            text(it, "owner"), text(it, "approach", "standard"), id));
        applyStatus(p.ID, text(it, "status", "planned"));
        break;
      case "targetObjects": createObject(it, text(it, "projectId"), id); break;
      case "requirements": createRequirement(it, text(it, "targetObjectId"), id); break;
      case "risks": createRisk(it, text(it, "targetObjectId"), id); break;
      default: assert(false, entity);
    }
    return Outcome.created;
  }

  /// Restricts a row to one project (import from within a project).
  private void scopeToProject(string entity, ref Json it, string projectId) @trusted {
    switch (entity) {
      case "targetObjects": it["projectId"] = projectId; break;
      case "requirements", "risks":
        auto objectId = text(it, "targetObjectId");
        if (_objects.get(objectId).projectId != projectId)
          throw new ValidationException("Target object '" ~ objectId ~ "' does not belong to this project");
        break;
      case "projects":
        if (text(it, "ID") != projectId) throw new ValidationException("Only the current project can be imported here");
        break;
      default: break;
    }
  }

  private void createObject(Json it, string projectId, string id) {
    _objects.create(CreateTargetObjectInput(projectId, text(it, "name"), text(it, "kind", "itSystem"),
        text(it, "description"), text(it, "confidentiality", "normal"), text(it, "integrity", "normal"),
        text(it, "availability", "normal"), text(it, "protectionRationale"), id));
  }

  private void createRequirement(Json it, string targetObjectId, string id) {
    _requirements.create(CreateRequirementInput(targetObjectId, text(it, "code"), text(it, "title"),
        text(it, "level", "basic"), text(it, "status", "open"), text(it, "responsible"), text(it, "note"),
        text(it, "dueDate"), id));
  }

  private void createRisk(Json it, string targetObjectId, string id) {
    _risks.create(CreateRiskInput(targetObjectId, text(it, "threatCode"), text(it, "title"), text(it, "description"),
        number(it, "frequency", 1), number(it, "impact", 1), text(it, "treatment", "open"), text(it, "treatmentNote"), id));
  }

  private void update(string entity, string id, Json it) {
    switch (entity) {
      case "projects":
        UpdateProjectInput u;
        u.name = opt(it, "name"); u.description = opt(it, "description"); u.scope_ = opt(it, "scope");
        u.owner = opt(it, "owner"); u.approach = opt(it, "approach");
        _projects.update(id, u);
        if (has(it, "status")) applyStatus(id, text(it, "status"));
        return;
      case "targetObjects":
        UpdateTargetObjectInput u;
        u.name = opt(it, "name"); u.kind = opt(it, "kind"); u.description = opt(it, "description");
        u.confidentiality = opt(it, "confidentiality"); u.integrity = opt(it, "integrity");
        u.availability = opt(it, "availability"); u.protectionRationale = opt(it, "protectionRationale");
        _objects.update(id, u);
        return;
      case "requirements":
        UpdateRequirementInput u;
        u.title = opt(it, "title"); u.status = opt(it, "status"); u.responsible = opt(it, "responsible");
        u.note = opt(it, "note"); u.dueDate = opt(it, "dueDate");
        _requirements.update(id, u);
        return;
      case "risks":
        UpdateRiskInput u;
        u.title = opt(it, "title"); u.description = opt(it, "description");
        if (has(it, "frequency")) u.frequency = number(it, "frequency", 1);
        if (has(it, "impact")) u.impact = number(it, "impact", 1);
        u.treatment = opt(it, "treatment"); u.treatmentNote = opt(it, "treatmentNote");
        _risks.update(id, u);
        return;
      default: assert(false, entity);
    }
  }

  /// Moves a project along the allowed status path to `target`.
  private void applyStatus(string projectId, string target) {
    auto current = _projects.get(projectId).status;
    if (current == target || target.length == 0) return;
    string[] path;
    switch (target) {
      case "inProgress": path = ["inProgress"]; break;
      case "completed": path = current == "inProgress" ? ["completed"] : ["inProgress", "completed"]; break;
      case "archived": path = ["archived"]; break;
      case "planned": throw new ConflictException("A project cannot be set back to 'planned'");
      default: throw new ValidationException("Invalid project status '" ~ target ~ "'");
    }
    foreach (s; path) {
      UpdateProjectInput u;
      u.status = s;
      _projects.update(projectId, u);
    }
  }

  private bool exists(string entity, string id) {
    try {
      switch (entity) {
        case "projects": _projects.get(id); return true;
        case "targetObjects": _objects.get(id); return true;
        case "requirements": _requirements.get(id); return true;
        case "risks": _risks.get(id); return true;
        default: return false;
      }
    } catch (EntityNotFoundException) return false;
  }

  /// Runs `work` in one transaction: committed only if nothing failed and it is no dry run.
  private void transaction(ref ImportReport rep, bool dryRun, void delegate() @safe work) {
    _tx.begin();
    try work();
    catch (Exception e) { _tx.rollback(); throw e; }
    if (dryRun || rep.failed > 0) _tx.rollback();
    else {
      _tx.commit();
      rep.committed = true;
    }
  }

  // ------------------------------------------------------------------ parsing

  private Json[] parseItems(string entity, string format, string content, out bool csv) @trusted {
    auto f = format.toLower;
    if (f == "auto" || f.length == 0) {
      auto t = content.strip;
      f = t.length && (t[0] == '[' || t[0] == '{') ? "json" : "csv";
    }
    csv = f == "csv";
    if (csv) {
      auto rows = parseCsv(content, detectDelimiter(content));
      if (rows.length == 0) return null;
      auto head = rows[0].map!(h => h.strip).array;
      Json[] items;
      foreach (r; rows[1 .. $]) {
        auto o = Json.emptyObject;
        foreach (i, h; head) if (h.length && i < r.length) o[h] = r[i];
        items ~= o;
      }
      return items;
    }
    Json doc;
    try doc = parseJsonString(content);
    catch (Exception e) throw new ValidationException("Invalid JSON: " ~ e.msg);
    if (doc.type == Json.Type.array) return doc.get!(Json[]);
    if (doc.type == Json.Type.object && doc["items"].type == Json.Type.array) {
      if (doc["entity"].type == Json.Type.string && doc["entity"].get!string != entity)
        throw new ValidationException("File contains '" ~ doc["entity"].get!string ~ "', not '" ~ entity ~ "'");
      return doc["items"].get!(Json[]);
    }
    throw new ValidationException("JSON must be an array or an export document with 'items'");
  }

  private static Json[] arrayOf(Json doc, string key) @trusted {
    auto v = doc[key];
    if (v.type == Json.Type.undefined || v.type == Json.Type.null_) return null;
    if (v.type != Json.Type.array) throw new ValidationException("'" ~ key ~ "' must be an array");
    return v.get!(Json[]);
  }

  private static void checkFormat(string format, bool allowAuto) {
    if (!(format == "json" || format == "csv" || (allowAuto && (format == "auto" || format.length == 0))))
      throw new ValidationException("Invalid format '" ~ format ~ "' (json, csv" ~ (allowAuto ? ", auto" : "") ~ ")");
  }

  private static string unknownEntity(string e) {
    return "Unknown entity '" ~ e ~ "'; available: " ~ exchangeEntities.join(", ");
  }
}

// ==================================================================== DTO helpers

/// Exported property name of a DTO field ("scope_" -> "scope").
private string publicName(string field) { return field == "scope_" ? "scope" : field; }

/// CSV header of a DTO type (declaration order).
string[] columns(T)() {
  string[] r;
  static foreach (f; FieldNameTuple!T) r ~= publicName(f);
  return r;
}

/// CSV cells of a DTO.
string[] cells(T)(T dto) {
  string[] r;
  static foreach (f; FieldNameTuple!T) {{
    auto v = __traits(getMember, dto, f);
    static if (is(typeof(v) == string)) r ~= v;
    else static if (is(typeof(v) == string[])) r ~= v.join("; ");
    else r ~= v.to!string;
  }}
  return r;
}

Json toJson(T)(T dto) @trusted {
  auto j = serializeToJson(dto);
  if (j["scope_"].type != Json.Type.undefined) {
    j["scope"] = j["scope_"];
    j.remove("scope_");
  }
  return j;
}

Json toJsonArray(T)(T[] dtos) @trusted {
  auto a = Json.emptyArray;
  foreach (d; dtos) a ~= toJson(d);
  return a;
}

private bool has(Json it, string key) @trusted {
  auto v = it[key];
  return v.type != Json.Type.undefined && v.type != Json.Type.null_;
}

/// String value of a field (numbers/bools converted); `fallback` if missing or empty.
private string text(Json it, string key, string fallback = "") @trusted {
  auto v = it[key];
  string s;
  switch (v.type) {
    case Json.Type.string: s = v.get!string; break;
    case Json.Type.int_, Json.Type.float_, Json.Type.bool_, Json.Type.bigInt: s = v.toString; break;
    default: s = "";
  }
  return s.length ? s : fallback;
}

private Nullable!string opt(Json it, string key) @trusted {
  auto v = it[key];
  if (v.type == Json.Type.undefined) return Nullable!string.init;
  return Nullable!string(text(it, key));
}

private int number(Json it, string key, int fallback) {
  auto s = text(it, key).strip;
  if (s.length == 0) return fallback;
  try return s.to!int;
  catch (ConvException) throw new ValidationException("'" ~ key ~ "' must be an integer, got '" ~ s ~ "'");
}
