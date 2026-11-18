/// Application service exposing the Kompendium catalog to the presentation layer.
module uim.myfiori.application.services.catalogservice;

@safe:

import std.algorithm : map, sort;
import std.array : array;
import uim.myfiori.application.dtos;
import uim.myfiori.domain.exceptions;
import uim.myfiori.ports.gateways;
import uim.myfiori.ports.services;

class DCatalogService : ICatalogService {
  private ICatalogGateway _gateway;

  this(ICatalogGateway gateway) { _gateway = gateway; }

  ModuleDto[] modules() {
    return _gateway.modules.map!(m => ModuleDto(m.code, m.title, m.layer, m.description,
        cast(int) m.requirements.length)).array;
  }

  ModuleDto findModule(string code) {
    foreach (m; modules) if (m.code == code) return m;
    throw new EntityNotFoundException("Module", code);
  }

  CatalogRequirementDto[] requirementsOf(string moduleCode) {
    foreach (m; _gateway.modules)
      if (m.code == moduleCode)
        return m.requirements.map!(r => CatalogRequirementDto(r.code, m.code, r.title, r.level)).array;
    throw new EntityNotFoundException("Module", moduleCode);
  }

  string edition() { return _gateway.edition; }

  ThreatDto[] threats() {
    return _gateway.threats.map!(t => ThreatDto(t.code, t.title)).array;
  }
}
