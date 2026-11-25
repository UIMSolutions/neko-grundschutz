/// Use-case level tests against the in-memory container.
module usecases_test;

version (GrundschutzUnittest):

import std.algorithm : canFind;
import std.exception : assertThrown;
import uim.myfiori.application.dtos;
import uim.myfiori.bootstrap;
import uim.myfiori.domain.exceptions;

unittest {
  auto app = DApplicationContainer.inMemory;
  auto p = app.projects.create(CreateProjectInput("ISMS Rathaus", "", "Verwaltung", "ISB", "basic"));
  assert(p.status == "planned");

  // protection need above normal needs a rationale
  assertThrown!ValidationException(app.targetObjects.create(
      CreateTargetObjectInput(p.ID, "Fachverfahren", "application", "", "high")));
  auto o = app.targetObjects.create(CreateTargetObjectInput(p.ID, "Fachverfahren", "application", "",
      "high", "normal", "veryHigh", "Personenbezogene Daten"));
  assert(o.protectionLevel == "veryHigh" && o.requiresRiskAnalysis);

  // module application is idempotent
  auto created = app.requirements.applyModule(o.ID, "SYS.1.1");
  assert(created.length > 0);
  assert(app.requirements.applyModule(o.ID, "SYS.1.1").length == 0);
  assertThrown!EntityNotFoundException(app.requirements.applyModule(o.ID, "XYZ.9"));

  // basic approach: only basic requirements are relevant
  auto report = app.reports.projectReport(p.ID);
  assert(report.requirementsTotal > 0 && report.requirementsTotal < cast(int) created.length);
  assert(!report.basicProtectionAchieved);
  foreach (r; created) {
    if (r.level != "basic") continue;
    UpdateRequirementInput u;
    u.status = "yes";
    app.requirements.update(r.ID, u);
  }
  report = app.reports.projectReport(p.ID);
  assert(report.basicProtectionAchieved && report.complianceDegree == 100.0);
  assert(report.protectionLevel == "veryHigh" && report.objectsRequiringRiskAnalysis == ["Fachverfahren"]);

  // basic requirement may not be dispensable
  UpdateRequirementInput dispensable;
  dispensable.status = "dispensable";
  dispensable.note = "nicht relevant";
  assertThrown!ValidationException(app.requirements.update(created[0].ID, dispensable));

  // risk acceptance rules
  assertThrown!ValidationException(app.risks.create(CreateRiskInput(o.ID, "G 0.39", "Ransomware", "", 4, 4, "accept")));
  auto k = app.risks.create(CreateRiskInput(o.ID, "G 0.39", "Ransomware", "", 4, 4, "reduce", "Backups, EDR"));
  assert(k.level == "veryHigh");
  assert(app.reports.projectReport(p.ID).risksVeryHigh == 1);

  // archived projects are read-only
  UpdateProjectInput archive;
  archive.status = "archived";
  app.projects.update(p.ID, archive);
  assertThrown!ConflictException(app.targetObjects.create(CreateTargetObjectInput(p.ID, "Server", "itSystem")));

  // cascading delete
  app.projects.remove(p.ID);
  assert(app.targetObjects.list.length == 0 && app.requirements.list.length == 0 && app.risks.list.length == 0);
}
