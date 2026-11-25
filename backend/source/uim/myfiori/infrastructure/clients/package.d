/**
 * Built-in excerpt of the BSI IT-Grundschutz-Kompendium (Edition 2023).
 *
 * The excerpt is meant for demonstration and modelling support; titles are abridged.
 * For audits always use the current official Kompendium (https://www.bsi.bund.de).
 * A complete catalog can be plugged in by another ICatalogGateway implementation
 * (e.g. an XML/JSON import client).
 */
module uim.myfiori.infrastructure.clients;

@safe:

import std.string : lineSplitter, split, strip;
import uim.myfiori.ports.gateways;

class DBuiltinCatalogClient : ICatalogGateway {
  private CatalogModule[] _modules;
  private CatalogThreat[] _threats;

  this() {
    _modules = parseModules(modulesText);
    foreach (line; threatsText.lineSplitter) {
      auto l = line.strip;
      if (l.length == 0) continue;
      auto f = l.split("|");
      _threats ~= CatalogThreat(f[0], f[1]);
    }
  }

  CatalogModule[] modules() { return _modules; }
  CatalogThreat[] threats() { return _threats; }
  string edition() { return "IT-Grundschutz-Kompendium Edition 2023 (Auszug)"; }

  /// Format: "# CODE|Title|Layer|Description" followed by "CODE.An|Title|level" lines.
  private static CatalogModule[] parseModules(string text) {
    CatalogModule[] result;
    foreach (line; text.lineSplitter) {
      auto l = line.strip;
      if (l.length == 0) continue;
      if (l[0] == '#') {
        auto f = l[1 .. $].strip.split("|");
        result ~= CatalogModule(f[0], f[1], f[2], f[3]);
      } else {
        auto f = l.split("|");
        result[$ - 1].requirements ~= CatalogRequirement(f[0], f[1], f[2]);
      }
    }
    return result;
  }
}

private enum modulesText = `
# ISMS.1|Sicherheitsmanagement|ISMS|Aufbau und Betrieb eines Managementsystems für Informationssicherheit
ISMS.1.A1|Übernahme der Gesamtverantwortung für Informationssicherheit durch die Leitung|basic
ISMS.1.A2|Festlegung der Sicherheitsziele und -strategie|basic
ISMS.1.A3|Erstellung einer Leitlinie zur Informationssicherheit|basic
ISMS.1.A4|Benennung eines oder einer Informationssicherheitsbeauftragten|basic
ISMS.1.A6|Aufbau einer geeigneten Organisationsstruktur für Informationssicherheit|basic
ISMS.1.A7|Festlegung von Sicherheitsmaßnahmen|basic
ISMS.1.A8|Integration der Mitarbeitenden in den Sicherheitsprozess|basic
ISMS.1.A9|Integration der Informationssicherheit in organisationsweite Abläufe und Prozesse|basic
ISMS.1.A10|Erstellung eines Sicherheitskonzepts|standard
ISMS.1.A11|Aufrechterhaltung der Informationssicherheit|standard
ISMS.1.A12|Management-Berichte zur Informationssicherheit|standard
ISMS.1.A13|Dokumentation des Sicherheitsprozesses|standard
ISMS.1.A15|Wirtschaftlicher Einsatz von Ressourcen für Informationssicherheit|standard
# ORP.4|Identitäts- und Berechtigungsmanagement|ORP|Regelungen für Kennungen, Berechtigungen und Authentisierung
ORP.4.A1|Regelung für die Einrichtung und Löschung von Benutzenden und Benutzendengruppen|basic
ORP.4.A2|Einrichtung, Änderung und Entzug von Berechtigungen|basic
ORP.4.A3|Dokumentation der Benutzendenkennungen und Rechteprofile|basic
ORP.4.A4|Aufgabenverteilung und Funktionstrennung|basic
ORP.4.A5|Vergabe von Zutrittsberechtigungen|basic
ORP.4.A6|Vergabe von Zugangsberechtigungen|basic
ORP.4.A7|Vergabe von Zugriffsrechten|basic
ORP.4.A8|Regelung des Passwortgebrauchs|basic
ORP.4.A9|Identifikation und Authentisierung|basic
ORP.4.A13|Geeignete Auswahl von Authentisierungsmechanismen|standard
ORP.4.A16|Richtlinien für die Zugriffs- und Zugangskontrolle|standard
# CON.3|Datensicherungskonzept|CON|Konzeption von Datensicherungen zum Schutz vor Datenverlust
CON.3.A1|Erhebung der Einflussfaktoren für Datensicherungen|basic
CON.3.A2|Festlegung der Verfahrensweise für die Datensicherung|basic
CON.3.A4|Erstellung von Datensicherungsplänen|basic
CON.3.A5|Regelmäßige Datensicherung|basic
CON.3.A6|Entwicklung eines Datensicherungskonzepts|standard
CON.3.A7|Beschaffung eines geeigneten Datensicherungssystems|standard
CON.3.A11|Geeignete Aufbewahrung der Backup-Datenträger|standard
CON.3.A14|Schutz von Datensicherungen|elevated
# OPS.1.1.3|Patch- und Änderungsmanagement|OPS|Geregelte Einspielung von Updates und Änderungen
OPS.1.1.3.A1|Konzept für das Patch- und Änderungsmanagement|basic
OPS.1.1.3.A2|Festlegung der Verantwortlichkeiten|basic
OPS.1.1.3.A3|Konfiguration von Autoupdate-Mechanismen|basic
OPS.1.1.3.A15|Regelmäßige Aktualisierung von IT-Systemen und Software|basic
OPS.1.1.3.A5|Umgang mit Änderungsanforderungen|standard
OPS.1.1.3.A8|Sicherer Download von Patches|standard
# OPS.1.1.4|Schutz vor Schadprogrammen|OPS|Einsatz und Betrieb von Schutzmechanismen gegen Schadsoftware
OPS.1.1.4.A1|Erstellung eines Konzepts für den Schutz vor Schadprogrammen|basic
OPS.1.1.4.A3|Auswahl eines Virenschutzprogrammes|basic
OPS.1.1.4.A5|Betrieb und Konfiguration von Virenschutzprogrammen|basic
OPS.1.1.4.A6|Regelmäßige Aktualisierung der eingesetzten Virenschutzprogramme und Signaturen|basic
OPS.1.1.4.A9|Meldung von Infektionen mit Schadprogrammen|standard
# DER.2.1|Behandlung von Sicherheitsvorfällen|DER|Erkennen, Bewerten und Behandeln von Sicherheitsvorfällen
DER.2.1.A1|Definition eines Sicherheitsvorfalls|basic
DER.2.1.A2|Erstellung einer Richtlinie zur Behandlung von Sicherheitsvorfällen|basic
DER.2.1.A3|Festlegung von Verantwortlichkeiten und Ansprechpersonen bei Sicherheitsvorfällen|basic
DER.2.1.A4|Benachrichtigung betroffener Stellen bei Sicherheitsvorfällen|basic
DER.2.1.A5|Behebung von Sicherheitsvorfällen|basic
DER.2.1.A6|Wiederherstellung der Betriebsumgebung nach Sicherheitsvorfällen|basic
DER.2.1.A7|Etablierung einer Vorgehensweise zur Behandlung von Sicherheitsvorfällen|standard
# APP.1.1|Office-Produkte|APP|Sichere Nutzung von Office-Anwendungen
APP.1.1.A2|Einschränken von Aktiven Inhalten|basic
APP.1.1.A3|Öffnen von Dokumenten aus externen Quellen|basic
APP.1.1.A6|Testen neuer Versionen von Office-Produkten|standard
APP.1.1.A15|Einsatz von Verschlüsselung und Digitalen Signaturen|standard
# SYS.1.1|Allgemeiner Server|SYS|Grundlegende Absicherung von Servern unabhängig vom Betriebssystem
SYS.1.1.A2|Benutzendenauthentisierung an Servern|basic
SYS.1.1.A3|Restriktive Rechtevergabe|basic
SYS.1.1.A4|Rollentrennung|basic
SYS.1.1.A5|Schutz der Administrationsschnittstellen|basic
SYS.1.1.A6|Deaktivierung nicht benötigter Dienste|basic
SYS.1.1.A7|Updates und Patches für Firmware, Betriebssystem und Anwendungen|basic
SYS.1.1.A9|Einsatz von Virenschutzprogrammen auf Servern|basic
SYS.1.1.A10|Protokollierung|basic
SYS.1.1.A11|Festlegung einer Sicherheitsrichtlinie für Server|standard
SYS.1.1.A12|Planung des Server-Einsatzes|standard
SYS.1.1.A35|Erstellung und Pflege eines Betriebshandbuchs|standard
SYS.1.1.A31|Hochverfügbarkeit durch Redundanz|elevated
# SYS.2.1|Allgemeiner Client|SYS|Grundlegende Absicherung von Arbeitsplatzrechnern
SYS.2.1.A1|Sichere Benutzendenauthentisierung|basic
SYS.2.1.A3|Aktivieren von Autoupdate-Mechanismen|basic
SYS.2.1.A6|Einsatz von Virenschutzprogrammen|basic
SYS.2.1.A8|Absicherung des Bootvorgangs|basic
SYS.2.1.A9|Festlegung einer Sicherheitsrichtlinie für Clients|standard
SYS.2.1.A42|Nutzung von Cloud- und Online-Funktionen|standard
SYS.2.1.A37|Verwendung von Multi-Faktor-Authentisierung|elevated
# NET.1.1|Netzarchitektur und -design|NET|Sichere Architektur und Segmentierung von Netzen
NET.1.1.A1|Sicherheitsrichtlinie für das Netz|basic
NET.1.1.A2|Dokumentation des Netzes|basic
NET.1.1.A3|Anforderungsspezifikation für das Netz|basic
NET.1.1.A4|Netztrennung in Sicherheitszonen|basic
NET.1.1.A5|Client-Server-Segmentierung|basic
NET.1.1.A6|Endgeräte-Segmentierung im internen Netz|basic
NET.1.1.A7|Absicherung von schützenswerten Informationen|basic
NET.1.1.A8|Grundlegende Absicherung des Internetzugangs|basic
NET.1.1.A9|Grundlegende Absicherung der Kommunikation mit nicht vertrauenswürdigen Netzen|basic
NET.1.1.A10|DMZ-Segmentierung für Zugriffe aus dem Internet|basic
NET.1.1.A13|Netzplanung|standard
NET.1.1.A14|Umsetzungsplanung|standard
NET.1.1.A15|Regelmäßiger Soll-Ist-Vergleich|standard
NET.1.1.A32|Physische Trennung von Management-Segmenten|elevated
# IND.2.1|Allgemeine ICS-Komponente|IND|Absicherung von Komponenten industrieller Steuerungssysteme
IND.2.1.A1|Einschränkung des Zugriffs auf Konfigurations- und Wartungsschnittstellen|basic
IND.2.1.A2|Nutzung sicherer Übertragungs- bzw. Kommunikationsprotokolle|basic
IND.2.1.A3|Zeitsynchronisation der ICS-Komponenten|standard
# INF.1|Allgemeines Gebäude|INF|Infrastrukturelle Absicherung von Gebäuden
INF.1.A1|Planung der Gebäudeabsicherung|basic
INF.1.A2|Angepasste Aufteilung der Stromkreise|basic
INF.1.A3|Einhaltung von Brandschutzvorschriften|basic
INF.1.A4|Branderkennung in Gebäuden|basic
INF.1.A5|Handfeuerlöscher|basic
INF.1.A6|Zutrittsregelung und -kontrolle|basic
INF.1.A10|Einhaltung einschlägiger DIN-Normen/VDE-Vorschriften|standard
INF.1.A12|Schlüsselverwaltung|standard
# INF.2|Rechenzentrum sowie Serverraum|INF|Absicherung von Räumen mit zentraler IT
INF.2.A1|Festlegung von Anforderungen|basic
INF.2.A2|Bildung von Brandabschnitten|basic
INF.2.A3|Einsatz einer unterbrechungsfreien Stromversorgung|basic
INF.2.A4|Notabschaltung der Stromversorgung|basic
INF.2.A5|Einhaltung der Lufttemperatur und -feuchtigkeit|basic
INF.2.A6|Zutrittskontrolle|basic
INF.2.A7|Verschließen und Sichern|basic
INF.2.A8|Einsatz einer Brandmeldeanlage|basic
INF.2.A11|Automatische Überwachung der Infrastruktur|basic
INF.2.A17|Einsatz einer Brandfrühesterkennung|standard
INF.2.A29|Redundante Netzwerkanbindung|elevated
`;

private enum threatsText = `
G 0.1|Feuer
G 0.2|Ungünstige klimatische Bedingungen
G 0.3|Wasser
G 0.4|Verschmutzung, Staub, Korrosion
G 0.5|Naturkatastrophen
G 0.6|Katastrophen im Umfeld
G 0.7|Großereignisse im Umfeld
G 0.8|Ausfall oder Störung der Stromversorgung
G 0.9|Ausfall oder Störung von Kommunikationsnetzen
G 0.10|Ausfall oder Störung von Versorgungsnetzen
G 0.11|Ausfall oder Störung von Dienstleistungsunternehmen
G 0.12|Elektromagnetische Störstrahlung
G 0.13|Abfangen kompromittierender Strahlung
G 0.14|Ausspähen von Informationen (Spionage)
G 0.15|Abhören
G 0.16|Diebstahl von Geräten, Datenträgern oder Dokumenten
G 0.17|Verlust von Geräten, Datenträgern oder Dokumenten
G 0.18|Fehlplanung oder fehlende Anpassung
G 0.19|Offenlegung schützenswerter Informationen
G 0.20|Informationen oder Produkte aus unzuverlässiger Quelle
G 0.21|Manipulation von Hard- oder Software
G 0.22|Manipulation von Informationen
G 0.23|Unbefugtes Eindringen in IT-Systeme
G 0.24|Zerstörung von Geräten oder Datenträgern
G 0.25|Ausfall von Geräten oder Systemen
G 0.26|Fehlfunktion von Geräten oder Systemen
G 0.27|Ressourcenmangel
G 0.28|Software-Schwachstellen oder -Fehler
G 0.29|Verstoß gegen Gesetze oder Regelungen
G 0.30|Unberechtigte Nutzung oder Administration von Geräten und Systemen
G 0.31|Fehlerhafte Nutzung oder Administration von Geräten und Systemen
G 0.32|Missbrauch von Berechtigungen
G 0.33|Personalausfall
G 0.34|Anschlag
G 0.35|Nötigung, Erpressung oder Korruption
G 0.36|Identitätsdiebstahl
G 0.37|Abstreiten von Handlungen
G 0.38|Missbrauch personenbezogener Daten
G 0.39|Schadprogramme
G 0.40|Verhinderung von Diensten (Denial of Service)
G 0.41|Sabotage
G 0.42|Social Engineering
G 0.43|Einspielen von Nachrichten
G 0.44|Unbefugtes Eindringen in Räumlichkeiten
G 0.45|Datenverlust
G 0.46|Integritätsverlust schützenswerter Informationen
G 0.47|Schädliche Seiteneffekte IT-gestützter Automatisierung
`;

unittest {
  auto c = new DBuiltinCatalogClient;
  assert(c.threats.length == 47);
  assert(c.modules.length >= 10);
  foreach (m; c.modules) assert(m.requirements.length > 0, m.code);
}
