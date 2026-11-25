/// Repository implementations of the driven ports on top of an IDocumentStorage.
module uim.myfiori.persistence.repositories;

@safe:

import std.algorithm : filter, sort;
import std.array : array;
import vibe.data.json : Json;
import vibe.data.json : deserialize = deserializeJson;
import vibe.data.json : serializeToJson;
import uim.myfiori.domain;
import uim.myfiori.persistence.mappers;
import uim.myfiori.persistence.records;
import uim.myfiori.ports.repositories;
import uim.myfiori.ports.storages;

/// Generic document repository: Entity <-> Record <-> Json.
abstract class DDocumentRepository(E, R, string collection) : IRepository!E {
  protected IDocumentStorage _storage;

  this(IDocumentStorage storage) { _storage = storage; }

  E[] findAll() {
    E[] result;
    foreach (doc; _storage.all(collection)) result ~= decode(doc);
    // deterministic, human friendly order: oldest first
    result.sort!((a, b) => less(a, b));
    return result;
  }

  /// Sort order of findAll; overridden where a business order exists.
  protected bool less(E a, E b) {
    return a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id < b.id;
  }

  E findById(EntityId id) {
    auto doc = _storage.get(collection, id);
    return doc.type == Json.Type.undefined ? null : decode(doc);
  }

  void save(E entity) {
    _storage.put(collection, entity.id, encode(entity));
  }

  bool remove(EntityId id) { return _storage.remove(collection, id); }

  protected E[] where(bool delegate(E) @safe predicate) {
    return findAll.filter!(e => predicate(e)).array;
  }

  private static E decode(Json doc) @trusted { return toEntity(deserialize!R(doc)); }
  private static Json encode(E entity) @trusted { return serializeToJson(toRecord(entity)); }
}

class DProjectRepository : DDocumentRepository!(DProject, ProjectRecord, Collections.projects), IProjectRepository {
  this(IDocumentStorage storage) { super(storage); }
}

class DTargetObjectRepository
    : DDocumentRepository!(DTargetObject, TargetObjectRecord, Collections.targetObjects), ITargetObjectRepository {
  this(IDocumentStorage storage) { super(storage); }
  DTargetObject[] findByProject(EntityId projectId) { return where(e => e.projectId == projectId); }
}

class DRequirementRepository
    : DDocumentRepository!(DRequirement, RequirementRecord, Collections.requirements), IRequirementRepository {
  this(IDocumentStorage storage) { super(storage); }
  DRequirement[] findByProject(EntityId projectId) { return where(e => e.projectId == projectId); }
  DRequirement[] findByTargetObject(EntityId id) { return where(e => e.targetObjectId == id); }

  /// Kompendium order: by target object, then module, then requirement number (A2 < A10).
  protected override bool less(DRequirement a, DRequirement b) {
    if (a.targetObjectId != b.targetObjectId) return super.less(a, b);
    if (a.moduleCode != b.moduleCode) return a.moduleCode < b.moduleCode;
    auto na = requirementNumber(a.code.value), nb = requirementNumber(b.code.value);
    return na != nb ? na < nb : a.id < b.id;
  }

  private static int requirementNumber(string code) {
    import std.conv : to;
    import std.string : lastIndexOf;
    return code[code.lastIndexOf(".A") + 2 .. $].to!int;
  }
}

class DRiskRepository : DDocumentRepository!(DRisk, RiskRecord, Collections.risks), IRiskRepository {
  this(IDocumentStorage storage) { super(storage); }
  DRisk[] findByProject(EntityId projectId) { return where(e => e.projectId == projectId); }
  DRisk[] findByTargetObject(EntityId id) { return where(e => e.targetObjectId == id); }
}

class DUserRepository : DDocumentRepository!(DUser, UserRecord, Collections.users), IUserRepository {
  this(IDocumentStorage storage) { super(storage); }

  DUser findByUserName(string userName) {
    foreach (u; findAll) if (u.userName == userName) return u;
    return null;
  }

  protected override bool less(DUser a, DUser b) { return a.userName < b.userName; }
}
