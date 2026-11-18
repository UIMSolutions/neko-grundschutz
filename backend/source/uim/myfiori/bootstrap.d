/**
 * Composition root: wires adapters to ports. The only module that knows
 * all concrete implementations.
 */
module uim.myfiori.bootstrap;

@safe:

import uim.myfiori.application;
import uim.myfiori.infrastructure;
import uim.myfiori.persistence;
import uim.myfiori.ports;
import uim.myfiori.appinfo : appVersion;

class DApplicationContainer {
  AppConfig config;
  IDocumentStorage storage;
  DAuditLogPublisher audit;
  ICatalogGateway catalogGateway;
  ICatalogService catalog;
  IProjectUseCases projects;
  ITargetObjectUseCases targetObjects;
  IRequirementUseCases requirements;
  IRiskUseCases risks;
  IReportUseCases reports;
  IExchangeService exchange;
  IBackupService backups;
  DAuthGuard authGuard;

  this(AppConfig config) {
    this(config, config.storage == "memory"
        ? new DMemoryDocumentStorage
        : new DJsonFileDocumentStorage(config.dataFile));
  }

  this(AppConfig config, DMemoryDocumentStorage storage) {
    this.config = config;
    this.storage = storage;
    audit = new DAuditLogPublisher;
    catalogGateway = new DBuiltinCatalogClient;
    catalog = new DCatalogService(catalogGateway);
    authGuard = new DAuthGuard(config);

    auto projectRepo = new DProjectRepository(storage);
    auto objectRepo = new DTargetObjectRepository(storage);
    auto requirementRepo = new DRequirementRepository(storage);
    auto riskRepo = new DRiskRepository(storage);

    projects = new DProjectUseCases(projectRepo, objectRepo, requirementRepo, riskRepo, audit);
    targetObjects = new DTargetObjectUseCases(projectRepo, objectRepo, requirementRepo, riskRepo, audit);
    requirements = new DRequirementUseCases(projectRepo, objectRepo, requirementRepo, catalog, audit);
    risks = new DRiskUseCases(projectRepo, objectRepo, riskRepo, audit);
    reports = new DReportUseCases(projectRepo, objectRepo, requirementRepo, riskRepo, catalog);
    exchange = new DExchangeService(projects, targetObjects, requirements, risks, catalog, storage, appVersion);
    backups = new DBackupService(storage, config.backupDir, config.backupRetention, appVersion, catalog.edition);
  }

  /// Volatile container for tests.
  static DApplicationContainer inMemory() {
    AppConfig cfg;
    cfg.storage = "memory";
    return new DApplicationContainer(cfg, new DMemoryDocumentStorage);
  }
}
