# UML – BSI IT-Grundschutz

UML views of the solution described in [README.md](README.md). All diagrams use Mermaid.
Module paths are relative to `backend/source/uim/myfiori/`.

1. [Component diagram (hexagonal architecture)](#1-component-diagram-hexagonal-architecture)
2. [Domain class diagram](#2-domain-class-diagram)
3. [Ports & adapters class diagram](#3-ports--adapters-class-diagram)
4. [Application layer & DTOs](#4-application-layer--dtos)
5. [Presentation adapters](#5-presentation-adapters)
6. [Sequence: apply a module via OData (Fiori)](#6-sequence-apply-a-module-via-odata-fiori)
7. [Sequence: authenticated request through the approuter](#7-sequence-authenticated-request-through-the-approuter)
8. [Sequence: CLI command](#8-sequence-cli-command)
9. [State machine: project status](#9-state-machine-project-status)
10. [State machine: requirement implementation status](#10-state-machine-requirement-implementation-status)
11. [Activity: Grundschutz methodology supported by the tool](#11-activity-grundschutz-methodology-supported-by-the-tool)
12. [Deployment diagram](#12-deployment-diagram)
13. [Frontend (UI5) structure](#13-frontend-ui5-structure)
14. [Import / export & backup – class diagram](#14-import--export--backup--class-diagram)
15. [Sequence: transactional CSV import](#15-sequence-transactional-csv-import)
16. [Sequence: project import as a copy](#16-sequence-project-import-as-a-copy)
17. [Sequence: validated restore](#17-sequence-validated-restore)
18. [Activity: restore decision flow](#18-activity-restore-decision-flow)
19. [Sequence: print a project](#19-sequence-print-a-project)

---

## 1. Component diagram (hexagonal architecture)

Dependencies point inwards only. `bootstrap.d` is the only module that knows the concrete adapters.

```mermaid
flowchart LR
  subgraph Presentation["presentation (driving adapters)"]
    CLI["cli<br/>DCommandLine"]
    HTTP["http<br/>router, auth, errors, DExchangeApi"]
    OData["odata<br/>DODataService, $metadata, query"]
    Web["web<br/>DWebController, print + Diet views"]
    GUI["gui<br/>openWebView()"]
  end

  subgraph Ports["ports"]
    PU["usecases<br/>IProjectUseCases …"]
    PS["services<br/>ICatalogService, IExchangeService, IBackupService"]
    PR["repositories<br/>IProjectRepository …"]
    PST["storages<br/>IDocumentStorage, ITransactionManager"]
    PM["messaging<br/>IDomainEventPublisher"]
    PG["gateways<br/>ICatalogGateway"]
  end

  subgraph Application["application"]
    UC["usecases<br/>DProjectUseCases …"]
    AS["services<br/>DCatalogService, DExchangeService, csv, dtomapping, ids, events"]
    DTO["dtos"]
  end

  subgraph Domain["domain"]
    ENT["entities"]
    TYP["types"]
    ENUM["enumerations"]
    DS["services<br/>compliance, protectionneed, riskassessment"]
    EXC["exceptions"]
  end

  subgraph Persistence["persistence (driven adapters)"]
    REP["repositories<br/>DDocumentRepository"]
    STO["storages<br/>memory / JSON file (transactions)<br/>DBackupService"]
    MAP["mappers"]
    REC["records"]
  end

  subgraph Infrastructure["infrastructure"]
    CFG["configuration"]
    LOG["logging<br/>DAuditLogPublisher"]
    SEC["security<br/>JWT, DAuthGuard"]
    CLT["clients<br/>DBuiltinCatalogClient"]
    WRK["workers<br/>DBackupWorker"]
  end

  BOOT(["bootstrap.d<br/>DApplicationContainer"])

  CLI & HTTP & OData & Web --> PU & PS
  OData & Web --> SEC
  GUI --> HTTP
  UC -. implements .-> PU
  AS -. implements .-> PS
  UC --> PR & PM & PS
  UC --> ENT & DS
  AS --> PG
  AS -- "transactions" --> PST
  STO -. "DBackupService implements" .-> PS
  REP -. implements .-> PR
  REP --> PST & MAP
  MAP --> REC & ENT
  STO -. implements .-> PST
  LOG -. implements .-> PM
  CLT -. implements .-> PG
  BOOT --> UC & AS & REP & STO & LOG & CLT & SEC & CFG
```

---

## 2. Domain class diagram

```mermaid
classDiagram
  direction LR

  class DEntity {
    <<abstract>>
    -EntityId _id
    -SysTime _createdAt
    -SysTime _modifiedAt
    +id() EntityId
    +createdAt() SysTime
    +modifiedAt() SysTime
    #touch()
  }

  class DProject {
    -string name, description, scope, owner
    -SecurityApproach approach
    -ProjectStatus status
    +rename(name)
    +describe(text)
    +changeScope(scope)
    +assignOwner(owner)
    +chooseApproach(approach)
    +changeStatus(next)
    +isReadOnly() bool
    +ensureWritable()
  }

  class DTargetObject {
    -EntityId projectId
    -string name, description, protectionRationale
    -TargetObjectKind kind
    -ProtectionNeed protectionNeed
    +rename(name)
    +changeKind(kind)
    +assessProtectionNeed(need, rationale)
  }

  class DRequirement {
    -EntityId projectId, targetObjectId
    -RequirementCode code
    -string title, responsible, note, dueDate
    -RequirementLevel level
    -ImplementationStatus status
    +recordStatus(status, note)
    +assign(responsible)
    +plan(dueDate)
    +isFulfilled() bool
    +moduleCode() string
  }

  class DRisk {
    -EntityId projectId, targetObjectId
    -ThreatCode threatCode
    -string title, description, treatmentNote
    -Frequency frequency
    -Impact impact
    -RiskTreatment treatment
    +level() RiskLevel
    +evaluate(frequency, impact)
    +decideTreatment(treatment, note)
  }

  class ProtectionNeed {
    <<value object>>
    +ProtectionLevel confidentiality
    +ProtectionLevel integrity
    +ProtectionLevel availability
    +overall() ProtectionLevel
    +combine(other) ProtectionNeed
    +requiresRiskAnalysis() bool
  }
  class ModuleCode { <<value object>> +string value }
  class RequirementCode { <<value object>> +string value +moduleCode() ModuleCode }
  class ThreatCode { <<value object>> +string value }

  class ProtectionLevel { <<enumeration>> normal high veryHigh }
  class SecurityApproach { <<enumeration>> basic standard core }
  class ProjectStatus { <<enumeration>> planned inProgress completed archived }
  class TargetObjectKind { <<enumeration>> businessProcess application itSystem icsSystem iotSystem room building network communicationLink }
  class RequirementLevel { <<enumeration>> basic standard elevated }
  class ImplementationStatus { <<enumeration>> open yes partially no dispensable }
  class Frequency { <<enumeration>> rare=1 medium=2 often=3 veryOften=4 }
  class Impact { <<enumeration>> negligible=1 limited=2 considerable=3 existential=4 }
  class RiskLevel { <<enumeration>> low medium high veryHigh }
  class RiskTreatment { <<enumeration>> open avoid reduce transfer accept }

  DEntity <|-- DProject
  DEntity <|-- DTargetObject
  DEntity <|-- DRequirement
  DEntity <|-- DRisk

  DProject "1" o-- "0..*" DTargetObject : projectId
  DTargetObject "1" o-- "0..*" DRequirement : targetObjectId
  DTargetObject "1" o-- "0..*" DRisk : targetObjectId

  DTargetObject *-- ProtectionNeed
  DRequirement *-- RequirementCode
  RequirementCode ..> ModuleCode
  DRisk *-- ThreatCode
  DRisk ..> RiskLevel
  ProtectionNeed ..> ProtectionLevel
  DProject ..> SecurityApproach
  DProject ..> ProjectStatus
  DTargetObject ..> TargetObjectKind
  DRequirement ..> RequirementLevel
  DRequirement ..> ImplementationStatus
  DRisk ..> Frequency
  DRisk ..> Impact
  DRisk ..> RiskTreatment
```

### Domain services and exceptions

```mermaid
classDiagram
  class compliance {
    <<module>>
    +isRelevant(level, approach) bool
    +evaluateCompliance(requirements, approach) ComplianceSummary
  }
  class ComplianceSummary {
    +total, fulfilled, partially, notFulfilled, open, dispensable, basicOpen
    +degree() double
    +basicProtectionAchieved() bool
  }
  class protectionneed {
    <<module>>
    +aggregateProtectionNeed(objects) ProtectionNeed
    +objectsRequiringRiskAnalysis(objects) DTargetObject[]
  }
  class riskassessment {
    <<module>>
    +assessRisk(frequency, impact) RiskLevel
  }
  compliance ..> ComplianceSummary

  class DomainException
  class ValidationException
  class EntityNotFoundException { +entityName +id }
  class ConflictException
  DomainException <|-- ValidationException
  DomainException <|-- EntityNotFoundException
  DomainException <|-- ConflictException
```

Risk matrix (BSI-Standard 200-3, implemented in `assessRisk`):

| Impact \ Frequency | rare (1) | medium (2) | often (3) | very often (4) |
|---|---|---|---|---|
| existential (4) | low | high | very high | very high |
| considerable (3) | low | medium | high | very high |
| limited (2) | low | low | medium | high |
| negligible (1) | low | low | low | low |

---

## 3. Ports & adapters class diagram

```mermaid
classDiagram
  direction TB
  class IRepository~T~ {
    <<interface>>
    +findAll() T[]
    +findById(id) T
    +save(entity)
    +remove(id) bool
  }
  class IProjectRepository { <<interface>> }
  class ITargetObjectRepository { <<interface>> +findByProject(id) }
  class IRequirementRepository { <<interface>> +findByProject(id) +findByTargetObject(id) }
  class IRiskRepository { <<interface>> +findByProject(id) +findByTargetObject(id) }
  IRepository <|-- IProjectRepository
  IRepository <|-- ITargetObjectRepository
  IRepository <|-- IRequirementRepository
  IRepository <|-- IRiskRepository

  class IDocumentStorage {
    <<interface>>
    +all(collection) Json[]
    +get(collection, id) Json
    +put(collection, id, doc)
    +remove(collection, id) bool
    +flush()
    +describe() string
    +snapshot() StorageSnapshot
    +replaceAll(StorageSnapshot)
  }
  class ITransactionManager {
    <<interface>>
    +begin()
    +commit()
    +rollback()
    +inTransaction() bool
  }
  class IDomainEventPublisher { <<interface>> +publish(DomainEvent) }
  class ICatalogGateway { <<interface>> +modules() CatalogModule[] +threats() CatalogThreat[] +edition() string }

  class DDocumentRepository~E,R,collection~ {
    <<abstract>>
    #IDocumentStorage _storage
    #less(a, b) bool
    #where(predicate) E[]
  }
  class DProjectRepository
  class DTargetObjectRepository
  class DRequirementRepository { #less() Kompendium order }
  class DRiskRepository
  DDocumentRepository <|-- DProjectRepository
  DDocumentRepository <|-- DTargetObjectRepository
  DDocumentRepository <|-- DRequirementRepository
  DDocumentRepository <|-- DRiskRepository
  DProjectRepository ..|> IProjectRepository
  DTargetObjectRepository ..|> ITargetObjectRepository
  DRequirementRepository ..|> IRequirementRepository
  DRiskRepository ..|> IRiskRepository
  DDocumentRepository --> IDocumentStorage
  DDocumentRepository ..> mappers : toRecord / toEntity

  class DMemoryDocumentStorage { -StorageSnapshot _data -StorageSnapshot _txBackup #persist() }
  class DJsonFileDocumentStorage { -string _path +flush() atomic write, skipped inside a transaction }
  DMemoryDocumentStorage ..|> IDocumentStorage
  DMemoryDocumentStorage ..|> ITransactionManager
  DMemoryDocumentStorage <|-- DJsonFileDocumentStorage

  class DAuditLogPublisher { +recent(max) DomainEvent[] }
  DAuditLogPublisher ..|> IDomainEventPublisher
  class DBuiltinCatalogClient
  DBuiltinCatalogClient ..|> ICatalogGateway

  class mappers { <<module>> }
  class records { <<module>> ProjectRecord TargetObjectRecord RequirementRecord RiskRecord }
  mappers ..> records
```

---

## 4. Application layer & DTOs

```mermaid
classDiagram
  direction LR
  class IProjectUseCases { <<interface>> +list() +get(id) +create(CreateProjectInput) +update(id, UpdateProjectInput) +remove(id) }
  class ITargetObjectUseCases { <<interface>> +list(projectId) +get +create +update +remove }
  class IRequirementUseCases { <<interface>> +list(projectId, targetObjectId) +get +create +update +remove +applyModule(targetObjectId, moduleCode) }
  class IRiskUseCases { <<interface>> +list +get +create +update +remove }
  class IReportUseCases { <<interface>> +projectReport(projectId) ProjectReportDto +dossier(projectId) ProjectDossierDto }
  class ICatalogService { <<interface>> +modules() +findModule(code) +requirementsOf(module) +threats() +edition() }

  class DProjectUseCases
  class DTargetObjectUseCases
  class DRequirementUseCases
  class DRiskUseCases
  class DReportUseCases
  class DCatalogService

  DProjectUseCases ..|> IProjectUseCases
  DTargetObjectUseCases ..|> ITargetObjectUseCases
  DRequirementUseCases ..|> IRequirementUseCases
  DRiskUseCases ..|> IRiskUseCases
  DReportUseCases ..|> IReportUseCases
  DCatalogService ..|> ICatalogService
  DRequirementUseCases --> ICatalogService : applyModule
  DCatalogService --> ICatalogGateway

  class DApplicationContainer {
    +AppConfig config
    +IDocumentStorage storage
    +DAuditLogPublisher audit
    +ICatalogService catalog
    +IProjectUseCases projects
    +ITargetObjectUseCases targetObjects
    +IRequirementUseCases requirements
    +IRiskUseCases risks
    +IReportUseCases reports
    +IExchangeService exchange
    +IBackupService backups
    +DAuthGuard authGuard
    +inMemory()$ DApplicationContainer
  }
  DApplicationContainer o-- DProjectUseCases
  DApplicationContainer o-- DTargetObjectUseCases
  DApplicationContainer o-- DRequirementUseCases
  DApplicationContainer o-- DRiskUseCases
  DApplicationContainer o-- DReportUseCases

  class ProjectDto
  class TargetObjectDto
  class RequirementDto
  class RiskDto
  class ProjectReportDto
  class ModuleDto
  class ThreatDto
  IProjectUseCases ..> ProjectDto
  ITargetObjectUseCases ..> TargetObjectDto
  IRequirementUseCases ..> RequirementDto
  IRiskUseCases ..> RiskDto
  IReportUseCases ..> ProjectReportDto
  ICatalogService ..> ModuleDto
  ICatalogService ..> ThreatDto
```

---

## 5. Presentation adapters

```mermaid
classDiagram
  class DODataService {
    -DApplicationContainer _app
    -string _base = "/odata/v4/grundschutz"
    +register(URLRouter)
    +handle(req, res)
    -dispatch() -collection() -navigation() -entity()
  }
  class model { <<module>> entityTypes() reportProperties() toODataJson() create*Input() update*Input() }
  class metadata { <<module>> buildMetadata() buildServiceDocument() }
  class query { <<module>> parseQueryOptions() applyQuery() FilterParser }
  DODataService ..> model
  DODataService ..> metadata
  DODataService ..> query

  class DWebController {
    -ubyte[] _csrfSecret
    +register(URLRouter)
    -guarded!(handler)()
    +csrfToken(Principal) string
  }
  class views { <<Diet>> layout.dt index.dt project.dt catalog.dt admin.dt print.dt }
  DWebController ..> views

  class DCommandLine { +run(CliArgs) int -exportCommand() -importCommand() -backup() -restore() }
  class DExchangeApi { +register(URLRouter) -guarded!(handler, scope)() }
  class printWeb { <<module web/print>> renderProjectHtml(dossier, autoPrint) sectionsOf() riskMatrix() }
  class printCli { <<module cli/print>> renderProjectMarkdown(dossier) }
  DCommandLine ..> printWeb
  DCommandLine ..> printCli
  DWebController ..> printWeb
  class CliArgs { +positional +options +flag() +opt() +required() }
  DCommandLine ..> CliArgs

  class server { <<module>> buildRouter() startServer() }
  class gui { <<module>> openWebView(url) webviewCommands(url) }
  class DAuthGuard { +authenticate(header) Principal }
  class Principal { +userName +scopes +hasScope() }

  server --> DODataService
  server --> DWebController
  server --> DExchangeApi
  DExchangeApi --> DAuthGuard
  DODataService --> DAuthGuard
  DWebController --> DAuthGuard
  DAuthGuard ..> Principal
  DCommandLine ..> server : serve / gui (via app.d)
  DCommandLine ..> gui
```

---

## 6. Sequence: apply a module via OData (Fiori)

```mermaid
sequenceDiagram
  autonumber
  actor ISB as ISB (Fiori app)
  participant UI5 as Project.controller.js
  participant OD as DODataService
  participant UC as DRequirementUseCases
  participant CAT as DCatalogService
  participant GW as DBuiltinCatalogClient
  participant TO as DTargetObjectRepository
  participant RQ as DRequirementRepository
  participant ST as DJsonFileDocumentStorage
  participant EV as DAuditLogPublisher

  ISB->>UI5: select target object + module, press "Apply module"
  UI5->>OD: POST /ApplyModule {targetObjectId, moduleCode}
  OD->>OD: authorize(Editor)
  OD->>UC: applyModule(targetObjectId, moduleCode)
  UC->>TO: findById(targetObjectId)
  UC->>UC: project.ensureWritable(), ModuleCode(moduleCode)
  UC->>RQ: findByTargetObject(id)
  UC->>CAT: requirementsOf(moduleCode)
  CAT->>GW: modules()
  GW-->>CAT: CatalogModule[]
  loop each requirement not yet present
    UC->>RQ: save(new DRequirement(status = open))
    RQ->>ST: put("requirements", id, record)
    ST->>ST: flush() (temp file + rename)
  end
  UC->>EV: publish(ModuleApplied)
  UC-->>OD: RequirementDto[]
  OD-->>UI5: 200 {"value":[…]}
  UI5->>OD: GET Projects('p')/requirements (refresh)
  UI5->>OD: GET GetProjectReport(projectId='p')
```

---

## 7. Sequence: authenticated request through the approuter

```mermaid
sequenceDiagram
  autonumber
  actor U as User (browser)
  participant AR as approuter
  participant UAA as XSUAA
  participant BE as backend (DODataService / DWebController)
  participant G as DAuthGuard
  participant J as jwt.validateToken

  U->>AR: GET /
  AR->>UAA: OAuth2 authorization code flow
  UAA-->>AR: JWT (scopes gs!t1.Viewer, gs!t1.Editor)
  AR-->>U: Fiori app (resources/)
  U->>AR: PATCH /odata/v4/grundschutz/Requirements('r') + X-CSRF-Token
  AR->>AR: CSRF check, scope $XSAPPNAME.Viewer
  AR->>BE: PATCH … Authorization: Bearer JWT (forwardAuthToken)
  BE->>G: authenticate(header)
  G->>J: validateToken(token, verificationkey, xsappname)
  J->>J: RS256 verify (OpenSSL EVP), exp, scope prefix
  J-->>G: Principal{scopes=[Viewer, Editor]}
  G-->>BE: Principal
  BE->>BE: hasScope("Editor") else 403
  BE-->>AR: 200 entity
  AR-->>U: 200 entity
```

---

## 8. Sequence: CLI command

```mermaid
sequenceDiagram
  autonumber
  actor Admin
  participant APP as app.d main()
  participant CFG as loadConfig
  participant BOOT as DApplicationContainer
  participant CLI as DCommandLine
  participant UC as DRiskUseCases

  Admin->>APP: grundschutz risk create --object 6fe6 --threat "G 0.39" …
  APP->>APP: parseArgs()
  APP->>CFG: default.json → env → VCAP_SERVICES
  APP->>BOOT: new DApplicationContainer(cfg)
  APP->>CLI: run(args)
  CLI->>CLI: resolveObject("6fe6") (unique prefix)
  CLI->>UC: create(CreateRiskInput)
  UC-->>CLI: RiskDto (level = veryHigh)
  CLI-->>Admin: "Risk (sehr hoch) created: …" / JSON, exit code 0
```

---

## 9. State machine: project status

```mermaid
stateDiagram-v2
  [*] --> planned : create
  planned --> inProgress
  planned --> archived
  inProgress --> completed
  inProgress --> archived
  completed --> inProgress : reopen
  completed --> archived
  archived --> [*]
  note right of archived : read-only (ConflictException on change)
```

## 10. State machine: requirement implementation status

```mermaid
stateDiagram-v2
  [*] --> open : applyModule / create
  open --> yes
  open --> partially
  open --> no : justification required
  open --> dispensable : justification required, not for basic requirements
  partially --> yes
  partially --> no
  no --> partially
  no --> yes
  yes --> partially : re-check
  dispensable --> open : re-assessment
```

The diagram shows the typical lifecycle. The domain (`DRequirement.recordStatus`) allows any
transition and enforces only the two guards above: *no* and *dispensable* need a justification, and
basic requirements can never be *dispensable*.

---

## 11. Activity: Grundschutz methodology supported by the tool

```mermaid
flowchart TD
  A([Start]) --> B[Create project<br/>scope + approach]
  B --> C[Structure analysis:<br/>record target objects]
  C --> D[Protection needs:<br/>C / I / A per object + rationale]
  D --> E{Protection need<br/>above normal?}
  E -- yes --> F[Risk analysis BSI 200-3:<br/>threats G 0.x, frequency × impact]
  F --> G[Risk treatment:<br/>avoid / reduce / transfer / accept]
  E -- no --> H
  G --> H[Modelling:<br/>apply Kompendium modules]
  H --> I[IT-Grundschutz check:<br/>status per requirement]
  I --> J[Report:<br/>degree of fulfilment, open basic reqs, risks]
  J --> K{Basic requirements<br/>fulfilled?}
  K -- no --> I
  K -- yes --> L[Project completed / archived]
  L --> Z([End])
```

---

## 12. Deployment diagram

```mermaid
flowchart TB
  subgraph Client["Client"]
    BR["Browser<br/>Fiori app / web GUI"]
    WV["Desktop webview<br/>chromium --app"]
    SH["Shell<br/>grundschutz CLI"]
  end

  subgraph BTP["SAP BTP – Cloud Foundry space"]
    AR["grundschutz-approuter<br/>approuter.nodejs<br/>resources/ = frontend"]
    SRV["grundschutz-srv<br/>binary_buildpack<br/>./grundschutz serve"]
    XS[("grundschutz-xsuaa<br/>xsuaa / application")]
    DISK[("ephemeral disk<br/>data/grundschutz.json")]
  end

  subgraph Local["Workstation (local mode)"]
    LSRV["grundschutz serve / gui<br/>127.0.0.1:8080"]
    LFILE[("backend/data/grundschutz.json")]
  end

  CDN["ui5.sap.com · jsDelivr<br/>(UI5, daisyUI)"]

  BR -- HTTPS --> AR
  AR -- "destination grundschutz-backend<br/>Bearer JWT" --> SRV
  AR -. OAuth2 .-> XS
  SRV -. VCAP_SERVICES verificationkey .-> XS
  SRV --- DISK
  WV -- HTTP --> LSRV
  SH --- LFILE
  LSRV --- LFILE
  BR -. static libs .-> CDN
```

---

## 13. Frontend (UI5) structure

```mermaid
classDiagram
  class Component { +init() +getContentDensityClass() }
  class BaseController { +formatter +getRouter() +getText() +showError() +createIn(binding, data) +apiUrl(path) +download(path) +openPrint(id) +pickFile(accept) +uploadFile(path, file) +showImportReport(report) +onNavBack() }
  class AppController
  class MainController { +onSearch() +onProjectPress() +onCreateProject() +onImportProject() +onExportProjects(format) +onDownloadBackup() +onOpenAdmin() }
  class ProjectController { +onApplyModule() +onCreateObject() +onCreateRisk() +onDeleteSelected() +onStatusFilter() +onPrint() +onExportProject() +onExportEntity(entity, format) +onImportEntity(entity) -_loadReport() }
  class formatter { <<module>> enumText() protectionState() riskState() implementationState() percent() }
  class models { <<module>> createDeviceModel() createEnumModel() }
  BaseController <|-- AppController
  BaseController <|-- MainController
  BaseController <|-- ProjectController
  BaseController ..> formatter
  Component ..> models

  class ODataModelV4 { <<sap.ui.model.odata.v4>> groupId=$direct }
  Component --> ODataModelV4 : "" (mainService)
  MainController ..> ODataModelV4 : /Projects
  ProjectController ..> ODataModelV4 : targetObjects, requirements, risks, /ApplyModule, GetProjectReport
  class ExchangeAPI { <<HTTP /api>> }
  MainController ..> ExchangeAPI : projects import/export, backup
  ProjectController ..> ExchangeAPI : entity import/export, project export
```

| Route | Pattern | View |
|---|---|---|
| `main` | `` | `Main.view.xml` – project list, create dialog |
| `project` | `project/{projectId}` | `Project.view.xml` – tabs: target objects, IT-Grundschutz check, risk analysis, report, master data |

---

## 14. Import / export & backup – class diagram

```mermaid
classDiagram
  direction LR
  class IExchangeService {
    <<interface>>
    +exportEntities(entity, format, projectId, delimiter) string
    +importEntities(entity, format, content, mode, dryRun, projectId) ImportReport
    +exportProject(projectId) string
    +importProject(content, newIds, dryRun) ImportReport
  }
  class IBackupService {
    <<interface>>
    +createBackup() string
    +restore(content, dryRun) RestoreReport
    +backupToFile(label) BackupInfo
    +listBackups() BackupInfo[]
    +readBackup(name) string
    +restoreFromFile(name, dryRun) RestoreReport
  }
  class DExchangeService {
    -ITransactionManager _tx
    -importRow(entity, item, mode) Outcome
    -scopeToProject(entity, item, projectId)
    -applyStatus(projectId, target)
    -transaction(report, dryRun, work)
    -parseItems(entity, format, content) Json[]
  }
  class csv {
    <<module>>
    +writeCsv(header, rows, delimiter) string
    +parseCsv(text, delimiter) string[][]
    +detectDelimiter(text) char
    +csvCell(value, delimiter) string
  }
  class DBackupService {
    -IDocumentStorage _storage
    -string _dir
    -int _retention
    -validate(content, report) StorageSnapshot
    -applyRetention()
    -isBackupName(name) bool
  }
  class backupModule {
    <<module>>
    +checksum(Json) string
    +canonicalJson(Json) string
  }
  class ImportReport { entity dryRun committed total created updated skipped failed issues }
  class ImportIssue { row id message }
  class RestoreReport { dryRun valid restored createdAt applicationVersion safetyBackup counts issues }
  class BackupInfo { name createdAt size }

  DExchangeService ..|> IExchangeService
  DExchangeService ..> csv
  DExchangeService --> IProjectUseCases
  DExchangeService --> ITargetObjectUseCases
  DExchangeService --> IRequirementUseCases
  DExchangeService --> IRiskUseCases
  DExchangeService --> ICatalogService
  DExchangeService --> ITransactionManager
  DExchangeService ..> ImportReport
  ImportReport *-- ImportIssue
  DBackupService ..|> IBackupService
  DBackupService --> IDocumentStorage
  DBackupService ..> backupModule
  DBackupService ..> DMemoryDocumentStorage : scratch store for validation
  DBackupService ..> DProjectRepository : decode records
  DBackupService ..> RestoreReport
  DBackupService ..> BackupInfo
  DBackupWorker --> IBackupService : backupToFile("auto")
```

| Mode | Existing ID | New / no ID |
|---|---|---|
| `create` | row error → whole import rolled back | created (ID kept if given) |
| `upsert` | updated (only columns present) | created |
| `skip` | skipped | created |

---

## 15. Sequence: transactional CSV import

```mermaid
sequenceDiagram
  autonumber
  actor ISB
  participant UI as Fiori / web GUI / CLI
  participant API as DExchangeApi
  participant EX as DExchangeService
  participant TX as ITransactionManager (storage)
  participant UC as DRequirementUseCases
  participant ST as DJsonFileDocumentStorage

  ISB->>UI: choose check.csv, mode = upsert
  UI->>API: POST /api/import/requirements?mode=upsert&projectId=p (text/csv + CSRF token)
  API->>API: authorize(Editor), ensureNotCrossSite
  API->>EX: importEntities("requirements", "auto", csv, "upsert", false, p)
  EX->>EX: detectDelimiter, parseCsv → items
  EX->>TX: begin() (snapshot, flushing suspended)
  loop every row
    EX->>EX: scopeToProject (target object must belong to p)
    alt ID exists
      EX->>UC: update(id, UpdateRequirementInput)
    else
      EX->>UC: create(CreateRequirementInput{ID})
    end
    UC->>ST: put(...) (in memory only)
    Note over EX,UC: DomainException → ImportIssue(row, id, message)
  end
  alt failed > 0 or dryRun
    EX->>TX: rollback() (snapshot restored)
  else
    EX->>TX: commit()
    TX->>ST: flush() (one atomic file write)
  end
  EX-->>API: ImportReport
  API-->>UI: 200 / 422 + report
  UI-->>ISB: summary or list of failing rows
```

---

## 16. Sequence: project import as a copy

```mermaid
sequenceDiagram
  autonumber
  participant EX as DExchangeService
  participant TX as ITransactionManager
  participant PU as ProjectUseCases
  participant OU as TargetObjectUseCases
  participant RU as Requirement/RiskUseCases

  EX->>EX: parse bundle (format grundschutz-project)
  EX->>TX: begin()
  EX->>EX: map(oldId) → new UUID (newIds = true)
  EX->>PU: create(project, ID = map(project.ID))
  loop target objects
    EX->>OU: create(object, projectId = new, ID = map(object.ID))
  end
  loop requirements, risks
    EX->>RU: create(item, targetObjectId = map(old), ID = map(item.ID))
  end
  EX->>PU: applyStatus(planned → … → original status)
  alt any failure
    EX->>TX: rollback()
  else
    EX->>TX: commit()
  end
```

---

## 17. Sequence: validated restore

```mermaid
sequenceDiagram
  autonumber
  actor Admin
  participant UI as Web GUI /web/admin
  participant BS as DBackupService
  participant SC as scratch DMemoryDocumentStorage
  participant RP as repositories (on scratch)
  participant ST as live storage
  participant FS as backup directory

  Admin->>UI: upload backup, tick "Bestätigen"
  UI->>BS: restore(content, dryRun = false)
  BS->>BS: parse, check format/formatVersion/schemaVersion
  BS->>BS: checksum(data) == document.checksum ?
  BS->>SC: replaceAll(data)
  BS->>RP: findAll() for projects, objects, requirements, risks (decode + domain validation)
  BS->>BS: check references (object→project, requirement/risk→object, projectId consistent)
  alt issues found
    BS-->>UI: RestoreReport{valid = false, issues}
  else valid
    BS->>FS: backupToFile("pre-restore") (current state)
    BS->>ST: replaceAll(data) → atomic file write
    BS-->>UI: RestoreReport{restored = true, safetyBackup}
  end
```

## 18. Activity: restore decision flow

```mermaid
flowchart TD
  A([Backup file or server backup]) --> B{Valid JSON and<br/>format grundschutz-backup?}
  B -- no --> X[Reject: invalid]
  B -- yes --> C{Version supported?}
  C -- no --> X
  C -- yes --> D{Checksum matches?}
  D -- no --> X2[Reject: corrupt or modified]
  D -- yes --> E[Decode all records<br/>on a scratch store]
  E --> F{Records and<br/>references valid?}
  F -- no --> X3[Reject: list of issues]
  F -- yes --> G{Confirmed?<br/>--yes / Bestätigen / no dryRun}
  G -- no --> V[Report: valid – nothing changed]
  G -- yes --> H[Write safety backup<br/>…-pre-restore.json]
  H --> I{Safety backup ok?}
  I -- no --> X4[Abort]
  I -- yes --> J[Replace data set atomically]
  J --> K([Restored])
```

---

## 19. Sequence: print a project

```mermaid
sequenceDiagram
  autonumber
  actor ISB
  participant F as Fiori (Project page)
  participant W as DWebController
  participant R as DReportUseCases
  participant P as web/print renderProjectHtml
  participant B as Browser print dialog

  ISB->>F: press "Print"
  F->>W: open /web/projects/{id}/print?auto=1 (new tab)
  W->>R: dossier(id)
  R-->>W: ProjectDossierDto (report, objects, requirements, risks, catalog edition)
  W->>P: render print.dt (sections per target object, risk matrix)
  P-->>W: A4 HTML
  W-->>B: HTML, window.print() on load
  B-->>ISB: printer / PDF
```

CLI: `grundschutz project print <id>` uses the same `dossier()` together with `renderProjectMarkdown`, or
`renderProjectHtml` with `--format html`.
