/// Reporting use case: protection need, IT-Grundschutz-Check and risk overview of one project.
module uim.myfiori.application.usecases.reports;

@safe:

import std.algorithm : map;
import std.array : array;
import std.conv : to;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

class DReportUseCases : IReportUseCases {
  private IProjectRepository _projects;
  private ITargetObjectRepository _objects;
  private IRequirementRepository _requirements;
  private IRiskRepository _risks;
  private ICatalogService _catalog;

  this(IProjectRepository projects, ITargetObjectRepository objects, IRequirementRepository requirements,
      IRiskRepository risks, ICatalogService catalog = null) {
    _projects = projects;
    _objects = objects;
    _requirements = requirements;
    _risks = risks;
    _catalog = catalog;
  }

  ProjectDossierDto dossier(string projectId) {
    import std.datetime.systime : Clock;
    ProjectDossierDto d;
    d.report = projectReport(projectId);
    d.targetObjects = toDtos(_objects.findByProject(projectId));
    d.requirements = toDtos(_requirements.findByProject(projectId));
    d.risks = toDtos(_risks.findByProject(projectId));
    d.catalogEdition = _catalog is null ? "" : _catalog.edition;
    d.generatedAt = isoTime(Clock.currTime);
    return d;
  }

  ProjectReportDto projectReport(string projectId) {
    auto p = _projects.findById(projectId);
    if (p is null) throw new EntityNotFoundException("Project", projectId);

    auto objects = _objects.findByProject(projectId);
    auto need = aggregateProtectionNeed(objects);
    auto compliance = evaluateCompliance(_requirements.findByProject(projectId), p.approach);

    ProjectReportDto r;
    r.project = toDto(p);
    r.targetObjectCount = cast(int) objects.length;
    r.confidentiality = need.confidentiality.to!string;
    r.integrity = need.integrity.to!string;
    r.availability = need.availability.to!string;
    r.protectionLevel = need.overall.to!string;
    r.objectsRequiringRiskAnalysis = objectsRequiringRiskAnalysis(objects).map!(o => o.name).array;
    r.requirementsTotal = cast(int) compliance.total;
    r.requirementsFulfilled = cast(int) compliance.fulfilled;
    r.requirementsPartially = cast(int) compliance.partially;
    r.requirementsNotFulfilled = cast(int) compliance.notFulfilled;
    r.requirementsOpen = cast(int) compliance.open;
    r.requirementsDispensable = cast(int) compliance.dispensable;
    r.basicRequirementsOpen = cast(int) compliance.basicOpen;
    r.basicProtectionAchieved = compliance.basicProtectionAchieved;
    r.complianceDegree = compliance.degree;

    foreach (risk; _risks.findByProject(projectId)) {
      r.risksTotal++;
      final switch (risk.level) {
        case RiskLevel.low: r.risksLow++; break;
        case RiskLevel.medium: r.risksMedium++; break;
        case RiskLevel.high: r.risksHigh++; break;
        case RiskLevel.veryHigh: r.risksVeryHigh++; break;
      }
      if (risk.treatment == RiskTreatment.open) r.risksUntreated++;
    }
    return r;
  }
}
