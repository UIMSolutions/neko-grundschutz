/**
 * OData v4 endpoint for SAP Fiori / UI5 (sap.ui.model.odata.v4.ODataModel).
 *
 * Supported: service document, $metadata, entity sets with $filter/$orderby/$top/$skip/
 * $count/$select, single entities by key, navigation collections (create via navigation),
 * POST/PATCH/PUT/DELETE, function import GetProjectReport and action import ApplyModule.
 * $batch is not supported — the UI5 model is configured with groupId "$direct".
 */
module uim.myfiori.presentation.odata.service;

@safe:

import std.algorithm : canFind, map;
import std.array : array;
import std.conv : to;
import std.string : indexOf, split, startsWith;
import vibe.core.log;
import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.inet.url : URL;
import vibe.textfilter.urlencode : urlDecode;

import uim.myfiori.application.dtos;
import uim.myfiori.domain.exceptions : EntityNotFoundException;
import uim.myfiori.bootstrap;
import uim.myfiori.presentation.http.auth;
import uim.myfiori.infrastructure.security : requiredScope;
import uim.myfiori.presentation.http.errors;
import uim.myfiori.presentation.odata.metadata;
import uim.myfiori.presentation.odata.model;
import uim.myfiori.presentation.odata.query;

/// One parsed path segment: name plus optional key / parameter list.
struct Segment {
  string name;
  bool hasKey;
  string key;                 // single key value
  string[string] params;      // named parameters (functions, named keys)
}

/// Parses "Name", "Name('k')", "Name(ID='k')" and "Name(a='x',b=1)".
Segment parseSegment(string raw) {
  Segment s;
  auto open = raw.indexOf('(');
  if (open < 0 || raw[$ - 1] != ')') { s.name = raw; return s; }
  s.name = raw[0 .. open];
  s.hasKey = true;
  auto inner = raw[open + 1 .. $ - 1];
  // split on commas outside of quotes
  string[] parts;
  string cur;
  bool quoted;
  foreach (c; inner) {
    if (c == '\'') quoted = !quoted;
    if (c == ',' && !quoted) { parts ~= cur; cur = null; } else cur ~= c;
  }
  if (cur.length) parts ~= cur;
  foreach (p; parts) {
    auto eq = p.indexOf('=');
    if (eq > 0 && (p[0] != '\'')) s.params[p[0 .. eq]] = literal(p[eq + 1 .. $]);
    else s.key = literal(p);
  }
  if (s.key.length == 0 && s.params.length == 1) s.key = s.params.byValue.front;
  return s;
}

private string literal(string v) {
  import std.array : replace;
  if (v.length >= 2 && v[0] == '\'' && v[$ - 1] == '\'') return v[1 .. $ - 1].replace("''", "'");
  return v;
}

class DODataService {
  private DApplicationContainer _app;
  private string _base;
  private string _csrfToken;

  this(DApplicationContainer app, string base = "/odata/v4/grundschutz") {
    import std.uuid : randomUUID;
    _app = app;
    _base = base;
    _csrfToken = randomUUID.toString;
  }

  string basePath() const { return _base; }

  void register(URLRouter router) {
    router.any(_base, &handle);
    router.any(_base ~ "/*", &handle);
  }

  void handle(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    res.headers["OData-Version"] = "4.0";
    res.headers["Cache-Control"] = "no-store";
    // CSRF protection is enforced by the approuter; the token is handed out for UI5 compatibility.
    if (req.headers.get("X-CSRF-Token", "").length && req.headers["X-CSRF-Token"] == "Fetch")
      res.headers["X-CSRF-Token"] = _csrfToken;
    try {
      auto scope_ = requiredScope(req.method.to!string);
      authorize(_app, req, scope_, res);
      ensureNotCrossSite(_app.authGuard, req);
      dispatch(req, res);
    } catch (Exception e) {
      auto info = classify(e);
      if (info.status == HTTPStatus.internalServerError) logException(e, "OData request failed");
      writeError(res, info.status, info.code, info.status == HTTPStatus.internalServerError ? "Internal server error" : e.msg);
    }
  }

  private void dispatch(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto path = req.requestPath.toString;
    auto rel = path.length > _base.length ? path[_base.length .. $] : "";
    if (rel.startsWith("/")) rel = rel[1 .. $];
    rel = urlDecode(rel);

    if (rel.length == 0) {
      if (req.method == HTTPMethod.HEAD) { res.writeVoidBody; return; }
      return writeJsonText(res, HTTPStatus.ok, buildServiceDocument(_base ~ "/$metadata"));
    }
    if (rel == "$metadata") {
      res.writeBody(buildMetadata, "application/xml");
      return;
    }
    if (rel == "$batch") throw new BadRequestException("$batch is not supported; use groupId $direct");

    auto segs = rel.split("/").map!(s => parseSegment(s)).array;
    auto q = parseQueryOptions((string k) @safe => req.query.get(k, null));

    if (segs[0].name == "GetProjectReport") {
      ensureMethod(req, HTTPMethod.GET);
      auto projectId = segs[0].params.get("projectId", segs[0].key);
      if (projectId.startsWith("@")) projectId = literal(req.query.get(projectId, ""));
      auto j = reportToJson(_app.reports.projectReport(projectId));
      j["@odata.context"] = _base ~ "/$metadata#" ~ odataNamespace ~ ".ProjectReport";
      return writeJson(res, HTTPStatus.ok, j);
    }
    if (segs[0].name == "ApplyModule") {
      ensureMethod(req, HTTPMethod.POST);
      auto b = body_(req);
      auto created = _app.requirements.applyModule(b["targetObjectId"].opt!string, b["moduleCode"].opt!string);
      return writeCollection(res, "Requirements", created.map!(d => toODataJson(d)).array, QueryOptions.init);
    }

    auto set = findEntitySet(segs[0].name);
    if (set.name.length == 0) throw new BadRequestException("Unknown resource '" ~ segs[0].name ~ "'");

    if (segs.length == 1 && !segs[0].hasKey) return collection(req, res, set, q);
    if (segs.length == 2 && !segs[0].hasKey && segs[1].name == "$count") {
      ensureMethod(req, HTTPMethod.GET);
      q.top = -1; q.skip = 0;
      res.writeBody(applyQuery(list(set.entitySet), q, set.key).count.to!string, "text/plain");
      return;
    }
    if (segs.length == 1) return entity(req, res, set, segs[0].key);
    if (segs.length >= 2 && segs[0].hasKey) return navigation(req, res, set, segs[0].key, segs[1].name,
        segs.length == 3 && segs[2].name == "$count", q);
    throw new BadRequestException("Unsupported resource path '" ~ rel ~ "'");
  }

  // -------------------------------------------------------------- collections

  private void collection(HTTPServerRequest req, HTTPServerResponse res, EntityTypeDef set, QueryOptions q) @trusted {
    if (req.method == HTTPMethod.GET || req.method == HTTPMethod.HEAD)
      return writeCollection(res, set.entitySet, list(set.entitySet), q);
    ensureMethod(req, HTTPMethod.POST);
    if (set.readOnly) throw new ForbiddenException(set.entitySet ~ " is read-only");
    auto created = create(set.entitySet, body_(req));
    res.headers["Location"] = _base ~ "/" ~ set.entitySet ~ "('" ~ created[set.key].get!string ~ "')";
    writeEntity(res, HTTPStatus.created, set.entitySet, created);
  }

  private void navigation(HTTPServerRequest req, HTTPServerResponse res, EntityTypeDef set, string key,
      string nav, bool countOnly, QueryOptions q) @trusted {
    auto navDefs = set.navigations.map!(n => n.name).array;
    if (!navDefs.canFind(nav)) throw new BadRequestException("Unknown navigation property '" ~ nav ~ "'");
    auto target = set.navigations[navDefs.countUntil(nav)].targetSet;

    Json[] items;
    if (set.entitySet == "Projects") {
      _app.projects.get(key); // 404 if missing
      final switch (nav) {
        case "targetObjects": items = _app.targetObjects.list(key).map!(d => toODataJson(d)).array; break;
        case "requirements": items = _app.requirements.list(key).map!(d => toODataJson(d)).array; break;
        case "risks": items = _app.risks.list(key).map!(d => toODataJson(d)).array; break;
      }
    } else {
      _app.targetObjects.get(key);
      final switch (nav) {
        case "requirements": items = _app.requirements.list("", key).map!(d => toODataJson(d)).array; break;
        case "risks": items = _app.risks.list("", key).map!(d => toODataJson(d)).array; break;
      }
    }

    if (req.method == HTTPMethod.POST) {
      auto b = body_(req);
      Json created;
      // Projects('p')/requirements|risks: the target object comes from the body and must belong to p
      auto objectId = set.entitySet == "TargetObjects" ? key : b["targetObjectId"].opt!string;
      if (set.entitySet == "Projects" && target != "TargetObjects" && _app.targetObjects.get(objectId).projectId != key)
        throw new BadRequestException("Target object '" ~ objectId ~ "' does not belong to project '" ~ key ~ "'");
      if (target == "TargetObjects") created = toODataJson(_app.targetObjects.create(createTargetObjectInput(b, key)));
      else if (target == "Requirements") created = toODataJson(_app.requirements.create(createRequirementInput(b, objectId)));
      else created = toODataJson(_app.risks.create(createRiskInput(b, objectId)));
      res.headers["Location"] = _base ~ "/" ~ target ~ "('" ~ created["ID"].get!string ~ "')";
      return writeEntity(res, HTTPStatus.created, target, created);
    }
    ensureMethod(req, HTTPMethod.GET);
    if (countOnly) {
      q.top = -1; q.skip = 0;
      res.writeBody(applyQuery(items, q, "ID").count.to!string, "text/plain");
      return;
    }
    writeCollection(res, target, items, q);
  }

  // -------------------------------------------------------------- single entities

  private void entity(HTTPServerRequest req, HTTPServerResponse res, EntityTypeDef set, string key) @trusted {
    switch (req.method) {
      case HTTPMethod.GET:
        return writeEntity(res, HTTPStatus.ok, set.entitySet, read(set.entitySet, key));
      case HTTPMethod.PATCH:
      case HTTPMethod.PUT:
        if (set.readOnly) throw new ForbiddenException(set.entitySet ~ " is read-only");
        return writeEntity(res, HTTPStatus.ok, set.entitySet, update(set.entitySet, key, body_(req)));
      case HTTPMethod.DELETE:
        if (set.readOnly) throw new ForbiddenException(set.entitySet ~ " is read-only");
        if (set.entitySet == "Projects") authorize(_app, req, "Admin");
        remove(set.entitySet, key);
        res.statusCode = HTTPStatus.noContent;
        res.writeVoidBody;
        return;
      default:
        throw new BadRequestException("Method " ~ req.method.to!string ~ " not allowed");
    }
  }

  // -------------------------------------------------------------- use case bridge

  private Json[] list(string set) {
    switch (set) {
      case "Projects": return _app.projects.list.map!(d => toODataJson(d)).array;
      case "TargetObjects": return _app.targetObjects.list.map!(d => toODataJson(d)).array;
      case "Requirements": return _app.requirements.list.map!(d => toODataJson(d)).array;
      case "Risks": return _app.risks.list.map!(d => toODataJson(d)).array;
      case "Modules": return _app.catalog.modules.map!(d => toODataJson(d)).array;
      case "Threats": return _app.catalog.threats.map!(d => toODataJson(d)).array;
      default: assert(false, set);
    }
  }

  private Json read(string set, string key) {
    switch (set) {
      case "Projects": return toODataJson(_app.projects.get(key));
      case "TargetObjects": return toODataJson(_app.targetObjects.get(key));
      case "Requirements": return toODataJson(_app.requirements.get(key));
      case "Risks": return toODataJson(_app.risks.get(key));
      case "Modules": return toODataJson(_app.catalog.findModule(key));
      case "Threats":
        foreach (t; _app.catalog.threats) if (t.code == key) return toODataJson(t);
        throw new EntityNotFoundException("Threat", key);
      default: assert(false, set);
    }
  }

  private Json create(string set, Json b) {
    switch (set) {
      case "Projects": return toODataJson(_app.projects.create(createProjectInput(b)));
      case "TargetObjects": return toODataJson(_app.targetObjects.create(createTargetObjectInput(b)));
      case "Requirements": return toODataJson(_app.requirements.create(createRequirementInput(b)));
      case "Risks": return toODataJson(_app.risks.create(createRiskInput(b)));
      default: assert(false, set);
    }
  }

  private Json update(string set, string key, Json b) {
    switch (set) {
      case "Projects": return toODataJson(_app.projects.update(key, updateProjectInput(b)));
      case "TargetObjects": return toODataJson(_app.targetObjects.update(key, updateTargetObjectInput(b)));
      case "Requirements": return toODataJson(_app.requirements.update(key, updateRequirementInput(b)));
      case "Risks": return toODataJson(_app.risks.update(key, updateRiskInput(b)));
      default: assert(false, set);
    }
  }

  private void remove(string set, string key) {
    switch (set) {
      case "Projects": return _app.projects.remove(key);
      case "TargetObjects": return _app.targetObjects.remove(key);
      case "Requirements": return _app.requirements.remove(key);
      case "Risks": return _app.risks.remove(key);
      default: assert(false, set);
    }
  }

  // -------------------------------------------------------------- response helpers

  private void writeCollection(HTTPServerResponse res, string set, Json[] items, QueryOptions q) {
    auto key = findEntitySet(set).key;
    auto r = applyQuery(items, q, key.length ? key : "ID");
    auto doc = Json.emptyObject;
    doc["@odata.context"] = _base ~ "/$metadata#" ~ set;
    if (q.count) doc["@odata.count"] = r.count;
    doc["value"] = Json(r.items);
    writeJson(res, HTTPStatus.ok, doc);
  }

  private void writeEntity(HTTPServerResponse res, HTTPStatus status, string set, Json entity) {
    entity["@odata.context"] = _base ~ "/$metadata#" ~ set ~ "/$entity";
    writeJson(res, status, entity);
  }

  private static Json body_(HTTPServerRequest req) @trusted {
    import vibe.stream.operations : readAllUTF8;
    auto text = req.bodyReader.readAllUTF8;
    if (text.length == 0) return Json.emptyObject;
    try {
      auto j = parseJsonString(text);
      if (j.type != Json.Type.object) throw new BadRequestException("Request body must be a JSON object");
      return j;
    } catch (JSONException e) throw new BadRequestException("Malformed JSON: " ~ e.msg);
  }

  private static void ensureMethod(HTTPServerRequest req, HTTPMethod m) {
    if (req.method != m && !(m == HTTPMethod.GET && req.method == HTTPMethod.HEAD))
      throw new BadRequestException("Method " ~ req.method.to!string ~ " not allowed here");
  }

  private static void writeJson(HTTPServerResponse res, HTTPStatus status, Json j) @trusted {
    writeJsonText(res, status, j.toString);
  }

  private static void writeJsonText(HTTPServerResponse res, HTTPStatus status, string text) @trusted {
    res.statusCode = status;
    res.writeBody(text, "application/json;odata.metadata=minimal;charset=utf-8");
  }

  private static void writeError(HTTPServerResponse res, HTTPStatus status, string code, string message) @trusted {
    auto e = Json.emptyObject;
    e["code"] = code;
    e["message"] = message;
    auto doc = Json.emptyObject;
    doc["error"] = e;
    writeJsonText(res, status, doc.toString);
  }
}

private size_t countUntil(string[] a, string v) {
  foreach (i, x; a) if (x == v) return i;
  return size_t.max;
}

unittest {
  auto s = parseSegment("Projects('a''b')");
  assert(s.name == "Projects" && s.hasKey && s.key == "a'b");
  s = parseSegment("GetProjectReport(projectId='x1')");
  assert(s.params["projectId"] == "x1" && s.key == "x1");
  s = parseSegment("Threats('G 0.18')");
  assert(s.key == "G 0.18");
}
