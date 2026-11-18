/**
 * Business enumerations of the BSI IT-Grundschutz methodology
 * (BSI-Standards 200-2 and 200-3).
 */
module uim.myfiori.domain.enumerations;

@safe:

import std.conv : to, ConvException;
import std.traits : EnumMembers;
import uim.myfiori.domain.exceptions;

/// Schutzbedarfskategorie (BSI-Standard 200-2, Kap. 8.2).
enum ProtectionLevel { normal, high, veryHigh }

/// Vorgehensweise / Absicherungsvariante (BSI-Standard 200-2).
enum SecurityApproach { basic, standard, core }

/// Lifecycle of a Grundschutz project (Sicherheitskonzeption).
enum ProjectStatus { planned, inProgress, completed, archived }

/// Zielobjekt types used for modelling (Modellierung).
enum TargetObjectKind {
  businessProcess, application, itSystem, icsSystem, iotSystem,
  room, building, network, communicationLink
}

/// Anforderungsart of an IT-Grundschutz-Kompendium requirement.
enum RequirementLevel { basic, standard, elevated }

/// Umsetzungsstatus as used in the IT-Grundschutz-Check.
enum ImplementationStatus { open, yes, partially, no, dispensable }

/// Eintrittshäufigkeit (BSI-Standard 200-3, Tab. 4).
enum Frequency { rare = 1, medium = 2, often = 3, veryOften = 4 }

/// Schadenshöhe (BSI-Standard 200-3, Tab. 5).
enum Impact { negligible = 1, limited = 2, considerable = 3, existential = 4 }

/// Risikokategorie (BSI-Standard 200-3, Tab. 6).
enum RiskLevel { low, medium, high, veryHigh }

/// Risikobehandlungsoption (BSI-Standard 200-3, Kap. 6).
enum RiskTreatment { open, avoid, reduce, transfer, accept }

/// Parses an enum member by its (case-insensitive) name.
E parseEnum(E)(string value) if (is(E == enum)) {
  import std.uni : sicmp;
  foreach (member; [EnumMembers!E])
    if (sicmp(member.to!string, value) == 0)
      return member;
  throw new ValidationException("Invalid value '" ~ value ~ "' for " ~ E.stringof
      ~ "; allowed: " ~ enumNames!E);
}

/// Comma separated list of all member names (for help texts and errors).
string enumNames(E)() if (is(E == enum)) {
  import std.algorithm : map;
  import std.array : join;
  return [EnumMembers!E].map!(m => m.to!string).join(", ");
}

/// German display label (used by web GUI and CLI reports).
string label(ProtectionLevel v) {
  final switch (v) {
    case ProtectionLevel.normal: return "normal";
    case ProtectionLevel.high: return "hoch";
    case ProtectionLevel.veryHigh: return "sehr hoch";
  }
}

/// ditto
string label(ImplementationStatus v) {
  final switch (v) {
    case ImplementationStatus.open: return "offen";
    case ImplementationStatus.yes: return "ja";
    case ImplementationStatus.partially: return "teilweise";
    case ImplementationStatus.no: return "nein";
    case ImplementationStatus.dispensable: return "entbehrlich";
  }
}

/// ditto
string label(RiskLevel v) {
  final switch (v) {
    case RiskLevel.low: return "gering";
    case RiskLevel.medium: return "mittel";
    case RiskLevel.high: return "hoch";
    case RiskLevel.veryHigh: return "sehr hoch";
  }
}

/// ditto
string label(SecurityApproach v) {
  final switch (v) {
    case SecurityApproach.basic: return "Basis-Absicherung";
    case SecurityApproach.standard: return "Standard-Absicherung";
    case SecurityApproach.core: return "Kern-Absicherung";
  }
}

unittest {
  assert(parseEnum!ProtectionLevel("VERYHIGH") == ProtectionLevel.veryHigh);
  assert(parseEnum!Frequency("often") == Frequency.often);
  bool thrown;
  try parseEnum!ProtectionLevel("extreme"); catch (ValidationException) thrown = true;
  assert(thrown);
}
