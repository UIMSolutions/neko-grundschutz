/// Driven ports for external reference data (IT-Grundschutz-Kompendium).
module uim.myfiori.ports.gateways;

@safe:

struct CatalogRequirement {
  string code;
  string title;
  string level;   // basic | standard | elevated
}

struct CatalogModule {
  string code;
  string title;
  string layer;   // ISMS, ORP, CON, OPS, DER, APP, SYS, IND, NET, INF
  string description;
  CatalogRequirement[] requirements;
}

struct CatalogThreat {
  string code;
  string title;
}

/// Source of the Kompendium (built-in excerpt, file import or remote service).
interface ICatalogGateway {
  CatalogModule[] modules();
  CatalogThreat[] threats();
  string edition();
}
