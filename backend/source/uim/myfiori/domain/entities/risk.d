/// Risk of an elementary threat for a target object (BSI-Standard 200-3).
module uim.myfiori.domain.entities.risk;

@safe:

import std.datetime.systime : SysTime;
import std.string : strip;
import uim.myfiori.domain.entities.base;
import uim.myfiori.domain.enumerations;
import uim.myfiori.domain.exceptions;
import uim.myfiori.domain.services.riskassessment;
import uim.myfiori.domain.types;

class DRisk : DEntity {
  private EntityId _projectId;
  private EntityId _targetObjectId;
  private ThreatCode _threatCode;
  private string _title;
  private string _description;
  private Frequency _frequency;
  private Impact _impact;
  private RiskTreatment _treatment;
  private string _treatmentNote;

  this(EntityId id, EntityId projectId, EntityId targetObjectId, ThreatCode threatCode, string title,
      string description, Frequency frequency, Impact impact, RiskTreatment treatment,
      string treatmentNote, SysTime createdAt, SysTime modifiedAt) {
    super(id, createdAt, modifiedAt);
    _projectId = requireText(projectId, "Project id");
    _targetObjectId = requireText(targetObjectId, "Target object id");
    _threatCode = threatCode;
    _title = requireText(title, "Risk title", 500);
    _description = description;
    _frequency = frequency;
    _impact = impact;
    _treatment = treatment;
    _treatmentNote = treatmentNote;
  }

  EntityId projectId() const pure nothrow @nogc { return _projectId; }
  EntityId targetObjectId() const pure nothrow @nogc { return _targetObjectId; }
  ThreatCode threatCode() const pure nothrow @nogc { return _threatCode; }
  string title() const pure nothrow @nogc { return _title; }
  string description() const pure nothrow @nogc { return _description; }
  Frequency frequency() const pure nothrow @nogc { return _frequency; }
  Impact impact() const pure nothrow @nogc { return _impact; }
  RiskTreatment treatment() const pure nothrow @nogc { return _treatment; }
  string treatmentNote() const pure nothrow @nogc { return _treatmentNote; }

  /// Risikokategorie from the 4x4 matrix.
  RiskLevel level() const pure nothrow @nogc { return assessRisk(_frequency, _impact); }

  void describe(string title, string description) {
    _title = requireText(title, "Risk title", 500);
    _description = description;
    touch;
  }

  void evaluate(Frequency frequency, Impact impact) {
    _frequency = frequency;
    _impact = impact;
    touch;
  }

  /// Risikobehandlung. Accepting a high/very high risk requires a documented justification.
  void decideTreatment(RiskTreatment treatment, string note) {
    if (treatment == RiskTreatment.accept && level >= RiskLevel.high && note.strip.length == 0)
      throw new ValidationException("Accepting a '" ~ label(level) ~ "' risk requires a documented justification");
    _treatment = treatment;
    _treatmentNote = note;
    touch;
  }
}
