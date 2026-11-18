/// View helpers for the Diet templates (German labels, badge colours, formatting).
module uim.myfiori.presentation.web.helpers;

@safe:

import std.format : format;

/// German label for an enum member name transported in DTOs.
string de(string value) pure nothrow {
  switch (value) {
    // protection levels
    case "normal": return "normal";
    case "high": return "hoch";
    case "veryHigh": return "sehr hoch";
    // approaches
    case "basic": return "Basis";
    case "standard": return "Standard";
    case "core": return "Kern";
    case "elevated": return "erhöht";
    // project status
    case "planned": return "geplant";
    case "inProgress": return "in Bearbeitung";
    case "completed": return "abgeschlossen";
    case "archived": return "archiviert";
    // target object kinds
    case "businessProcess": return "Geschäftsprozess";
    case "application": return "Anwendung";
    case "itSystem": return "IT-System";
    case "icsSystem": return "ICS-System";
    case "iotSystem": return "IoT-System";
    case "room": return "Raum";
    case "building": return "Gebäude";
    case "network": return "Netz";
    case "communicationLink": return "Kommunikationsverbindung";
    // implementation status
    case "open": return "offen";
    case "yes": return "ja";
    case "partially": return "teilweise";
    case "no": return "nein";
    case "dispensable": return "entbehrlich";
    // risk levels / treatment
    case "low": return "gering";
    case "medium": return "mittel";
    case "avoid": return "vermeiden";
    case "reduce": return "reduzieren";
    case "transfer": return "übertragen";
    case "accept": return "akzeptieren";
    default: return value;
  }
}

/// daisyUI badge class for a status/level value.
string badge(string value) pure nothrow {
  switch (value) {
    case "yes", "low", "normal", "completed", "dispensable": return "badge badge-success";
    case "partially", "medium", "high", "inProgress": return "badge badge-warning";
    case "no", "veryHigh": return "badge badge-error";
    case "archived": return "badge badge-ghost";
    default: return "badge badge-info badge-outline";
  }
}

string percent(double v) { return format("%.0f %%", v); }

string frequencyLabel(int v) pure nothrow {
  switch (v) { case 1: return "selten"; case 2: return "mittel"; case 3: return "häufig"; case 4: return "sehr häufig"; default: return "?"; }
}

string impactLabel(int v) pure nothrow {
  switch (v) { case 1: return "vernachlässigbar"; case 2: return "begrenzt"; case 3: return "beträchtlich"; case 4: return "existenzbedrohend"; default: return "?"; }
}

/// Short display form of a UUID.
string shortId(string id) pure nothrow { return id.length > 8 ? id[0 .. 8] : id; }

immutable string[] protectionLevels = ["normal", "high", "veryHigh"];
immutable string[] approaches = ["basic", "standard", "core"];
immutable string[] projectStatuses = ["planned", "inProgress", "completed", "archived"];
immutable string[] objectKinds = ["businessProcess", "application", "itSystem", "icsSystem", "iotSystem",
  "room", "building", "network", "communicationLink"];
immutable string[] implementationStatuses = ["open", "yes", "partially", "no", "dispensable"];
immutable string[] treatments = ["open", "avoid", "reduce", "transfer", "accept"];

/// Labels for the basic values (Grundwerte).
string ciaLabel(string field) pure nothrow {
  return field == "confidentiality" ? "Vertraulichkeit" : field == "integrity" ? "Integrität" : "Verfügbarkeit";
}

/// ditto, abbreviated (V/I/A).
string ciaShort(string field) pure nothrow {
  return field == "confidentiality" ? "V" : field == "integrity" ? "I" : "A";
}
