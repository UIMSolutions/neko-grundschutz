/// Entity → DTO conversion shared by all use cases.
module uim.myfiori.application.services.dtomapping;

@safe:

import std.conv : to;
import std.datetime.systime : SysTime;
import uim.myfiori.application.dtos;
import uim.myfiori.domain;

/// ISO 8601 UTC timestamp with second precision (Edm.DateTimeOffset, Precision 0).
string isoTime(SysTime t) {
  import core.time : Duration;
  if (t == SysTime.init) return "";
  auto u = t.toUTC;
  u.fracSecs = Duration.zero;
  return u.toISOExtString;
}

ProjectDto toDto(const DProject p) {
  return ProjectDto(p.id, p.name, p.description, p.scope_, p.owner, p.approach.to!string,
      p.status.to!string, isoTime(p.createdAt), isoTime(p.modifiedAt));
}

TargetObjectDto toDto(const DTargetObject o) {
  auto n = o.protectionNeed;
  return TargetObjectDto(o.id, o.projectId, o.name, o.kind.to!string, o.description,
      n.confidentiality.to!string, n.integrity.to!string, n.availability.to!string,
      n.overall.to!string, o.protectionRationale, n.requiresRiskAnalysis,
      isoTime(o.createdAt), isoTime(o.modifiedAt));
}

RequirementDto toDto(const DRequirement r) {
  return RequirementDto(r.id, r.projectId, r.targetObjectId, r.code.value, r.moduleCode, r.title,
      r.level.to!string, r.status.to!string, r.responsible, r.note, r.dueDate,
      isoTime(r.createdAt), isoTime(r.modifiedAt));
}

RiskDto toDto(const DRisk r) {
  return RiskDto(r.id, r.projectId, r.targetObjectId, r.threatCode.value, r.title, r.description,
      cast(int) r.frequency, cast(int) r.impact, r.level.to!string, r.treatment.to!string,
      r.treatmentNote, isoTime(r.createdAt), isoTime(r.modifiedAt));
}

/// Maps a list of entities to DTOs.
auto toDtos(T)(T[] entities) {
  import std.algorithm : map;
  import std.array : array;
  return entities.map!(e => toDto(e)).array;
}

/// Converts an integer (1-4) into Frequency / Impact with validation.
E scale(E)(int value) if (is(E == Frequency) || is(E == Impact)) {
  if (value < 1 || value > 4)
    throw new ValidationException(E.stringof ~ " must be between 1 and 4");
  return cast(E) value;
}
