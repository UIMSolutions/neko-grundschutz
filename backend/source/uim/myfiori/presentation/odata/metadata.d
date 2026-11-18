/// CSDL ($metadata) generation for the OData v4 service.
module uim.myfiori.presentation.odata.metadata;

@safe:

import std.array : appender;
import std.conv : to;
import uim.myfiori.presentation.odata.model;

private void writeProperty(A)(ref A w, PropertyDef p, bool annotateComputed = true) {
  auto type = p.collection ? "Collection(" ~ p.type ~ ")" : p.type;
  w ~= `<Property Name="` ~ p.name ~ `" Type="` ~ type ~ `"`;
  if (!p.nullable) w ~= ` Nullable="false"`;
  if (p.maxLength > 0) w ~= ` MaxLength="` ~ p.maxLength.to!string ~ `"`;
  if (p.type == "Edm.DateTimeOffset") w ~= ` Precision="0"`;
  if (p.computed && annotateComputed) w ~= `><Annotation Term="Core.Computed" Bool="true"/></Property>`;
  else w ~= `/>`;
}

/// Builds the complete CSDL XML document.
string buildMetadata() {
  enum ns = odataNamespace;
  auto w = appender!string;
  w ~= `<?xml version="1.0" encoding="utf-8"?>`;
  w ~= `<edmx:Edmx xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx" Version="4.0">`;
  w ~= `<edmx:Reference Uri="https://oasis-tcs.github.io/odata-vocabularies/vocabularies/Org.OData.Core.V1.xml">`;
  w ~= `<edmx:Include Namespace="Org.OData.Core.V1" Alias="Core"/></edmx:Reference>`;
  w ~= `<edmx:DataServices><Schema xmlns="http://docs.oasis-open.org/odata/ns/edm" Namespace="` ~ ns ~ `">`;

  foreach (t; entityTypes) {
    w ~= `<EntityType Name="` ~ t.name ~ `"><Key><PropertyRef Name="` ~ t.key ~ `"/></Key>`;
    foreach (p; t.properties) writeProperty(w, p);
    foreach (n; t.navigations)
      w ~= `<NavigationProperty Name="` ~ n.name ~ `" Type="Collection(` ~ ns ~ "." ~ n.targetType ~ `)"/>`;
    w ~= `</EntityType>`;
  }

  w ~= `<ComplexType Name="ProjectReport">`;
  foreach (p; reportProperties) writeProperty(w, p, false);
  w ~= `</ComplexType>`;

  w ~= `<Function Name="GetProjectReport"><Parameter Name="projectId" Type="Edm.String" Nullable="false"/>`;
  w ~= `<ReturnType Type="` ~ ns ~ `.ProjectReport" Nullable="false"/></Function>`;
  w ~= `<Action Name="ApplyModule"><Parameter Name="targetObjectId" Type="Edm.String" Nullable="false"/>`;
  w ~= `<Parameter Name="moduleCode" Type="Edm.String" Nullable="false"/>`;
  w ~= `<ReturnType Type="Collection(` ~ ns ~ `.Requirement)"/></Action>`;

  w ~= `<EntityContainer Name="EntityContainer">`;
  foreach (t; entityTypes) {
    w ~= `<EntitySet Name="` ~ t.entitySet ~ `" EntityType="` ~ ns ~ "." ~ t.name ~ `">`;
    foreach (n; t.navigations)
      w ~= `<NavigationPropertyBinding Path="` ~ n.name ~ `" Target="` ~ n.targetSet ~ `"/>`;
    w ~= `</EntitySet>`;
  }
  w ~= `<FunctionImport Name="GetProjectReport" Function="` ~ ns ~ `.GetProjectReport"/>`;
  w ~= `<ActionImport Name="ApplyModule" Action="` ~ ns ~ `.ApplyModule" EntitySet="Requirements"/>`;
  w ~= `</EntityContainer></Schema></edmx:DataServices></edmx:Edmx>`;
  return w.data;
}

/// Service document (JSON) listing all entity sets and the function import.
string buildServiceDocument(string metadataUrl) {
  import vibe.data.json : Json;
  auto values = Json.emptyArray;
  foreach (t; entityTypes) {
    auto e = Json.emptyObject;
    e["name"] = t.entitySet;
    e["kind"] = "EntitySet";
    e["url"] = t.entitySet;
    values ~= e;
  }
  auto f = Json.emptyObject;
  f["name"] = "GetProjectReport";
  f["kind"] = "FunctionImport";
  f["url"] = "GetProjectReport";
  values ~= f;
  auto doc = Json.emptyObject;
  doc["@odata.context"] = metadataUrl;
  doc["value"] = values;
  return doc.toString;
}

unittest {
  import std.algorithm : canFind;
  auto xml = buildMetadata;
  assert(xml.canFind(`<EntitySet Name="Projects" EntityType="grundschutz.Project">`));
  assert(xml.canFind(`<FunctionImport Name="GetProjectReport"`));
}
