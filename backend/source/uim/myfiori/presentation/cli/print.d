/// Markdown rendering of a project dossier (CLI `project print`).
module uim.myfiori.presentation.cli.print;

@safe:

import std.array : appender, join, replace;
import std.conv : to;
import std.format : format;
import uim.myfiori.application.dtos;
import uim.myfiori.presentation.web.helpers : de, frequencyLabel, impactLabel, percent;
import uim.myfiori.presentation.web.print : sectionsOf;

private string cell(string s) { return s.replace("|", "\\|").replace("\n", " "); }

string renderProjectMarkdown(ProjectDossierDto d) {
  auto r = d.report;
  auto p = r.project;
  auto w = appender!string;
  void ln(string s = "") { w ~= s; w ~= "\n"; }

  ln("# Sicherheitskonzept: " ~ p.name);
  ln();
  ln("| | |");
  ln("|---|---|");
  ln("| Informationsverbund | " ~ cell(p.scope_) ~ " |");
  ln("| Beschreibung | " ~ cell(p.description) ~ " |");
  ln("| Verantwortlich (ISB) | " ~ cell(p.owner) ~ " |");
  ln("| Vorgehensweise | " ~ de(p.approach) ~ "-Absicherung |");
  ln("| Status | " ~ de(p.status) ~ " |");
  ln("| Erstellt am | " ~ d.generatedAt ~ " |");
  ln("| Referenzkatalog | " ~ cell(d.catalogEdition) ~ " |");
  ln();

  ln("## 1 Management-Zusammenfassung");
  ln();
  ln(format("- **Erfüllungsgrad:** %s (%d von %d relevanten Anforderungen erfüllt)", percent(r.complianceDegree),
      r.requirementsFulfilled, r.requirementsTotal));
  ln(format("- **Schutzbedarf:** V %s · I %s · A %s → **%s**", de(r.confidentiality), de(r.integrity),
      de(r.availability), de(r.protectionLevel)));
  ln("- **Basis-Absicherung:** " ~ (r.basicProtectionAchieved ? "erreicht"
      : r.basicRequirementsOpen.to!string ~ " Basis-Anforderungen offen"));
  ln(format("- **Risiken:** %d gesamt – %d gering, %d mittel, %d hoch, %d sehr hoch; %d unbehandelt",
      r.risksTotal, r.risksLow, r.risksMedium, r.risksHigh, r.risksVeryHigh, r.risksUntreated));
  ln("- **Risikoanalyse erforderlich für:** " ~ (r.objectsRequiringRiskAnalysis.length ? r.objectsRequiringRiskAnalysis.join(", ") : "–"));
  ln();

  ln("## 2 Strukturanalyse und Schutzbedarf");
  ln();
  ln("| Zielobjekt | Typ | V | I | A | Max. | Begründung |");
  ln("|---|---|---|---|---|---|---|");
  foreach (o; d.targetObjects)
    ln(format("| %s | %s | %s | %s | %s | %s | %s |", cell(o.name), de(o.kind), de(o.confidentiality),
        de(o.integrity), de(o.availability), de(o.protectionLevel), cell(o.protectionRationale)));
  ln();

  ln("## 3 IT-Grundschutz-Check");
  foreach (s; sectionsOf(d)) {
    if (s.requirements.length == 0) continue;
    ln();
    ln("### " ~ s.object.name ~ " (" ~ de(s.object.kind) ~ ")");
    ln();
    ln("| Anforderung | Titel | Art | Umsetzung | Verantwortlich | Termin | Begründung |");
    ln("|---|---|---|---|---|---|---|");
    foreach (q; s.requirements)
      ln(format("| %s | %s | %s | %s | %s | %s | %s |", q.code, cell(q.title), de(q.level), de(q.status),
          cell(q.responsible), q.dueDate, cell(q.note)));
  }
  ln();

  ln("## 4 Risikoanalyse");
  ln();
  if (d.risks.length == 0) ln("Keine Risiken erfasst.");
  else {
    ln("| Zielobjekt | Gefährdung | Titel | Häufigkeit | Schadenshöhe | Risiko | Behandlung | Begründung |");
    ln("|---|---|---|---|---|---|---|---|");
    foreach (s; sectionsOf(d))
      foreach (k; s.risks)
        ln(format("| %s | %s | %s | %s | %s | %s | %s | %s |", cell(s.object.name), k.threatCode, cell(k.title),
            frequencyLabel(k.frequency), impactLabel(k.impact), de(k.level), de(k.treatment), cell(k.treatmentNote)));
  }
  ln();
  ln("## 5 Freigabe");
  ln();
  ln("| Rolle | Name | Datum | Unterschrift |");
  ln("|---|---|---|---|");
  ln("| Informationssicherheitsbeauftragte/r | | | |");
  ln("| Leitung der Institution | | | |");
  return w.data;
}
