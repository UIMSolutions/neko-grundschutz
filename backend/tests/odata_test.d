/// OData model/metadata consistency checks.
module odata_test;

version (GrundschutzUnittest):

import std.algorithm : canFind;
import uim.myfiori.application.dtos;
import uim.myfiori.presentation.odata;

unittest {
  // every DTO property is declared in the EDM and vice versa (except navigation properties)
  auto check(T)(string set) {
    auto def = findEntitySet(set);
    auto j = toODataJson(T.init);
    foreach (p; def.properties) assert(j[p.name].type != j[p.name].Type.undefined, set ~ "." ~ p.name);
    foreach (string k, v; j) assert(def.properties.canFind!(p => p.name == k), set ~ " missing " ~ k);
  }
  check!ProjectDto("Projects");
  check!TargetObjectDto("TargetObjects");
  check!RequirementDto("Requirements");
  check!RiskDto("Risks");
  check!ModuleDto("Modules");
  check!ThreatDto("Threats");

  auto report = reportToJson(ProjectReportDto.init);
  foreach (p; reportProperties) assert(report[p.name].type != report[p.name].Type.undefined, p.name);
}
