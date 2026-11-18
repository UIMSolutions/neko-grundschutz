/// Round trip through the JSON file storage.
module persistence_test;

version (GrundschutzUnittest):

import std.file : exists, remove, tempDir;
import std.path : buildPath;
import std.uuid : randomUUID;
import uim.myfiori.application.dtos;
import uim.myfiori.bootstrap;
import uim.myfiori.infrastructure.configuration;
import uim.myfiori.persistence.storages;

unittest {
  auto file = buildPath(tempDir, "gs-test-" ~ randomUUID.toString ~ ".json");
  scope (exit) if (file.exists) remove(file);
  AppConfig cfg;
  cfg.dataFile = file;

  string projectId, objectId;
  {
    auto app = new DApplicationContainer(cfg, new DJsonFileDocumentStorage(file));
    projectId = app.projects.create(CreateProjectInput("Persistenz")).ID;
    objectId = app.targetObjects.create(CreateTargetObjectInput(projectId, "Serverraum", "room")).ID;
    app.requirements.applyModule(objectId, "INF.2");
  }
  auto reloaded = new DApplicationContainer(cfg, new DJsonFileDocumentStorage(file));
  assert(reloaded.projects.get(projectId).name == "Persistenz");
  assert(reloaded.targetObjects.get(objectId).kind == "room");
  assert(reloaded.requirements.list(projectId).length > 0);
}
