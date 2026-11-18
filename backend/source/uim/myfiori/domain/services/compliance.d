/// Evaluation of the IT-Grundschutz-Check (Soll-Ist-Vergleich).
module uim.myfiori.domain.services.compliance;

@safe:

import uim.myfiori.domain.entities;
import uim.myfiori.domain.enumerations;

struct ComplianceSummary {
  size_t total;
  size_t fulfilled;     // ja
  size_t partially;     // teilweise
  size_t notFulfilled;  // nein
  size_t open;          // nicht geprüft
  size_t dispensable;   // entbehrlich
  size_t basicOpen;     // offene/nicht erfüllte Basis-Anforderungen

  /// Erfüllungsgrad in percent (fulfilled + dispensable, partially counts half).
  double degree() const pure nothrow @nogc {
    if (total == 0) return 0;
    return (fulfilled + dispensable + partially * 0.5) * 100.0 / total;
  }

  /// All Basis-Anforderungen fulfilled — precondition for Basis-Absicherung.
  bool basicProtectionAchieved() const pure nothrow @nogc { return total > 0 && basicOpen == 0; }
}

/// Requirement levels that are relevant for the chosen approach.
bool isRelevant(RequirementLevel level, SecurityApproach approach) pure nothrow @nogc {
  final switch (approach) {
    case SecurityApproach.basic: return level == RequirementLevel.basic;
    case SecurityApproach.standard: return level != RequirementLevel.elevated;
    case SecurityApproach.core: return true;
  }
}

/// Computes the compliance summary over all requirements relevant for the approach.
ComplianceSummary evaluateCompliance(const(DRequirement)[] requirements, SecurityApproach approach) {
  ComplianceSummary s;
  foreach (r; requirements) {
    if (!isRelevant(r.level, approach)) continue;
    s.total++;
    final switch (r.status) {
      case ImplementationStatus.yes: s.fulfilled++; break;
      case ImplementationStatus.partially: s.partially++; break;
      case ImplementationStatus.no: s.notFulfilled++; break;
      case ImplementationStatus.open: s.open++; break;
      case ImplementationStatus.dispensable: s.dispensable++; break;
    }
    if (r.level == RequirementLevel.basic && !r.isFulfilled)
      s.basicOpen++;
  }
  return s;
}
