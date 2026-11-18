/// Print rendering of a project (Sicherheitskonzept-Dossier) as standalone A4 HTML.
module uim.myfiori.presentation.web.print;

@safe:

import std.algorithm : filter;
import std.array : appender, array;
import uim.myfiori.application.dtos;

/// One chapter per target object.
struct PrintSection {
  TargetObjectDto object;
  RequirementDto[] requirements;
  RiskDto[] risks;
}

/// Groups requirements and risks by target object (keeps the dossier order).
PrintSection[] sectionsOf(ProjectDossierDto d) {
  PrintSection[] result;
  foreach (o; d.targetObjects)
    result ~= PrintSection(o, d.requirements.filter!(r => r.targetObjectId == o.ID).array,
        d.risks.filter!(r => r.targetObjectId == o.ID).array);
  return result;
}

/// Number of risks per matrix cell: [impact - 1][frequency - 1].
int[4][4] riskMatrix(RiskDto[] risks) {
  int[4][4] m;
  foreach (r; risks)
    if (r.impact >= 1 && r.impact <= 4 && r.frequency >= 1 && r.frequency <= 4)
      m[r.impact - 1][r.frequency - 1]++;
  return m;
}

/// Renders the complete print view. `autoPrint` opens the browser print dialog on load.
string renderProjectHtml(ProjectDossierDto dossier, bool autoPrint = false) @trusted {
  import diet.html : compileHTMLDietFile;
  auto sections = sectionsOf(dossier);
  auto matrix = riskMatrix(dossier.risks);
  auto dst = appender!string;
  dst.compileHTMLDietFile!("print.dt", dossier, sections, matrix, autoPrint);
  return dst.data;
}
