/// Driving ports for application-wide services.
module uim.myfiori.ports.services;

@safe:

import uim.myfiori.application.dtos;

/// Read access to the IT-Grundschutz-Kompendium catalog (modules, requirements, threats).
interface ICatalogService {
  ModuleDto[] modules();
  /// Throws EntityNotFoundException for unknown codes.
  ModuleDto findModule(string code);
  CatalogRequirementDto[] requirementsOf(string moduleCode);
  ThreatDto[] threats();
  string edition();
}

/// Entities that can be exported / imported.
enum exchangeEntities = ["projects", "targetObjects", "requirements", "risks", "modules", "threats"];
/// Entities that can be imported (catalog data is read-only).
enum importableEntities = ["projects", "targetObjects", "requirements", "risks"];

/**
 * Import and export of entities as JSON or CSV, and of complete projects as JSON bundles.
 * Imports run through the use cases (all business rules apply) inside one transaction:
 * either every row is imported or none.
 */
interface IExchangeService {
  /// format: "json" | "csv"; projectId restricts project-bound entities ("" = all).
  string exportEntities(string entity, string format, string projectId = "", char delimiter = ',');
  /**
   * format: "json" | "csv" | "auto"; mode: "create" | "upsert" | "skip".
   * projectId (optional): target objects are assigned to this project; requirements and
   * risks must belong to it.
   */
  ImportReport importEntities(string entity, string format, string content, string mode = "create",
      bool dryRun = false, string projectId = "");
  /// Project with all target objects, requirements and risks.
  string exportProject(string projectId);
  /// newIds: import as a copy with fresh ids (e.g. from a template project).
  ImportReport importProject(string content, bool newIds = false, bool dryRun = false);
}

/// Backup and restore of the complete data set.
interface IBackupService {
  /// Complete backup document (JSON) with metadata and checksum.
  string createBackup();
  /// Validates the backup and, unless dryRun, replaces all data with it.
  RestoreReport restore(string content, bool dryRun = false);
  /// Writes a backup into the backup directory (applies retention).
  BackupInfo backupToFile(string label = "");
  BackupInfo[] listBackups();
  string readBackup(string name);
  RestoreReport restoreFromFile(string name, bool dryRun = false);
}

/// Driven port: one-way password hashing (implemented in infrastructure.security).
interface IPasswordHasher {
  string hash(string password);
  bool verify(string password, string encoded);
}
