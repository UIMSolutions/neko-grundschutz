# BSI IT-Grundschutz – Project Management

Manage **BSI IT-Grundschutz** projects (security concepts per BSI-Standard 200-2 and
risk analyses per BSI-Standard 200-3) with:

| Interface | Technology | Entry point |
|-----------|------------|-------------|
| **OData v4** service | vibe.d 0.10.3 (D) | `/odata/v4/grundschutz/` (`$metadata`) |
| **Fiori app** | SAP Fiori 3 / UI5 1.120 (`sap_fiori_3`) | `/ui/index.html` (local) – `/` behind the approuter |
| **Web GUI** | Diet templates + Beer CSS + htmx (server-side rendered, login + user management) | `/web` |
| **Desktop webview** | web GUI in a chromeless browser window | `grundschutz gui` |
| **CLI** | same use cases, table or JSON output | `grundschutz help` |
| **Exchange / backup API** | file import & export, backup & restore | `/api/…` |

All interfaces are thin adapters around one **hexagonal / Clean Architecture** backend. The
domain logic exists once: protection need, IT-Grundschutz check and the risk matrix.

> Further documentation: [uml.md](uml.md) (UML diagrams) · [nafv4.md](nafv4.md) (NAF v4 architecture description)

---

## Functional scope

| BSI step | Supported by |
|----------|--------------|
| Initiation, scope (*Geltungsbereich*), approach (Basis-, Standard-, Kern-Absicherung) | Project |
| Structure analysis (*Strukturanalyse*) | Target objects (*Zielobjekte*): business process, application, IT/ICS/IoT system, room, building, network, communication link |
| Protection needs (*Schutzbedarfsfeststellung*) | Confidentiality, integrity and availability per target object. A raised need must be justified. The **maximum principle** gives the aggregated need of the information domain. |
| Modelling (*Modellierung*) | Apply a Kompendium module (*Baustein*) to a target object. This creates all of its requirements and is idempotent. |
| IT-Grundschutz check | Status per requirement: open / yes / partially / no / dispensable, plus who is responsible, due date and justification |
| Risk analysis (BSI 200-3) | Elementary threats G 0.1 – G 0.47, frequency × impact → 4×4 risk matrix, treatment (avoid / reduce / transfer / accept) |
| Reporting | Degree of fulfilment, open basic requirements, protection need, risk distribution, untreated risks |
| Documentation | **Printable security concept** (A4 dossier with cover, summary, protection needs, check, risk matrix, sign-off) as HTML/PDF or Markdown |
| Data exchange | **Import and export of every entity** (CSV or JSON), complete **project export/import** (also as a copy, e.g. from a template) |
| Operations | **Complete backup and restore** with SHA-256 checksum, validation, dry run, automatic safety backup and retention |

**Business rules enforced in the domain:**

- A protection need above *normal* requires a rationale.
- Status *no* and *dispensable* require a justification.
- Basic requirements (*Basis-Anforderungen*) can never be *dispensable*.
- Accepting a *high* or *very high* risk requires a documented justification.
- Project status may only move planned → inProgress → completed → archived; a completed project can be reopened.
- Archived projects are read-only. Deleting a project, or a target object, removes everything that depends on it.
- Relevant requirements depend on the approach: Basis = basic only; Standard = basic + standard; Kern = all.

The built-in catalog (`infrastructure/clients`) is an **excerpt** of the IT-Grundschutz-Kompendium
(Edition 2023: 14 modules, all 47 elementary threats). It is meant for demos and modelling support. For
audits, always use the current official Kompendium. A full catalog import can be added as another
`ICatalogGateway` implementation.

---

## Repository layout

```
grundschutz/
├── mta.yaml                     MTA descriptor (backend + frontend + approuter → SAP BTP / Cloud Foundry)
├── README.md · uml.md · nafv4.md
├── backend/                     D / vibe.d 0.10.3 service
│   ├── dub.json                 configurations: application, unittest
│   ├── config/default.json      default configuration
│   ├── build/                   build.sh (CF dist), test.sh
│   ├── docs/                    backend notes
│   ├── public/                  static assets of the web GUI
│   ├── tests/                   use-case, persistence and OData tests
│   ├── views/                   Diet templates (layout, index, project, catalog, admin, print)
│   └── source/
│       ├── app.d                entry point (serve | gui | CLI commands)
│       └── uim/myfiori/
│           ├── bootstrap.d      composition root (wires adapters to ports)
│           ├── domain/          entities, types, enumerations, services, exceptions
│           ├── appinfo.d        application name & version
│           ├── application/     usecases, services (catalog, exchange, csv, ids), dtos
│           ├── ports/           usecases, services, repositories, storages, messaging, gateways
│           ├── infrastructure/  configuration, logging (audit), security (XSUAA JWT), clients (catalog), workers (backup)
│           ├── persistence/     repositories, storages (memory / JSON file, transactions, backup), mappers, records
│           └── presentation/    cli (+ Markdown print), http (+ exchange API), odata, web (+ print, admin), gui
├── frontend/                    SAP Fiori 3 / UI5 app (namespace uim.grundschutz)
│   ├── manifest.json · Component.js · index.html
│   ├── view/ controller/ model/ i18n/ (de, en) css/
│   ├── localService/            metadata.xml + mockdata (sap-fe-mockserver)
│   └── test/                    QUnit unit tests, OPA5 integration tests
├── approuter/                   @sap/approuter: xs-app.json, xs-security.json, default-env.json (local only)
└── attributes/ classes/ elements/ entities/ usecases/ values/ package.d
                                 legacy uim.entities model (module models.grundschutz), not used by the new solution
```

---

## Quick start (local)

Prerequisites: a D compiler (`dmd` ≥ 2.105 or `ldc2`), `dub`, OpenSSL 1.1/3.x, and a browser.

```bash
cd backend
dub build                                   # → build/bin/grundschutz
./build/bin/grundschutz serve               # http://127.0.0.1:8080
```

| URL | What |
|-----|------|
| http://127.0.0.1:8080/web | Web GUI (Beer CSS + htmx); first start: `/setup` creates the first administrator |
| http://127.0.0.1:8080/ui/index.html | Fiori 3 app (served from `../frontend`) |
| http://127.0.0.1:8080/odata/v4/grundschutz/$metadata | OData v4 metadata |
| http://127.0.0.1:8080/health | health check |
| http://127.0.0.1:8080/web/admin | import / export, backup & restore |
| http://127.0.0.1:8080/ui/test/testsuite.qunit.html | UI5 unit & OPA tests |

Desktop window (webview):

```bash
./build/bin/grundschutz gui                 # starts the server and opens /web in Chromium/Chrome/Edge --app mode
GS_WEBVIEW=/usr/bin/surf ./build/bin/grundschutz gui   # use any other webview binary
```

Fiori app with UI5 tooling instead (optional):

```bash
cd frontend && npm install
npm start            # proxies /odata to http://localhost:8080
npm run start:mock   # no backend, sap-fe-mockserver with localService/
```

---

## Command line interface

```bash
G=./build/bin/grundschutz
$G project create --name "ISMS Musterstadt" --scope "Rathaus" --owner "ISB" --approach standard
$G project list
$G object create --project 88035da7 --name Fileserver --kind itSystem --c high --rationale "Personaldaten"
$G requirement apply --object 6fe6db68 --module SYS.1.1
$G requirement list --project 88035da7 --status open
$G requirement set d3f66d77 --status yes --responsible "IT-Betrieb"
$G risk create --object 6fe6db68 --threat "G 0.39" --title Ransomware --frequency 3 --impact 4 \
               --treatment reduce --note "Offline-Backups, EDR"
$G report 88035da7
$G catalog modules | catalog requirements NET.1.1 | catalog threats

# print, import / export
$G project print 88035da7 > konzept.md
$G project print 88035da7 --format html --output konzept.html
$G export requirements --format csv --delimiter semicolon --project 88035da7 --output check.csv
$G import requirements --input check.csv --mode upsert --dry-run
$G project export 88035da7 --output isms.json
$G project import --input vorlage.json --new-ids

# backup & restore
$G backup --label vor-audit
$G backup list
$G restore grundschutz-backup-20261118T182135Z-vor-audit.json            # check only
$G restore grundschutz-backup-20261118T182135Z-vor-audit.json --yes      # replace data
$G backup --output /mnt/archive/grundschutz.json
```

- IDs may be abbreviated to any unique prefix.
- `--json` switches to machine-readable output; `--data FILE` and `--memory` select the storage.
- Exit codes: 0 ok, 1 unexpected, 2 usage, 3 not found, 4 business rule violated, failed import or invalid backup.
- The CLI writes the JSON data file directly. Do not use it against the same data file while a
  server is running (including `import` and `restore`), because the server keeps its state in memory
  and would overwrite the CLI's changes. Use the OData API or `/api` instead.

---

## OData v4 API

Base path `/odata/v4/grundschutz/`

| Resource | Operations |
|----------|------------|
| `Projects`, `TargetObjects`, `Requirements`, `Risks` | GET (collection / by key), POST, PATCH/PUT, DELETE |
| `Projects('id')/targetObjects` · `/requirements` · `/risks` | GET, POST (creates in context) |
| `TargetObjects('id')/requirements` · `/risks` | GET, POST |
| `Modules`, `Threats` | read-only catalog |
| `GetProjectReport(projectId='id')` | function → complex type `ProjectReport` |
| `ApplyModule` | action, body `{ "targetObjectId": "…", "moduleCode": "SYS.1.1" }` |
| `…/$count`, `$metadata`, service document | ✔ |

System query options: `$filter` (`eq ne gt ge lt le and or not`, `contains startswith endswith tolower toupper`),
`$orderby`, `$top`, `$skip`, `$count`, `$select`.

- `$batch` is not implemented; the UI5 model uses `groupId: "$direct"`.
- Errors use the OData JSON error format: 400 validation/bad request, 401, 403, 404, 409 conflict.

```bash
curl "http://localhost:8080/odata/v4/grundschutz/Requirements?\$filter=status eq 'open' and level eq 'basic'&\$count=true"
curl -X PATCH -H 'Content-Type: application/json' -d '{"status":"yes"}' \
     "http://localhost:8080/odata/v4/grundschutz/Requirements('…')"
```

---

## Import & export

Each entity can be exported and imported as **CSV** or **JSON**:

| Entity | Export | Import |
|---|---|---|
| `projects`, `targetObjects`, `requirements`, `risks` | ✔ | ✔ |
| `modules`, `threats` (Kompendium catalog) | ✔ | – (read-only) |

- **CSV** follows RFC 4180, is UTF-8 and has a header row with the property names (`ID, projectId, name, …`).
  - Downloads carry a BOM, and `delimiter=semicolon` gives German Excel files.
  - On import, `,`, `;` and TAB are detected automatically, and computed columns (`protectionLevel`, `level`, timestamps …) are ignored.
  - Cells starting with `= + - @` are exported with a leading `'` to prevent formula injection; the import removes it again.
- **JSON** is `{"format":"grundschutz-export","entity":"…","items":[…]}`. A plain array also works for import.
- **Import modes:** `create` treats an existing ID as an error, `upsert` updates existing rows and creates new ones, and `skip` leaves existing rows alone.
  - Rows without an `ID` always get a new ID.
  - Rows with an `ID` keep it, so references between files stay valid.
- **All-or-nothing:** every row goes through the use cases, so all business rules apply. The import runs in **one transaction**: if a single row fails, nothing is saved, and the report lists every failing row. A `dryRun` only checks.
- **Project scope:** with `projectId` (Fiori project page, CLI `--project`), imported target objects are assigned to that project, and requirements and risks must belong to it.
- **Project files** (`grundschutz-project`) contain one project with all its target objects, requirements and risks.
  - Import them unchanged into another system (IDs are kept), or as a **copy with new IDs** (`newIds`), e.g. to start from a template project.
  - The project status (e.g. *archived*) is applied after the content has been imported.

| Channel | How |
|---|---|
| Fiori app | project list: *Import project*, *Export* menu (projects CSV/JSON, complete backup); project page: *Print*, export project, and a download/upload button on every table |
| Web GUI | *Daten & Sicherung* (`/web/admin`): export links, import forms (file upload, mode, dry run); project page: *Drucken*, *Projekt exportieren* |
| CLI | `export`, `import`, `project export`, `project import` |
| HTTP | `/api/export/{entity}`, `/api/import/{entity}`, `/api/projects/{id}/export`, `/api/projects/import` |

## Printing a project

The **security concept dossier** has these parts:

1. cover sheet
2. management summary with key figures
3. structure analysis and protection needs
4. IT-Grundschutz check per target object
5. risk analysis with a 4×4 risk matrix and the treatment of each risk
6. sign-off block for the information security officer (ISB) and the management

- **Web GUI / Fiori:** *Drucken* / *Print* opens `/web/projects/{id}/print`. This is an A4 print layout (`?auto=1` opens the print dialog right away); save it as a PDF from the browser's print dialog.
- **CLI:** `grundschutz project print <id>` writes Markdown; `--format html --output konzept.html` writes the same HTML file as the web view.

## Backup & restore

A **complete backup** is one JSON document:

```json
{ "format": "grundschutz-backup", "formatVersion": 1, "schemaVersion": 1,
  "application": {"name": "grundschutz", "version": "1.1.0"}, "catalogEdition": "…",
  "createdAt": "…", "counts": {"projects": 3, …},
  "checksum": "sha256:…", "data": { "projects": {…}, "targetObjects": {…}, "requirements": {…}, "risks": {…} } }
```

**A restore** goes through these steps:

1. It checks the format and version, and verifies the **checksum**. The checksum is computed over canonical JSON, so a modified or damaged file is rejected.
2. It decodes **every record** into domain objects and checks **all references** (target object → project, requirement and risk → target object), in a scratch store.
3. Only then does it write a **safety backup** of the current state (`…-pre-restore.json`).
4. It replaces the data set in one step. Nothing changes if any check fails.

To confirm a restore:

- web GUI: tick *Bestätigen*;
- CLI: add `--yes`;
- API: leave out `dryRun=true`.

Without confirmation the backup is only checked.

**Server-side backups** are stored in `backupDir` as `grundschutz-backup-<UTC timestamp>Z[-label].json`.

- They are created manually (web GUI, `grundschutz backup`, `POST /api/backups`) or periodically (`backupIntervalMinutes`).
- The newest `backupRetention` files are kept.
- Backup names are validated, so path traversal is not possible.

| Channel | Backup | Restore |
|---|---|---|
| Web GUI `/web/admin` | download, or create on the server | upload a file, or pick a server-side backup |
| Fiori | *Export ▸ Download complete backup* | via *Data & backup* (web GUI) |
| CLI | `backup [--label L]`, `backup --output FILE`, `backup list` | `restore <file\|name> [--dry-run] [--yes]` |
| HTTP | `GET /api/backup`, `POST /api/backups`, `GET /api/backups[/{name}]` | `POST /api/restore`, `POST /api/backups/{name}/restore` (`?dryRun=true`) |

Backup and restore require the **Admin** role, imports **Editor**, and exports **Viewer**.

---

## Configuration

Precedence: `backend/config/default.json` → environment variables → `VCAP_SERVICES` (highest).

| Key (`default.json`) | Environment | Default | Meaning |
|---|---|---|---|
| `host` | `GS_HOST` | `127.0.0.1` | bind address (`0.0.0.0` automatically on Cloud Foundry) |
| `port` | `GS_PORT`, `PORT` | `8080` | listener port |
| `logLevel` | `GS_LOG_LEVEL` | `info` | trace, debug, info, warn, error |
| `storage` | `GS_STORAGE` | `json` | `json` (file) or `memory` |
| `dataFile` | `GS_DATA_FILE` | `data/grundschutz.json` | JSON data file, written atomically |
| `frontendDir` | `GS_FRONTEND_DIR` | `../frontend` | Fiori app served under `/ui` |
| `authEnabled` | `GS_AUTH` | `false` | require XSUAA JWTs (set automatically when an XSUAA is bound) |
| `login` | `GS_LOGIN` | `true` in `default.json` | local user accounts with login page (ignored when XSUAA is active) |
| `usersFile` | `GS_USERS_FILE` | `data/users.json` | local user accounts (file mode 0600, not part of data backups) |
| `sessionMinutes` | `GS_SESSION_MINUTES` | `480` | idle timeout of a login session |
| – | `GS_ADMIN_PASSWORD`, `GS_ADMIN_USER` | – | headless setup: creates this administrator (default `admin`) if no account exists |
| `backupIntervalMinutes` | `GS_BACKUP_INTERVAL` | `0` | periodic complete backups (0 = off) |
| `backupDir` | `GS_BACKUP_DIR` | `data/backups` | backup target |
| `backupRetention` | `GS_BACKUP_RETENTION` | `30` | number of backup files kept (0 = unlimited) |
| `maxUploadMegabytes` | `GS_MAX_UPLOAD_MB` | `32` | maximum request size (imports, restores) |
| – | `GS_CONFIG_DIR` | `config` | configuration directory (CLI: `--config`) |
| – | `GS_WEBVIEW` | – | preferred webview binary for `grundschutz gui` |

---

## Security

- **Local login (default without XSUAA):** user accounts in `data/users.json`, passwords hashed with
  PBKDF2-HMAC-SHA256 (210,000 iterations, random salt, constant-time comparison). Sessions use an
  `HttpOnly`, `SameSite=Strict` cookie (`Secure` behind TLS), are renewed at login (no session
  fixation) and expire after `sessionMinutes` of inactivity. 5 failed logins lock a user name for
  5 minutes. Roles: *Leser* (Viewer), *Bearbeiter* (Viewer + Editor), *Administrator* (all). The last
  active administrator cannot be deleted, demoted or locked. Administrators manage accounts under
  `/web/users`; each user changes their own password under `/web/account`. The session also
  authenticates `/odata`, `/api` and the Fiori app under `/ui`.
- **Authentication with XSUAA:** XSUAA access tokens (RS256) forwarded by the approuter. They are checked against
  the XSUAA `verificationkey` with OpenSSL; expiry and the `xsappname` scope prefix are validated too.
- **Authorization:** `Viewer` for reads, `Editor` for changes, `Admin` for deleting projects. Role
  templates *Auditor*, *SecurityOfficer* and *Administrator* are defined in `approuter/xs-security.json`.
- **CSRF:** the approuter handles CSRF for `/odata` and `/api`. The web GUI forms (including file uploads)
  carry their own per-session token, HMAC-SHA256(secret, user | session id).
- **Cross-site protection in local mode:** without authentication, any web page could otherwise send
  writing requests to `127.0.0.1` (for example a restore). Such requests to `/odata` and `/api` are
  rejected when the browser reports a foreign `Origin` or a cross-site fetch.
- **Import / backup integrity:**
  - imports are transactional;
  - restores are checksum-verified and fully validated before anything changes, with an automatic safety backup;
  - CSV exports are protected against formula injection;
  - backup file names are validated against path traversal.
- **Local mode:** with neither `authEnabled` nor `login` every request runs as the local principal with
  all scopes. Bind to `127.0.0.1` only.
- **Audit trail:** every change produces a domain event that is logged as `[audit] …`.
- **Data protection:** the web GUI loads Beer CSS 5.0.3 and htmx 2.0.4 from jsDelivr, and
  the Fiori app loads UI5 from ui5.sap.com. For offline or air-gapped use, vendor these files into
  `backend/public/` and `frontend/`.

---

## Tests

```bash
cd backend && dub test            # domain, use cases, persistence, OData, CSV, import/export, print, backup/restore (20 modules)
# UI5: start the backend, then open http://127.0.0.1:8080/ui/test/testsuite.qunit.html
```

---

## Deployment to SAP BTP (Cloud Foundry)

```bash
mbt build                          # runs backend/build/build.sh release → backend/dist
cf deploy mta_archives/grundschutz_1.0.0.mtar
```

- `grundschutz-srv` runs on the `binary_buildpack` with `./grundschutz serve` and health check `/health`.
  Build it on a Linux compatible with the CF stack (cflinuxfs4, Ubuntu 22.04).
- `grundschutz-approuter` serves the Fiori app from `resources/` and forwards `/odata`, `/api`, `/web`
  and `/public` to the destination `grundschutz-backend`, with `forwardAuthToken`.
- Use `GET /api/backup` (e.g. from a scheduled job) to copy complete backups off the container.
- The JSON file storage lives on the container's ephemeral disk. For productive use, implement
  `IDocumentStorage` (or the repository ports) against a persistent service such as PostgreSQL. No
  other layer has to change.

Local approuter: fill in `approuter/default-env.json` (never commit it), then run `npm install && npm start`
in `approuter/`.
