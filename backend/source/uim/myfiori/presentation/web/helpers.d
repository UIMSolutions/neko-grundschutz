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

/// Beer CSS chip classes (with status colour from app.css) for a status/level value.
string badge(string value) pure nothrow {
  switch (value) {
    case "yes", "low", "normal", "completed", "dispensable": return "chip small tag-ok";
    case "partially", "medium", "high", "inProgress": return "chip small tag-warn";
    case "no", "veryHigh": return "chip small tag-bad";
    case "archived": return "chip small tag-muted";
    default: return "chip small tag-info";
  }
}

/// Neutral chip.
enum chip = "chip small tag-muted";

/// "active" for the current navigation entry / tab.
string activeIf(bool cond) pure nothrow { return cond ? "active" : ""; }

immutable string[] userRoles = ["viewer", "editor", "admin"];

string roleLabel(string role) pure nothrow {
  switch (role) {
    case "viewer": return "Leser";
    case "editor": return "Bearbeiter";
    case "admin": return "Administrator";
    default: return role;
  }
}

/// "2026-11-18T09:30:12.123Z" → "18.11.2026 09:30" (UTC); "–" if empty.
string dateTime(string iso) pure nothrow {
  if (iso.length < 16) return "–";
  return iso[8 .. 10] ~ "." ~ iso[5 .. 7] ~ "." ~ iso[0 .. 4] ~ " " ~ iso[11 .. 16];
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
