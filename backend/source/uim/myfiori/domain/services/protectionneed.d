/// Schutzbedarfsfeststellung across target objects (Maximumprinzip).
module uim.myfiori.domain.services.protectionneed;

@safe:

import uim.myfiori.domain.entities;
import uim.myfiori.domain.types;

/**
 * Aggregated protection need of an Informationsverbund: the component-wise
 * maximum of all target objects (Maximumprinzip, BSI-Standard 200-2 Kap. 8.2).
 */
ProtectionNeed aggregateProtectionNeed(const(DTargetObject)[] objects) {
  ProtectionNeed result;
  foreach (o; objects)
    result = result.combine(o.protectionNeed);
  return result;
}

/// Target objects that need an additional risk analysis (protection need above normal).
const(DTargetObject)[] objectsRequiringRiskAnalysis(const(DTargetObject)[] objects) {
  import std.algorithm : filter;
  import std.array : array;
  return objects.filter!(o => o.protectionNeed.requiresRiskAnalysis).array;
}
