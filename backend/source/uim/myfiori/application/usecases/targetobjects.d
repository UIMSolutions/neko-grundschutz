/// Use cases for target objects (Strukturanalyse & Schutzbedarfsfeststellung).
module uim.myfiori.application.usecases.targetobjects;

@safe:

import std.datetime.systime : Clock;
import std.uuid : randomUUID;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

class DTargetObjectUseCases : ITargetObjectUseCases {
  private IProjectRepository _projects;
  private ITargetObjectRepository _objects;
  private IRequirementRepository _requirements;
  private IRiskRepository _risks;
  private IDomainEventPublisher _events;

  this(IProjectRepository projects, ITargetObjectRepository objects, IRequirementRepository requirements,
      IRiskRepository risks, IDomainEventPublisher events) {
    _projects = projects;
    _objects = objects;
    _requirements = requirements;
    _risks = risks;
    _events = events;
  }

  TargetObjectDto[] list(string projectId = "") {
    return toDtos(projectId.length ? _objects.findByProject(projectId) : _objects.findAll);
  }

  TargetObjectDto get(string id) { return toDto(load(id)); }

  TargetObjectDto create(CreateTargetObjectInput input) {
    writableProject(input.projectId);
    auto now = Clock.currTime.toUTC;
    auto o = new DTargetObject(newId(input.ID, (id) => _objects.findById(id) !is null), input.projectId, input.name,
        parseEnum!TargetObjectKind(input.kind), input.description, ProtectionNeed.init, "", now, now);
    o.assessProtectionNeed(ProtectionNeed(parseEnum!ProtectionLevel(input.confidentiality),
        parseEnum!ProtectionLevel(input.integrity), parseEnum!ProtectionLevel(input.availability)),
        input.protectionRationale);
    _objects.save(o);
    _events.raise("TargetObjectCreated", o.id, o.projectId, o.name);
    return toDto(o);
  }

  TargetObjectDto update(string id, UpdateTargetObjectInput input) {
    auto o = load(id);
    writableProject(o.projectId);
    if (!input.name.isNull) o.rename(input.name.get);
    if (!input.kind.isNull) o.changeKind(parseEnum!TargetObjectKind(input.kind.get));
    if (!input.description.isNull) o.describe(input.description.get);
    if (!input.confidentiality.isNull || !input.integrity.isNull || !input.availability.isNull
        || !input.protectionRationale.isNull) {
      auto n = o.protectionNeed;
      if (!input.confidentiality.isNull) n.confidentiality = parseEnum!ProtectionLevel(input.confidentiality.get);
      if (!input.integrity.isNull) n.integrity = parseEnum!ProtectionLevel(input.integrity.get);
      if (!input.availability.isNull) n.availability = parseEnum!ProtectionLevel(input.availability.get);
      o.assessProtectionNeed(n, input.protectionRationale.isNull ? o.protectionRationale : input.protectionRationale.get);
    }
    _objects.save(o);
    _events.raise("TargetObjectUpdated", o.id, o.projectId);
    return toDto(o);
  }

  void remove(string id) {
    auto o = load(id);
    writableProject(o.projectId);
    foreach (r; _risks.findByTargetObject(id)) _risks.remove(r.id);
    foreach (r; _requirements.findByTargetObject(id)) _requirements.remove(r.id);
    _objects.remove(id);
    _events.raise("TargetObjectDeleted", id, o.projectId, o.name);
  }

  private DTargetObject load(string id) {
    auto o = _objects.findById(id);
    if (o is null) throw new EntityNotFoundException("TargetObject", id);
    return o;
  }

  private void writableProject(string projectId) {
    auto p = _projects.findById(projectId);
    if (p is null) throw new EntityNotFoundException("Project", projectId);
    p.ensureWritable;
  }
}
