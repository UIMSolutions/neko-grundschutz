/// Use cases for Grundschutz projects.
module uim.myfiori.application.usecases.projects;

@safe:

import std.datetime.systime : Clock;
import std.uuid : randomUUID;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

class DProjectUseCases : IProjectUseCases {
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

  ProjectDto[] list() { return toDtos(_projects.findAll); }

  ProjectDto get(string id) { return toDto(load(id)); }

  ProjectDto create(CreateProjectInput input) {
    auto now = Clock.currTime.toUTC;
    auto p = new DProject(newId(input.ID, (id) => _projects.findById(id) !is null), input.name, input.description, input.scope_, input.owner,
        parseEnum!SecurityApproach(input.approach), ProjectStatus.planned, now, now);
    _projects.save(p);
    _events.raise("ProjectCreated", p.id, p.id, p.name);
    return toDto(p);
  }

  ProjectDto update(string id, UpdateProjectInput input) {
    auto p = load(id);
    if (!input.name.isNull) p.rename(input.name.get);
    if (!input.description.isNull) p.describe(input.description.get);
    if (!input.scope_.isNull) p.changeScope(input.scope_.get);
    if (!input.owner.isNull) p.assignOwner(input.owner.get);
    if (!input.approach.isNull) p.chooseApproach(parseEnum!SecurityApproach(input.approach.get));
    // status last: archiving in the same request must not block the other changes
    if (!input.status.isNull) p.changeStatus(parseEnum!ProjectStatus(input.status.get));
    _projects.save(p);
    _events.raise("ProjectUpdated", p.id, p.id);
    return toDto(p);
  }

  void remove(string id) {
    auto p = load(id);
    foreach (r; _risks.findByProject(id)) _risks.remove(r.id);
    foreach (r; _requirements.findByProject(id)) _requirements.remove(r.id);
    foreach (o; _objects.findByProject(id)) _objects.remove(o.id);
    _projects.remove(id);
    _events.raise("ProjectDeleted", id, id, p.name);
  }

  private DProject load(string id) {
    auto p = _projects.findById(id);
    if (p is null) throw new EntityNotFoundException("Project", id);
    return p;
  }
}
