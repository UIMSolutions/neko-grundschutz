/// Entity data model (EDM) of the OData v4 service and DTO <-> JSON conversion.
module uim.myfiori.presentation.odata.model;

@safe:

import std.typecons : Nullable;
import vibe.data.json;
import uim.myfiori.application.dtos;
import uim.myfiori.presentation.http.errors : BadRequestException;

enum odataNamespace = "grundschutz";

struct PropertyDef {
  string name;
  string type = "Edm.String";
  bool nullable = true;
  bool computed;
  int maxLength;
  bool collection;
}

struct NavigationDef {
  string name;
  string targetType;
  string targetSet;
}

struct EntityTypeDef {
  string name;
  string entitySet;
  string key = "ID";
  PropertyDef[] properties;
  NavigationDef[] navigations;
  bool readOnly;
}

private PropertyDef key(string n = "ID") { return PropertyDef(n, "Edm.String", false, true); }
private PropertyDef str(string n, int len = 255) { return PropertyDef(n, "Edm.String", true, false, len); }
private PropertyDef req(string n, int len = 255) { return PropertyDef(n, "Edm.String", false, false, len); }
private PropertyDef computed(string n, string type = "Edm.String") { return PropertyDef(n, type, true, true); }
private PropertyDef stamp(string n) { return computed(n, "Edm.DateTimeOffset"); }

EntityTypeDef[] entityTypes() {
  return [
    EntityTypeDef("Project", "Projects", "ID", [
      key, req("name"), str("description", 4000), str("scope", 4000), str("owner"),
      str("approach", 20), str("status", 20), stamp("createdAt"), stamp("modifiedAt"),
    ], [
      NavigationDef("targetObjects", "TargetObject", "TargetObjects"),
      NavigationDef("requirements", "Requirement", "Requirements"),
      NavigationDef("risks", "Risk", "Risks"),
    ]),
    EntityTypeDef("TargetObject", "TargetObjects", "ID", [
      key, req("projectId", 36), req("name"), str("kind", 30), str("description", 4000),
      str("confidentiality", 20), str("integrity", 20), str("availability", 20),
      computed("protectionLevel"), str("protectionRationale", 4000),
      computed("requiresRiskAnalysis", "Edm.Boolean"), stamp("createdAt"), stamp("modifiedAt"),
    ], [
      NavigationDef("requirements", "Requirement", "Requirements"),
      NavigationDef("risks", "Risk", "Risks"),
    ]),
    EntityTypeDef("Requirement", "Requirements", "ID", [
      key, computed("projectId"), req("targetObjectId", 36), req("code", 30), computed("moduleCode"),
      req("title", 500), str("level", 20), str("status", 20), str("responsible"), str("note", 4000),
      PropertyDef("dueDate", "Edm.Date"), stamp("createdAt"), stamp("modifiedAt"),
    ]),
    EntityTypeDef("Risk", "Risks", "ID", [
      key, computed("projectId"), req("targetObjectId", 36), req("threatCode", 10), req("title", 500),
      str("description", 4000), PropertyDef("frequency", "Edm.Int32", false), PropertyDef("impact", "Edm.Int32", false),
      computed("level"), str("treatment", 20), str("treatmentNote", 4000), stamp("createdAt"), stamp("modifiedAt"),
    ]),
    EntityTypeDef("Module", "Modules", "code", [
      key("code"), computed("title"), computed("layer"), computed("description"),
      computed("requirementCount", "Edm.Int32"),
    ], null, true),
    EntityTypeDef("Threat", "Threats", "code", [key("code"), computed("title")], null, true),
  ];
}

/// Complex type returned by the GetProjectReport function.
PropertyDef[] reportProperties() {
  PropertyDef[] p;
  foreach (n; ["projectId", "projectName", "approach", "status", "confidentiality", "integrity",
      "availability", "protectionLevel"]) p ~= PropertyDef(n);
  p ~= PropertyDef("objectsRequiringRiskAnalysis", "Edm.String", true, false, 0, true);
  foreach (n; ["targetObjectCount", "requirementsTotal", "requirementsFulfilled", "requirementsPartially",
      "requirementsNotFulfilled", "requirementsOpen", "requirementsDispensable", "basicRequirementsOpen",
      "risksTotal", "risksLow", "risksMedium", "risksHigh", "risksVeryHigh", "risksUntreated"])
    p ~= PropertyDef(n, "Edm.Int32", false);
  p ~= PropertyDef("basicProtectionAchieved", "Edm.Boolean", false);
  p ~= PropertyDef("complianceDegree", "Edm.Double", false);
  return p;
}

EntityTypeDef findEntitySet(string set) {
  foreach (t; entityTypes) if (t.entitySet == set) return t;
  return EntityTypeDef.init;
}

// ------------------------------------------------------------------ DTO -> JSON

/// Serialises a DTO; empty date values become null, "scope_" is exposed as "scope".
Json toODataJson(T)(T dto) @trusted {
  auto j = serializeToJson(dto);
  if (j["scope_"].type != Json.Type.undefined) {
    j["scope"] = j["scope_"];
    j.remove("scope_");
  }
  foreach (n; ["dueDate", "createdAt", "modifiedAt"])
    if (j[n].type == Json.Type.string && j[n].get!string.length == 0) j[n] = Json(null);
  return j;
}

Json reportToJson(ProjectReportDto r) @trusted {
  auto j = serializeToJson(r);
  j.remove("project");
  j["projectId"] = r.project.ID;
  j["projectName"] = r.project.name;
  j["approach"] = r.project.approach;
  j["status"] = r.project.status;
  return j;
}

// ------------------------------------------------------------------ JSON -> input

private string text(Json body_, string field, string fallback = "") {
  auto v = body_[field];
  if (v.type == Json.Type.undefined || v.type == Json.Type.null_) return fallback;
  if (v.type != Json.Type.string) throw new BadRequestException("Property '" ~ field ~ "' must be a string");
  return v.get!string;
}

private Nullable!string optText(Json body_, string field) {
  auto v = body_[field];
  if (v.type == Json.Type.undefined) return Nullable!string.init;
  if (v.type == Json.Type.null_) return Nullable!string("");
  if (v.type != Json.Type.string) throw new BadRequestException("Property '" ~ field ~ "' must be a string");
  return Nullable!string(v.get!string);
}

private int integer(Json body_, string field, int fallback) @trusted {
  auto v = body_[field];
  if (v.type == Json.Type.undefined || v.type == Json.Type.null_) return fallback;
  if (v.type != Json.Type.int_) throw new BadRequestException("Property '" ~ field ~ "' must be an integer");
  return cast(int) v.get!long;
}

private Nullable!int optInteger(Json body_, string field) @trusted {
  auto v = body_[field];
  if (v.type == Json.Type.undefined || v.type == Json.Type.null_) return Nullable!int.init;
  if (v.type != Json.Type.int_) throw new BadRequestException("Property '" ~ field ~ "' must be an integer");
  return Nullable!int(cast(int) v.get!long);
}

CreateProjectInput createProjectInput(Json b) {
  return CreateProjectInput(text(b, "name"), text(b, "description"), text(b, "scope"), text(b, "owner"),
      text(b, "approach", "standard"));
}

UpdateProjectInput updateProjectInput(Json b) {
  return UpdateProjectInput(optText(b, "name"), optText(b, "description"), optText(b, "scope"),
      optText(b, "owner"), optText(b, "approach"), optText(b, "status"));
}

CreateTargetObjectInput createTargetObjectInput(Json b, string projectId = "") {
  return CreateTargetObjectInput(projectId.length ? projectId : text(b, "projectId"), text(b, "name"),
      text(b, "kind", "itSystem"), text(b, "description"), text(b, "confidentiality", "normal"),
      text(b, "integrity", "normal"), text(b, "availability", "normal"), text(b, "protectionRationale"));
}

UpdateTargetObjectInput updateTargetObjectInput(Json b) {
  return UpdateTargetObjectInput(optText(b, "name"), optText(b, "kind"), optText(b, "description"),
      optText(b, "confidentiality"), optText(b, "integrity"), optText(b, "availability"),
      optText(b, "protectionRationale"));
}

CreateRequirementInput createRequirementInput(Json b, string targetObjectId = "") {
  return CreateRequirementInput(targetObjectId.length ? targetObjectId : text(b, "targetObjectId"),
      text(b, "code"), text(b, "title"), text(b, "level", "basic"), text(b, "status", "open"),
      text(b, "responsible"), text(b, "note"), text(b, "dueDate"));
}

UpdateRequirementInput updateRequirementInput(Json b) {
  return UpdateRequirementInput(optText(b, "title"), optText(b, "status"), optText(b, "responsible"),
      optText(b, "note"), optText(b, "dueDate"));
}

CreateRiskInput createRiskInput(Json b, string targetObjectId = "") {
  return CreateRiskInput(targetObjectId.length ? targetObjectId : text(b, "targetObjectId"),
      text(b, "threatCode"), text(b, "title"), text(b, "description"), integer(b, "frequency", 1),
      integer(b, "impact", 1), text(b, "treatment", "open"), text(b, "treatmentNote"));
}

UpdateRiskInput updateRiskInput(Json b) {
  return UpdateRiskInput(optText(b, "title"), optText(b, "description"), optInteger(b, "frequency"),
      optInteger(b, "impact"), optText(b, "treatment"), optText(b, "treatmentNote"));
}
