/// Converters between storage records and domain entities.
module uim.myfiori.persistence.mappers;

@safe:

import std.conv : to;
import std.datetime.systime : SysTime;
import uim.myfiori.domain;
import uim.myfiori.persistence.records;

private string ts(SysTime t) { return t == SysTime.init ? "" : t.toUTC.toISOExtString; }
private SysTime parseTs(string s) { return s.length ? SysTime.fromISOExtString(s) : SysTime.init; }

ProjectRecord toRecord(const DProject p) {
  return ProjectRecord(schemaVersion, p.id, p.name, p.description, p.scope_, p.owner,
      p.approach.to!string, p.status.to!string, ts(p.createdAt), ts(p.modifiedAt));
}

DProject toEntity(ProjectRecord r) {
  return new DProject(r.id, r.name, r.description, r.scope_, r.owner, parseEnum!SecurityApproach(r.approach),
      parseEnum!ProjectStatus(r.status), parseTs(r.createdAt), parseTs(r.modifiedAt));
}

TargetObjectRecord toRecord(const DTargetObject o) {
  auto n = o.protectionNeed;
  return TargetObjectRecord(schemaVersion, o.id, o.projectId, o.name, o.kind.to!string, o.description,
      n.confidentiality.to!string, n.integrity.to!string, n.availability.to!string,
      o.protectionRationale, ts(o.createdAt), ts(o.modifiedAt));
}

DTargetObject toEntity(TargetObjectRecord r) {
  auto need = ProtectionNeed(parseEnum!ProtectionLevel(r.confidentiality),
      parseEnum!ProtectionLevel(r.integrity), parseEnum!ProtectionLevel(r.availability));
  // rehydration bypasses business rules on purpose (stored state was valid when written)
  return new DTargetObject(r.id, r.projectId, r.name, parseEnum!TargetObjectKind(r.kind), r.description,
      need, r.protectionRationale, parseTs(r.createdAt), parseTs(r.modifiedAt));
}

RequirementRecord toRecord(const DRequirement q) {
  return RequirementRecord(schemaVersion, q.id, q.projectId, q.targetObjectId, q.code.value, q.title,
      q.level.to!string, q.status.to!string, q.responsible, q.note, q.dueDate, ts(q.createdAt), ts(q.modifiedAt));
}

DRequirement toEntity(RequirementRecord r) {
  return new DRequirement(r.id, r.projectId, r.targetObjectId, RequirementCode(r.code), r.title,
      parseEnum!RequirementLevel(r.level), parseEnum!ImplementationStatus(r.status), r.responsible, r.note,
      r.dueDate, parseTs(r.createdAt), parseTs(r.modifiedAt));
}

RiskRecord toRecord(const DRisk k) {
  return RiskRecord(schemaVersion, k.id, k.projectId, k.targetObjectId, k.threatCode.value, k.title,
      k.description, cast(int) k.frequency, cast(int) k.impact, k.treatment.to!string, k.treatmentNote,
      ts(k.createdAt), ts(k.modifiedAt));
}

DRisk toEntity(RiskRecord r) {
  return new DRisk(r.id, r.projectId, r.targetObjectId, ThreatCode(r.threatCode), r.title, r.description,
      cast(Frequency) r.frequency, cast(Impact) r.impact, parseEnum!RiskTreatment(r.treatment),
      r.treatmentNote, parseTs(r.createdAt), parseTs(r.modifiedAt));
}
