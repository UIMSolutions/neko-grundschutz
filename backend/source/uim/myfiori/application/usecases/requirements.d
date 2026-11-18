/// Use cases for requirements (Modellierung & IT-Grundschutz-Check).
module uim.myfiori.application.usecases.requirements;

@safe:

import std.algorithm : canFind, map;
import std.array : array;
import std.datetime.systime : Clock;
import std.uuid : randomUUID;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

class DRequirementUseCases : IRequirementUseCases {
  private IProjectRepository _projects;
  private ITargetObjectRepository _objects;
  private IRequirementRepository _requirements;
  private ICatalogService _catalog;
  private IDomainEventPublisher _events;

  this(IProjectRepository projects, ITargetObjectRepository objects, IRequirementRepository requirements,
      ICatalogService catalog, IDomainEventPublisher events) {
    _projects = projects;
    _objects = objects;
    _requirements = requirements;
    _catalog = catalog;
    _events = events;
  }

  RequirementDto[] list(string projectId = "", string targetObjectId = "") {
    if (targetObjectId.length) return toDtos(_requirements.findByTargetObject(targetObjectId));
    if (projectId.length) return toDtos(_requirements.findByProject(projectId));
    return toDtos(_requirements.findAll);
  }

  RequirementDto get(string id) { return toDto(load(id)); }

  RequirementDto create(CreateRequirementInput input) {
    auto o = writableTarget(input.targetObjectId);
    auto code = RequirementCode(input.code);
    if (_requirements.findByTargetObject(o.id).canFind!(r => r.code == code))
      throw new ConflictException("Requirement " ~ code.value ~ " already exists for '" ~ o.name ~ "'");
    auto now = Clock.currTime.toUTC;
    auto r = new DRequirement(newId(input.ID, (id) => _requirements.findById(id) !is null), o.projectId, o.id, code, input.title,
        parseEnum!RequirementLevel(input.level), ImplementationStatus.open, input.responsible, "",
        input.dueDate, now, now);
    r.recordStatus(parseEnum!ImplementationStatus(input.status), input.note);
    _requirements.save(r);
    _events.raise("RequirementCreated", r.id, r.projectId, code.value);
    return toDto(r);
  }

  RequirementDto update(string id, UpdateRequirementInput input) {
    auto r = load(id);
    writableTarget(r.targetObjectId);
    if (!input.title.isNull) r.retitle(input.title.get);
    if (!input.responsible.isNull) r.assign(input.responsible.get);
    if (!input.dueDate.isNull) r.plan(input.dueDate.get);
    if (!input.status.isNull || !input.note.isNull)
      r.recordStatus(input.status.isNull ? r.status : parseEnum!ImplementationStatus(input.status.get),
          input.note.isNull ? r.note : input.note.get);
    _requirements.save(r);
    _events.raise("RequirementUpdated", r.id, r.projectId, r.status.label);
    return toDto(r);
  }

  void remove(string id) {
    auto r = load(id);
    writableTarget(r.targetObjectId);
    _requirements.remove(id);
    _events.raise("RequirementDeleted", id, r.projectId, r.code.value);
  }

  RequirementDto[] applyModule(string targetObjectId, string moduleCode) {
    auto o = writableTarget(targetObjectId);
    auto module_ = ModuleCode(moduleCode);
    auto existing = _requirements.findByTargetObject(o.id).map!(r => r.code.value).array;
    RequirementDto[] created;
    auto now = Clock.currTime.toUTC;
    foreach (c; _catalog.requirementsOf(module_.value)) {
      if (existing.canFind(c.code)) continue;
      auto r = new DRequirement(randomUUID.toString, o.projectId, o.id, RequirementCode(c.code), c.title,
          parseEnum!RequirementLevel(c.level), ImplementationStatus.open, "", "", "", now, now);
      _requirements.save(r);
      created ~= toDto(r);
    }
    _events.raise("ModuleApplied", o.id, o.projectId, module_.value);
    return created;
  }

  private DRequirement load(string id) {
    auto r = _requirements.findById(id);
    if (r is null) throw new EntityNotFoundException("Requirement", id);
    return r;
  }

  private DTargetObject writableTarget(string targetObjectId) {
    auto o = _objects.findById(targetObjectId);
    if (o is null) throw new EntityNotFoundException("TargetObject", targetObjectId);
    auto p = _projects.findById(o.projectId);
    if (p !is null) p.ensureWritable;
    return o;
  }
}
