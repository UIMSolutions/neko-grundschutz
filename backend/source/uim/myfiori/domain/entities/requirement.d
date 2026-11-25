/// Anforderung of a module applied to a target object (one row of the IT-Grundschutz-Check).
module uim.myfiori.domain.entities.requirement;

@safe:

import std.datetime.systime : SysTime;
import std.string : strip;
import uim.myfiori.domain.entities.base;
import uim.myfiori.domain.enumerations;
import uim.myfiori.domain.exceptions;
import uim.myfiori.domain.types;

class DRequirement : DEntity {
  private EntityId _projectId;
  private EntityId _targetObjectId;
  private RequirementCode _code;
  private string _title;
  private RequirementLevel _level;
  private ImplementationStatus _status;
  private string _responsible;
  private string _note;       // Begründung / Umsetzungsbeschreibung
  private string _dueDate;    // ISO date (YYYY-MM-DD) for planned implementation, optional

  this(EntityId id, EntityId projectId, EntityId targetObjectId, RequirementCode code, string title,
      RequirementLevel level, ImplementationStatus status, string responsible, string note,
      string dueDate, SysTime createdAt, SysTime modifiedAt) {
    super(id, createdAt, modifiedAt);
    _projectId = requireText(projectId, "Project id");
    _targetObjectId = requireText(targetObjectId, "Target object id");
    _code = code;
    _title = requireText(title, "Requirement title", 500);
    _level = level;
    _status = status;
    _responsible = responsible;
    _note = note;
    _dueDate = validateDate(dueDate);
  }

  EntityId projectId() const pure nothrow @nogc { return _projectId; }
  EntityId targetObjectId() const pure nothrow @nogc { return _targetObjectId; }
  RequirementCode code() const pure nothrow @nogc { return _code; }
  string moduleCode() const { return _code.moduleCode.value; }
  string title() const pure nothrow @nogc { return _title; }
  RequirementLevel level() const pure nothrow @nogc { return _level; }
  ImplementationStatus status() const pure nothrow @nogc { return _status; }
  string responsible() const pure nothrow @nogc { return _responsible; }
  string note() const pure nothrow @nogc { return _note; }
  string dueDate() const pure nothrow @nogc { return _dueDate; }

  /**
   * Records the implementation status. "entbehrlich" and "nein" must be justified,
   * and basic requirements (Basis-Anforderungen) can never be dispensable.
   */
  void recordStatus(ImplementationStatus status, string note) {
    if ((status == ImplementationStatus.dispensable || status == ImplementationStatus.no) && note.strip.length == 0)
      throw new ValidationException("Status '" ~ label(status) ~ "' requires a justification");
    if (status == ImplementationStatus.dispensable && _level == RequirementLevel.basic)
      throw new ValidationException("Basic requirements (Basis-Anforderungen) cannot be dispensable");
    _status = status;
    _note = note;
    touch;
  }

  void assign(string responsible) { _responsible = responsible; touch; }
  void plan(string dueDate) { _dueDate = validateDate(dueDate); touch; }
  void retitle(string title) { _title = requireText(title, "Requirement title", 500); touch; }

  /// True when the requirement counts as fulfilled for the check.
  bool isFulfilled() const pure nothrow @nogc {
    return _status == ImplementationStatus.yes || _status == ImplementationStatus.dispensable;
  }

  private static string validateDate(string d) {
    import std.datetime.date : Date;
    auto v = d.strip;
    if (v.length == 0) return "";
    try Date.fromISOExtString(v);
    catch (Exception) throw new ValidationException("Invalid due date '" ~ d ~ "' (expected YYYY-MM-DD)");
    return v;
  }
}
