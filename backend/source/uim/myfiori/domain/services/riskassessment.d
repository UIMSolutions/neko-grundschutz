/// Risk matrix of BSI-Standard 200-3 (Tabelle 6, Matrix zur Einstufung von Risiken).
module uim.myfiori.domain.services.riskassessment;

@safe:

import uim.myfiori.domain.enumerations;

/// rows: impact (negligible..existential), columns: frequency (rare..veryOften)
private immutable RiskLevel[4][4] matrix = [
  [RiskLevel.low,    RiskLevel.low,    RiskLevel.low,      RiskLevel.low],
  [RiskLevel.low,    RiskLevel.low,    RiskLevel.medium,   RiskLevel.high],
  [RiskLevel.low,    RiskLevel.medium, RiskLevel.high,     RiskLevel.veryHigh],
  [RiskLevel.low,    RiskLevel.high,   RiskLevel.veryHigh, RiskLevel.veryHigh],
];

/// Classifies a risk from frequency and impact.
RiskLevel assessRisk(Frequency frequency, Impact impact) pure nothrow @nogc {
  return matrix[cast(int) impact - 1][cast(int) frequency - 1];
}

unittest {
  assert(assessRisk(Frequency.rare, Impact.existential) == RiskLevel.low);
  assert(assessRisk(Frequency.veryOften, Impact.existential) == RiskLevel.veryHigh);
  assert(assessRisk(Frequency.medium, Impact.considerable) == RiskLevel.medium);
  assert(assessRisk(Frequency.veryOften, Impact.limited) == RiskLevel.high);
}
