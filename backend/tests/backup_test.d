/// Backup & restore of the complete data set.
module backup_test;

version (GrundschutzUnittest):

import std.algorithm : canFind;
import std.file : dirEntries, exists, mkdirRecurse, rmdirRecurse, tempDir, SpanMode;
import std.path : buildPath;
import std.string : replace;
import std.uuid : randomUUID;
import uim.myfiori.application.dtos;
import uim.myfiori.bootstrap;
import uim.myfiori.infrastructure.configuration;
import uim.myfiori.persistence.storages;

unittest {
  auto dir = buildPath(tempDir, "gs-backup-" ~ randomUUID.toString);
  scope (exit) if (dir.exists) rmdirRecurse(dir);
  AppConfig cfg;
  cfg.storage = "memory";
  cfg.backupDir = dir;
  cfg.backupRetention = 3;
  auto app = new DApplicationContainer(cfg, new DMemoryDocumentStorage);

  auto p = app.projects.create(CreateProjectInput("Original")).ID;
  auto o = app.targetObjects.create(CreateTargetObjectInput(p, "Server", "itSystem")).ID;
  app.requirements.applyModule(o, "SYS.1.1");
  auto backup = app.backups.createBackup;

  // change everything, then restore
  app.projects.remove(p);
  app.projects.create(CreateProjectInput("Neu"));
  auto dry = app.backups.restore(backup, true);
  assert(dry.valid && !dry.restored && dry.projects == 1 && dry.requirements > 0);
  assert(app.projects.list[0].name == "Neu");

  auto r = app.backups.restore(backup);
  assert(r.valid && r.restored && r.safetyBackup.canFind("pre-restore"), r.issues.length ? r.issues[0] : "");
  assert(app.projects.list.length == 1 && app.projects.get(p).name == "Original");
  assert(app.requirements.list(p).length == r.requirements);

  // the safety backup brings back the intermediate state
  auto back = app.backups.restoreFromFile(r.safetyBackup);
  assert(back.restored && app.projects.list[0].name == "Neu");

  // tampering is detected
  auto tampered = app.backups.restore(backup.replace("Original", "Gefälscht"));
  assert(!tampered.valid && !tampered.restored && tampered.issues[0].canFind("Checksum"));
  assert(!app.backups.restore("{}").valid);
  assert(!app.backups.restore("not json").valid);

  // retention keeps the newest n files; names are validated (no path traversal)
  foreach (i; 0 .. 5) app.backups.backupToFile("t");
  assert(app.backups.listBackups.length == 3);
  import std.exception : assertThrown;
  assertThrown!Exception(app.backups.readBackup("../../etc/passwd"));
}

unittest { // broken references are rejected before anything is changed
  auto app = DApplicationContainer.inMemory;
  auto p = app.projects.create(CreateProjectInput("P")).ID;
  app.targetObjects.create(CreateTargetObjectInput(p, "O", "room"));
  auto text = app.backups.createBackup;
  // remove the project from the data but keep a correct checksum
  import vibe.data.json;
  import uim.myfiori.persistence.storages.backup : checksum;
  auto doc = parseJsonString(text);
  doc["data"]["projects"] = Json.emptyObject;
  doc["checksum"] = checksum(doc["data"]);
  auto r = app.backups.restore(doc.toString);
  assert(!r.valid && r.issues[0].canFind("missing project"));
  assert(app.projects.list.length == 1);
}
