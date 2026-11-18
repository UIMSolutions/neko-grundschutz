
I've built the BSI IT-Grundschutz solution with `/fiori-vibed-architecture`. It has an OData v4 API, a Fiori 3 app, a daisyUI web GUI that also opens as a desktop webview window (`grundschutz gui`), and a CLI. `README.md` is rewritten, and `uml.md` and `nafv4.md` are new. Everything builds against vibe.d 0.10.3, and the checks below pass.

The old `models.grundschutz` model in the root folders is untouched and not used by the new code.

**What it covers (BSI-Standards 200-2 and 200-3)**

- **Projects:** scope, approach (Basis-, Standard- or Kern-Absicherung), and a status lifecycle. Archived projects are read-only.
- **Target objects:** a protection need for confidentiality, integrity and availability, combined across objects with the maximum principle (*Maximumprinzip*).
- **Modules:** applying one (e.g. `SYS.1.1`) to a target object creates all its requirements. Applying it twice adds nothing.
- **IT-Grundschutz check:** a status per requirement (open / yes / partially / no / dispensable), with a responsible person, due date and justification.
- **Risk analysis:** the 47 elementary threats, the 4×4 risk matrix and a treatment decision per risk.
- **Report:** degree of fulfilment, open basic requirements, and the risk breakdown.
- **Rules the backend enforces:**
  - raising a protection need, or setting a requirement to "no" or "dispensable", needs a justification;
  - basic requirements can never be dispensable;
  - accepting a high risk needs a justification.

**How the pieces fit**

- **Backend:** under `backend/source/uim/myfiori/`, in the skill's layer layout. All four interfaces call the same use cases, so the rules above live in one place.
- **Storage:** a JSON data file, written so a crash can't leave it half-written. A periodic backup is available but off by default.
- **Login on SAP BTP:** the backend checks the XSUAA tokens the approuter forwards. Reading needs the Viewer role, changing needs Editor, and deleting a project needs Admin.
- **Deployment:** `mta.yaml` builds the backend, Fiori app and approuter together.

**Checks**

- **Backend unit tests:** all pass (13 modules), covering business rules, persistence round-trip, OData parsing and the CLI.
- **CLI:** every command run against a real data file, including error exit codes.
- **OData:** tested with curl, including filters, counts, the report function, the module action and error responses.
- **Web GUI:** every page renders; a form post without the CSRF token is rejected.
- **Fiori app:** checked in a headless browser with screenshots. The UI5 unit tests (16 assertions) and the integration test pass.
- **Login:** tested with real signed tokens. Missing, expired or forged tokens get 401; a missing role or another app's roles get 403.

**Bugs found and fixed during testing**

- **Data corruption on load:** opening a project in the Fiori app silently overwrote stored values. A target object got saved as "business process" with protection need "normal". The drop-downs no longer write anything on load.
- **Blank project page:** a duplicate control ID stopped the Fiori project page from rendering.

**Limitations**

- **Partial catalog:** the built-in Kompendium is an excerpt of 14 modules. Some requirement titles are abridged, so it is not fit for audits as is; the README says this.
- **No `$batch`:** the OData service doesn't support it, so the Fiori app sends each request directly instead of batching.
- **CLI and server can't share a data file:** don't run them on the same file at once. The running server would overwrite the CLI's changes.
- **Storage on SAP BTP:** the data file sits on temporary disk and can be lost. Productive use needs a database such as PostgreSQL behind the existing storage interface.
- **Libraries from CDNs:** both GUIs load UI5 and daisyUI from public CDNs. For offline or privacy-sensitive use, those files would need to be bundled locally.

To try it: `cd backend && dub build && ./build/bin/grundschutz serve`, then open http://127.0.0.1:8080/web or `/ui/index.html`.
