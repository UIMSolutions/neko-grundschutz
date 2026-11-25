/**
 * Backup & restore of the complete data set (all collections of the document store).
 *
 * Backup document:
 *   { "format": "grundschutz-backup", "formatVersion": 1, "schemaVersion": 1,
 *     "application": {...}, "createdAt": "...", "counts": {...},
 *     "checksum": "sha256:<hex of canonical JSON of data>", "data": { collection: { id: record } } }
 *
 * A restore is validated completely before anything is changed: format, checksum, every record
 * (decoded into domain entities) and all references. Before replacing the data a safety backup
 * of the current state is written to the backup directory.
 */
module uim.myfiori.persistence.storages.backup;

@safe:

import std.algorithm : canFind, endsWith, filter, map, sort, startsWith;
import std.array : array, appender;
import std.conv : to;
import std.datetime.systime : Clock;
import std.digest : toHexString, LetterCase;
import std.digest.sha : sha256Of;
import std.file : DirEntry, SpanMode, dirEntries, exists, isDir, mkdirRecurse, readText, remove, rename, write;
import std.path : baseName, buildPath;
import std.regex : ctRegex, matchFirst;
import std.string : replace;
import vibe.data.json;

import uim.myfiori.application.dtos : BackupInfo, RestoreReport;
import uim.myfiori.domain.exceptions;
import uim.myfiori.persistence.records : Collections, schemaVersion;
import uim.myfiori.persistence.repositories;
import uim.myfiori.persistence.storages.memory;
import uim.myfiori.ports.services : IBackupService;
import uim.myfiori.ports.storages;

enum backupFormat = "grundschutz-backup";
enum backupFormatVersion = 1;

class DBackupService : IBackupService {
  private IDocumentStorage _storage;
  private string _dir;
  private int _retention;
  private string _appVersion;
  private string _catalogEdition;

  this(IDocumentStorage storage, string backupDir, int retention, string appVersion, string catalogEdition) {
    _storage = storage;
    _dir = backupDir;
    _retention = retention;
    _appVersion = appVersion;
    _catalogEdition = catalogEdition;
  }

  string createBackup() @trusted {
    auto data = Json.emptyObject;
    auto counts = Json.emptyObject;
    foreach (collection, docs; _storage.snapshot) {
      auto c = Json.emptyObject;
      foreach (id, doc; docs) c[id] = doc;
      data[collection] = c;
      counts[collection] = docs.length;
    }
    auto app = Json.emptyObject;
    app["name"] = "grundschutz";
    app["version"] = _appVersion;
    auto doc = Json.emptyObject;
    doc["format"] = backupFormat;
    doc["formatVersion"] = backupFormatVersion;
    doc["schemaVersion"] = schemaVersion;
    doc["application"] = app;
    doc["catalogEdition"] = _catalogEdition;
    doc["storage"] = _storage.describe;
    doc["createdAt"] = Clock.currTime.toUTC.toISOExtString;
    doc["counts"] = counts;
    doc["checksum"] = checksum(data);
    doc["data"] = data;
    return doc.toPrettyString;
  }

  RestoreReport restore(string content, bool dryRun = false) @trusted {
    RestoreReport r;
    r.dryRun = dryRun;
    StorageSnapshot data;
    try data = validate(content, r);
    catch (Exception e) r.issues ~= e.msg;
    r.valid = r.issues.length == 0;
    if (!r.valid || dryRun) return r;

    // safety net: keep the current state before overwriting it
    try r.safetyBackup = backupToFile("pre-restore").name;
    catch (Exception e) {
      r.valid = false;
      r.issues ~= "Safety backup failed, restore aborted: " ~ e.msg;
      return r;
    }
    _storage.replaceAll(data);
    r.restored = true;
    return r;
  }

  BackupInfo backupToFile(string label = "") {
    if (!_dir.exists) mkdirRecurse(_dir);
    auto stamp = Clock.currTime.toUTC.toISOString.replace(".", "")[0 .. 15]; // YYYYMMDDTHHMMSS
    auto safeLabel = label.length ? "-" ~ sanitize(label) : "";
    auto name = "grundschutz-backup-" ~ stamp ~ "Z" ~ safeLabel ~ ".json";
    auto path = buildPath(_dir, name);
    for (int i = 2; path.exists; i++) {
      name = "grundschutz-backup-" ~ stamp ~ "Z" ~ safeLabel ~ "-" ~ i.to!string ~ ".json";
      path = buildPath(_dir, name);
    }
    auto text = createBackup();
    write(path ~ ".tmp", text);
    rename(path ~ ".tmp", path);
    applyRetention();
    return BackupInfo(name, Clock.currTime.toUTC.toISOExtString, cast(long) text.length);
  }

  BackupInfo[] listBackups() @trusted {
    if (!_dir.exists || !_dir.isDir) return null;
    BackupInfo[] result;
    foreach (DirEntry e; dirEntries(_dir, SpanMode.shallow)) {
      auto name = e.name.baseName;
      if (!isBackupName(name)) continue;
      result ~= BackupInfo(name, e.timeLastModified.toUTC.toISOExtString, cast(long) e.size);
    }
    result.sort!((a, b) => a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.name > b.name);   // newest first
    return result;
  }

  string readBackup(string name) {
    if (!isBackupName(name)) throw new ValidationException("Invalid backup name '" ~ name ~ "'");
    auto path = buildPath(_dir, name);
    if (!path.exists) throw new EntityNotFoundException("Backup", name);
    return readText(path);
  }

  RestoreReport restoreFromFile(string name, bool dryRun = false) {
    return restore(readBackup(name), dryRun);
  }

  // ---------------------------------------------------------------- validation

  private StorageSnapshot validate(string content, ref RestoreReport r) @trusted {
    Json doc;
    try doc = parseJsonString(content);
    catch (Exception e) throw new ValidationException("Backup is not valid JSON: " ~ e.msg);
    if (doc.type != Json.Type.object || doc["format"].opt!string != backupFormat)
      throw new ValidationException("Not a Grundschutz backup (format must be '" ~ backupFormat ~ "')");
    if (doc["formatVersion"].opt!long(0) > backupFormatVersion)
      throw new ValidationException("Backup format version " ~ doc["formatVersion"].toString ~ " is newer than supported");
    if (doc["schemaVersion"].opt!long(0) > schemaVersion)
      throw new ValidationException("Backup schema version " ~ doc["schemaVersion"].toString ~ " is newer than supported");
    r.createdAt = doc["createdAt"].opt!string;
    r.applicationVersion = doc["application"]["version"].opt!string;

    auto data = doc["data"];
    if (data.type != Json.Type.object) throw new ValidationException("Backup contains no data section");
    if (doc["checksum"].opt!string != checksum(data))
      throw new ValidationException("Checksum mismatch – the backup is corrupt or was modified");

    StorageSnapshot snap;
    foreach (string collection, docs; data) {
      if (![Collections.projects, Collections.targetObjects, Collections.requirements, Collections.risks]
          .map!(c => cast(string) c).canFind(collection))
        throw new ValidationException("Unknown collection '" ~ collection ~ "' in backup");
      if (docs.type != Json.Type.object) throw new ValidationException("Collection '" ~ collection ~ "' is malformed");
      Json[string] c;
      foreach (string id, d; docs) c[id] = d;
      snap[collection] = c;
    }

    // decode every record into domain entities on a scratch store and check references
    auto scratch = new DMemoryDocumentStorage;
    scratch.replaceAll(snap);
    auto projects = decodeAll(new DProjectRepository(scratch), "project", r);
    auto objects = decodeAll(new DTargetObjectRepository(scratch), "target object", r);
    auto requirements = decodeAll(new DRequirementRepository(scratch), "requirement", r);
    auto risks = decodeAll(new DRiskRepository(scratch), "risk", r);
    bool[string] projectIds, objectProject;
    string[string] objectToProject;
    foreach (p; projects) projectIds[p.id] = true;
    foreach (o; objects) {
      objectToProject[o.id] = o.projectId;
      if (o.projectId !in projectIds) r.issues ~= "Target object " ~ o.id ~ " references missing project " ~ o.projectId;
    }
    void checkChild(string kind, string id, string objectId, string projectId) {
      auto owner = objectId in objectToProject;
      if (owner is null) r.issues ~= kind ~ " " ~ id ~ " references missing target object " ~ objectId;
      else if (*owner != projectId) r.issues ~= kind ~ " " ~ id ~ " has inconsistent project " ~ projectId;
    }
    foreach (q; requirements) checkChild("Requirement", q.id, q.targetObjectId, q.projectId);
    foreach (k; risks) checkChild("Risk", k.id, k.targetObjectId, k.projectId);
    r.projects = cast(int) projects.length;
    r.targetObjects = cast(int) objects.length;
    r.requirements = cast(int) requirements.length;
    r.risks = cast(int) risks.length;
    return snap;
  }

  private static auto decodeAll(R)(R repo, string kind, ref RestoreReport r) @trusted {
    try return repo.findAll;
    catch (Exception e) {
      r.issues ~= "Invalid " ~ kind ~ " record: " ~ e.msg;
      return typeof(repo.findAll()).init;
    }
  }

  private void applyRetention() {
    if (_retention <= 0) return;
    auto all = listBackups();
    foreach (b; all.length > _retention ? all[_retention .. $] : null)
      remove(buildPath(_dir, b.name));
  }

  private static bool isBackupName(string name) {
    return !matchFirst(name, ctRegex!(`^grundschutz-backup-[0-9TZ]+(-[A-Za-z0-9_-]+)?\.json$`)).empty;
  }

  private static string sanitize(string label) {
    auto r = appender!string;
    foreach (c; label) r ~= ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_') ? c : '_';
    return r.data.length > 32 ? r.data[0 .. 32] : r.data;
  }
}

/// SHA-256 over a canonical serialisation (sorted keys) of a JSON value.
string checksum(Json value) @trusted {
  auto text = canonicalJson(value);
  return "sha256:" ~ toHexString!(LetterCase.lower)(sha256Of(text)).idup;
}

/// Deterministic JSON text: object keys sorted, no whitespace.
string canonicalJson(Json value) @trusted {
  auto w = appender!string;
  void emit(Json v) {
    switch (v.type) {
      case Json.Type.object:
        string[] keys;
        foreach (string k, _; v) keys ~= k;
        keys.sort();
        w ~= "{";
        foreach (i, k; keys) {
          if (i) w ~= ",";
          w ~= Json(k).toString;
          w ~= ":";
          emit(v[k]);
        }
        w ~= "}";
        break;
      case Json.Type.array:
        w ~= "[";
        foreach (size_t i, Json e; v) {
          if (i) w ~= ",";
          emit(e);
        }
        w ~= "]";
        break;
      default:
        w ~= v.toString;
    }
  }
  emit(value);
  return w.data;
}

unittest {
  auto a = parseJsonString(`{"b":1,"a":{"y":[1,2],"x":"s"}}`);
  auto b = parseJsonString(`{"a":{"x":"s","y":[1,2]},"b":1}`);
  assert(canonicalJson(a) == `{"a":{"x":"s","y":[1,2]},"b":1}`);
  assert(checksum(a) == checksum(b));
}
