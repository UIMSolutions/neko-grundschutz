/// Import / export of entities and projects.
module exchange_test;

version (GrundschutzUnittest):

import std.algorithm : canFind;
import std.exception : assertThrown;
import std.string : replace;
import vibe.data.json;
import uim.myfiori.application.dtos;
import uim.myfiori.bootstrap;
import uim.myfiori.domain.exceptions;

private DApplicationContainer sample(out string projectId, out string objectId) {
  auto app = DApplicationContainer.inMemory;
  projectId = app.projects.create(CreateProjectInput("ISMS; \"Test\"", "Beschreibung\nmit Umbruch", "=Rathaus", "ISB")).ID;
  objectId = app.targetObjects.create(CreateTargetObjectInput(projectId, "Fileserver", "itSystem", "", "high",
      "normal", "normal", "Personaldaten")).ID;
  app.requirements.applyModule(objectId, "SYS.1.1");
  app.risks.create(CreateRiskInput(objectId, "G 0.39", "Ransomware", "", 4, 4, "accept", "Leitungsentscheidung"));
  return app;
}

unittest { // CSV and JSON round trip into an empty system keeps ids and references
  string p, o;
  auto src = sample(p, o);
  foreach (format; ["csv", "json"]) {
    auto dst = DApplicationContainer.inMemory;
    foreach (entity; ["projects", "targetObjects", "requirements", "risks"]) {
      auto r = dst.exchange.importEntities(entity, "auto", src.exchange.exportEntities(entity, format, "",
          format == "csv" ? ';' : ','));
      assert(r.committed && r.failed == 0 && r.created == r.total, entity ~ " " ~ format);
    }
    assert(dst.projects.get(p).name == "ISMS; \"Test\"");
    assert(dst.projects.get(p).scope_ == "=Rathaus");                 // formula prefix removed again
    assert(dst.projects.get(p).description == "Beschreibung\nmit Umbruch");
    assert(dst.targetObjects.get(o).confidentiality == "high");
    assert(dst.requirements.list(p).length == src.requirements.list(p).length);
    assert(dst.risks.list(p)[0].level == "veryHigh");
  }
}

unittest { // CSV export neutralises formulas
  string p, o;
  auto app = sample(p, o);
  assert(app.exchange.exportEntities("projects", "csv").canFind("'=Rathaus"));
}

unittest { // imports are all-or-nothing; dry run never writes
  auto app = DApplicationContainer.inMemory;
  auto csv = "name,approach\r\nA,basic\r\nB,nonsense\r\n";
  auto r = app.exchange.importEntities("projects", "csv", csv);
  assert(!r.committed && r.created == 1 && r.failed == 1 && r.issues[0].row == 3);
  assert(app.projects.list.length == 0);
  r = app.exchange.importEntities("projects", "csv", "name\r\nA\r\n", "create", true);
  assert(r.dryRun && !r.committed && r.created == 1 && app.projects.list.length == 0);
}

unittest { // modes create / skip / upsert
  string p, o;
  auto app = sample(p, o);
  auto json = app.exchange.exportEntities("targetObjects", "json").replace("Fileserver", "Fileserver 2");
  assert(app.exchange.importEntities("targetObjects", "json", json, "create").failed == 1);
  assert(app.exchange.importEntities("targetObjects", "json", json, "skip").skipped == 1);
  auto r = app.exchange.importEntities("targetObjects", "json", json, "upsert");
  assert(r.committed && r.updated == 1 && app.targetObjects.get(o).name == "Fileserver 2");
  assertThrown!ValidationException(app.exchange.importEntities("modules", "json", "[]"));
  assertThrown!ValidationException(app.exchange.importEntities("risks", "json", json));  // wrong entity in file
}

unittest { // project bundle: copy with new ids, archived status restored last
  string p, o;
  auto app = sample(p, o);
  UpdateProjectInput archive;
  archive.status = "archived";
  app.projects.update(p, archive);
  auto bundle = app.exchange.exportProject(p);

  auto again = app.exchange.importProject(bundle);           // same ids -> conflict
  assert(!again.committed && again.failed > 0);

  auto copy = app.exchange.importProject(bundle, true);
  assert(copy.committed && copy.failed == 0, copy.issues.length ? copy.issues[0].message : "");
  assert(app.projects.list.length == 2);
  foreach (q; app.projects.list) if (q.ID != p) {
    assert(q.status == "archived");
    assert(app.reports.projectReport(q.ID).requirementsTotal == app.reports.projectReport(p).requirementsTotal);
    assert(app.risks.list(q.ID).length == 1);
  }

  auto other = DApplicationContainer.inMemory;
  auto moved = other.exchange.importProject(bundle);          // same ids into another system
  assert(moved.committed && other.projects.get(p).status == "archived");
}

unittest { // dossier for printing
  string p, o;
  auto app = sample(p, o);
  auto d = app.reports.dossier(p);
  assert(d.targetObjects.length == 1 && d.requirements.length > 0 && d.risks.length == 1);
  import uim.myfiori.presentation.web.print : renderProjectHtml;
  import uim.myfiori.presentation.cli.print : renderProjectMarkdown;
  auto html = renderProjectHtml(d);
  assert(html.canFind("Sicherheitskonzept") && html.canFind("SYS.1.1.A2") && html.canFind("Ransomware"));
  assert(!html.canFind("<script"));                                       // no auto print by default
  assert(renderProjectHtml(d, true).canFind("window.print()"));
  assert(html.canFind("ISMS; &quot;Test&quot;") || html.canFind("ISMS; \"Test\""));
  auto md = renderProjectMarkdown(d);
  assert(md.canFind("# Sicherheitskonzept: ISMS; \"Test\"") && md.canFind("| SYS.1.1.A2 |"));
}
