/**
 * Data transfer objects crossing the application boundary.
 * Enumerations are transported as their member names (e.g. "veryHigh").
 */
module uim.myfiori.application.dtos;

@safe:

import std.typecons : Nullable;

// ---------------------------------------------------------------- output models

struct ProjectDto {
  string ID;
  string name;
  string description;
  string scope_;
  string owner;
  string approach;
  string status;
  string createdAt;
  string modifiedAt;
}

struct TargetObjectDto {
  string ID;
  string projectId;
  string name;
  string kind;
  string description;
  string confidentiality;
  string integrity;
  string availability;
  string protectionLevel;      // overall (Maximumprinzip)
  string protectionRationale;
  bool requiresRiskAnalysis;
  string createdAt;
  string modifiedAt;
}

struct RequirementDto {
  string ID;
  string projectId;
  string targetObjectId;
  string code;
  string moduleCode;
  string title;
  string level;
  string status;
  string responsible;
  string note;
  string dueDate;
  string createdAt;
  string modifiedAt;
}

struct RiskDto {
  string ID;
  string projectId;
  string targetObjectId;
  string threatCode;
  string title;
  string description;
  int frequency;
  int impact;
  string level;
  string treatment;
  string treatmentNote;
  string createdAt;
  string modifiedAt;
}

struct ModuleDto {
  string code;
  string title;
  string layer;
  string description;
  int requirementCount;
}

struct CatalogRequirementDto {
  string code;
  string moduleCode;
  string title;
  string level;
}

struct ThreatDto {
  string code;
  string title;
}

struct ProjectReportDto {
  ProjectDto project;
  int targetObjectCount;
  string confidentiality;
  string integrity;
  string availability;
  string protectionLevel;
  string[] objectsRequiringRiskAnalysis;
  int requirementsTotal;
  int requirementsFulfilled;
  int requirementsPartially;
  int requirementsNotFulfilled;
  int requirementsOpen;
  int requirementsDispensable;
  int basicRequirementsOpen;
  bool basicProtectionAchieved;
  double complianceDegree;
  int risksTotal;
  int risksLow;
  int risksMedium;
  int risksHigh;
  int risksVeryHigh;
  int risksUntreated;
}

// ---------------------------------------------------------------- input models

struct CreateProjectInput {
  string name;
  string description;
  string scope_;
  string owner;
  string approach = "standard";
  string ID;           // optional: keep this id (import); empty = generate
}

struct UpdateProjectInput {
  Nullable!string name;
  Nullable!string description;
  Nullable!string scope_;
  Nullable!string owner;
  Nullable!string approach;
  Nullable!string status;
}

struct CreateTargetObjectInput {
  string projectId;
  string name;
  string kind;
  string description;
  string confidentiality = "normal";
  string integrity = "normal";
  string availability = "normal";
  string protectionRationale;
  string ID;           // optional: keep this id (import); empty = generate
}

struct UpdateTargetObjectInput {
  Nullable!string name;
  Nullable!string kind;
  Nullable!string description;
  Nullable!string confidentiality;
  Nullable!string integrity;
  Nullable!string availability;
  Nullable!string protectionRationale;
}

struct CreateRequirementInput {
  string targetObjectId;
  string code;
  string title;
  string level = "basic";
  string status = "open";
  string responsible;
  string note;
  string dueDate;
  string ID;           // optional: keep this id (import); empty = generate
}

struct UpdateRequirementInput {
  Nullable!string title;
  Nullable!string status;
  Nullable!string responsible;
  Nullable!string note;
  Nullable!string dueDate;
}

struct CreateRiskInput {
  string targetObjectId;
  string threatCode;
  string title;
  string description;
  int frequency = 1;
  int impact = 1;
  string treatment = "open";
  string treatmentNote;
  string ID;           // optional: keep this id (import); empty = generate
}

struct UpdateRiskInput {
  Nullable!string title;
  Nullable!string description;
  Nullable!int frequency;
  Nullable!int impact;
  Nullable!string treatment;
  Nullable!string treatmentNote;
}

// ---------------------------------------------------------------- printing

/// Everything needed to print a project (Sicherheitskonzept-Dossier).
struct ProjectDossierDto {
  ProjectReportDto report;
  TargetObjectDto[] targetObjects;
  RequirementDto[] requirements;
  RiskDto[] risks;
  string catalogEdition;
  string generatedAt;
}

// ---------------------------------------------------------------- import / export / backup

struct ImportIssue {
  int row;          // 1-based data row (CSV: line number incl. header)
  string id;
  string message;
}

struct ImportReport {
  string entity;
  bool dryRun;
  bool committed;   // false if dry run or any row failed (imports are all-or-nothing)
  int total;
  int created;
  int updated;
  int skipped;
  int failed;
  ImportIssue[] issues;
}

struct BackupInfo {
  string name;
  string createdAt;
  long size;
}

struct RestoreReport {
  bool dryRun;
  bool valid;
  bool restored;
  string createdAt;          // of the backup
  string applicationVersion; // of the backup
  string safetyBackup;       // backup taken before restoring (file name)
  int projects;
  int targetObjects;
  int requirements;
  int risks;
  string[] issues;
}

// ---------------------------------------------------------------- users

/// User account without credentials.
struct UserDto {
  string ID;
  string userName;
  string displayName;
  string email;
  string role;            // viewer | editor | admin
  bool active;
  string[] scopes;
  string lastLoginAt;
  string createdAt;
}

struct CreateUserInput {
  string userName;
  string displayName;
  string email;
  string role = "viewer";
  string password;
  bool active = true;
}

struct UpdateUserInput {
  Nullable!string displayName;
  Nullable!string email;
  Nullable!string role;
  Nullable!bool active;
}
