/// Value objects of the Grundschutz domain.
module uim.myfiori.domain.types;

@safe:

import std.algorithm : max;
import std.regex : ctRegex, matchFirst;
import std.string : strip;
import std.conv : to;
import uim.myfiori.domain.enumerations;
import uim.myfiori.domain.exceptions;

/// Identity of an entity (UUID string).
alias EntityId = string;

/// Schutzbedarf for the three basic values Vertraulichkeit, Integrität, Verfügbarkeit.
struct ProtectionNeed {
  ProtectionLevel confidentiality = ProtectionLevel.normal;
  ProtectionLevel integrity = ProtectionLevel.normal;
  ProtectionLevel availability = ProtectionLevel.normal;

  /// Highest level over all three basic values.
  ProtectionLevel overall() const pure nothrow @nogc {
    return max(confidentiality, integrity, availability);
  }

  /// Maximumprinzip: component-wise maximum of two protection needs.
  ProtectionNeed combine(in ProtectionNeed other) const pure nothrow @nogc {
    return ProtectionNeed(max(confidentiality, other.confidentiality),
        max(integrity, other.integrity), max(availability, other.availability));
  }

  /// A protection need above "normal" requires an additional risk analysis (BSI 200-3).
  bool requiresRiskAnalysis() const pure nothrow @nogc {
    return overall > ProtectionLevel.normal;
  }
}

/// Code of an IT-Grundschutz module (Baustein), e.g. "SYS.1.1".
struct ModuleCode {
  string value;

  this(string raw) {
    auto v = raw.strip;
    if (!matchFirst(v, ctRegex!(`^[A-Z]{3,4}(\.[0-9]+){1,3}$`)))
      throw new ValidationException("Invalid module code '" ~ raw ~ "' (expected e.g. SYS.1.1)");
    value = v;
  }

  string toString() const pure nothrow @nogc { return value; }
}

/// Code of a requirement (Anforderung), e.g. "SYS.1.1.A3".
struct RequirementCode {
  string value;

  this(string raw) {
    auto v = raw.strip;
    if (!matchFirst(v, ctRegex!(`^[A-Z]{3,4}(\.[0-9]+){1,3}\.A[0-9]+$`)))
      throw new ValidationException("Invalid requirement code '" ~ raw ~ "' (expected e.g. SYS.1.1.A3)");
    value = v;
  }

  /// Module (Baustein) this requirement belongs to.
  ModuleCode moduleCode() const {
    import std.string : lastIndexOf;
    return ModuleCode(value[0 .. value.lastIndexOf(".A")]);
  }

  string toString() const pure nothrow @nogc { return value; }
}

/// Code of an elementary threat (elementare Gefährdung), e.g. "G 0.18".
struct ThreatCode {
  string value;

  this(string raw) {
    auto v = raw.strip;
    if (!matchFirst(v, ctRegex!(`^G 0\.[0-9]{1,2}$`)))
      throw new ValidationException("Invalid threat code '" ~ raw ~ "' (expected e.g. G 0.18)");
    value = v;
  }

  string toString() const pure nothrow @nogc { return value; }
}

/// Validates and normalises a mandatory text attribute.
string requireText(string value, string field, size_t maxLength = 255) {
  auto v = value.strip;
  if (v.length == 0)
    throw new ValidationException(field ~ " must not be empty");
  if (v.length > maxLength)
    throw new ValidationException(field ~ " is too long (max. " ~ maxLength.to!string ~ ")");
  return v;
}

unittest {
  auto a = ProtectionNeed(ProtectionLevel.high, ProtectionLevel.normal, ProtectionLevel.normal);
  auto b = ProtectionNeed(ProtectionLevel.normal, ProtectionLevel.normal, ProtectionLevel.veryHigh);
  auto c = a.combine(b);
  assert(c.confidentiality == ProtectionLevel.high);
  assert(c.availability == ProtectionLevel.veryHigh);
  assert(c.overall == ProtectionLevel.veryHigh);
  assert(c.requiresRiskAnalysis);
  assert(!ProtectionNeed.init.requiresRiskAnalysis);

  assert(RequirementCode("SYS.1.1.A3").moduleCode.value == "SYS.1.1");
  assert(ModuleCode("OPS.1.1.2").value == "OPS.1.1.2");
  assert(ThreatCode("G 0.18").value == "G 0.18");
  bool thrown;
  try ModuleCode("sys"); catch (ValidationException) thrown = true;
  assert(thrown);
}
