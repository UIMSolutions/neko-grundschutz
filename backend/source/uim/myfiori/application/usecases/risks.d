/// Use cases for the risk analysis (BSI-Standard 200-3).
module uim.myfiori.application.usecases.risks;

@safe:

import std.datetime.systime : Clock;
import std.uuid : randomUUID;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

class DRiskUseCases : IRiskUseCases {
  private IProjectRepository _projects;
  private ITargetObjectRepository _objects;
  private IRiskRepository _risks;
  private IDomainEventPublisher _events;

  this(IProjectRepository projects, ITargetObjectRepository objects, IRiskRepository risks,
      IDomainEventPublisher events) {
    _projects = projects;
    _objects = objects;
    _risks = risks;
    _events = events;
  }

  RiskDto[] list(string projectId = "", string targetObjectId = "") {
    if (targetObjectId.length) return toDtos(_risks.findByTargetObject(targetObjectId));
    if (projectId.length) return toDtos(_risks.findByProject(projectId));
    return toDtos(_risks.findAll);
  }

  RiskDto get(string id) { return toDto(load(id)); }

  RiskDto create(CreateRiskInput input) {
    auto o = writableTarget(input.targetObjectId);
    auto now = Clock.currTime.toUTC;
    auto r = new DRisk(newId(input.ID, (id) => _risks.findById(id) !is null), o.projectId, o.id, ThreatCode(input.threatCode), input.title,
        input.description, scale!Frequency(input.frequency), scale!Impact(input.impact),
        RiskTreatment.open, "", now, now);
    r.decideTreatment(parseEnum!RiskTreatment(input.treatment), input.treatmentNote);
    _risks.save(r);
    _events.raise("RiskCreated", r.id, r.projectId, r.threatCode.value);
    return toDto(r);
  }

  RiskDto update(string id, UpdateRiskInput input) {
    auto r = load(id);
    writableTarget(r.targetObjectId);
    if (!input.title.isNull || !input.description.isNull)
      r.describe(input.title.isNull ? r.title : input.title.get,
          input.description.isNull ? r.description : input.description.get);
    if (!input.frequency.isNull || !input.impact.isNull)
      r.evaluate(input.frequency.isNull ? r.frequency : scale!Frequency(input.frequency.get),
          input.impact.isNull ? r.impact : scale!Impact(input.impact.get));
    // re-check the treatment rule whenever the evaluation or the treatment changes
    r.decideTreatment(input.treatment.isNull ? r.treatment : parseEnum!RiskTreatment(input.treatment.get),
        input.treatmentNote.isNull ? r.treatmentNote : input.treatmentNote.get);
    _risks.save(r);
    _events.raise("RiskUpdated", r.id, r.projectId, r.level.label);
    return toDto(r);
  }

  void remove(string id) {
    auto r = load(id);
    writableTarget(r.targetObjectId);
    _risks.remove(id);
    _events.raise("RiskDeleted", id, r.projectId, r.threatCode.value);
  }

  private DRisk load(string id) {
    auto r = _risks.findById(id);
    if (r is null) throw new EntityNotFoundException("Risk", id);
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
