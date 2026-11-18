/// Technical storage schemas (one record per document). Version field allows migrations.
module uim.myfiori.persistence.records;

@safe:

enum int schemaVersion = 1;

struct ProjectRecord {
  int v = schemaVersion;
  string id, name, description, scope_, owner, approach, status, createdAt, modifiedAt;
}

struct TargetObjectRecord {
  int v = schemaVersion;
  string id, projectId, name, kind, description;
  string confidentiality, integrity, availability, protectionRationale;
  string createdAt, modifiedAt;
}

struct RequirementRecord {
  int v = schemaVersion;
  string id, projectId, targetObjectId, code, title, level, status, responsible, note, dueDate;
  string createdAt, modifiedAt;
}

struct RiskRecord {
  int v = schemaVersion;
  string id, projectId, targetObjectId, threatCode, title, description;
  int frequency, impact;
  string treatment, treatmentNote, createdAt, modifiedAt;
}

/// Collection names inside the document storage.
enum Collections : string {
  projects = "projects",
  targetObjects = "targetObjects",
  requirements = "requirements",
  risks = "risks",
}
