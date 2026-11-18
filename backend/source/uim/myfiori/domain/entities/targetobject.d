/// Zielobjekt of an Informationsverbund (process, application, IT system, room, ...).
module uim.myfiori.domain.entities.targetobject;

@safe:

import std.datetime.systime : SysTime;
import uim.myfiori.domain.entities.base;
import uim.myfiori.domain.enumerations;
import uim.myfiori.domain.types;

class DTargetObject : DEntity {
  private EntityId _projectId;
  private string _name;
  private TargetObjectKind _kind;
  private string _description;
  private ProtectionNeed _protectionNeed;
  private string _protectionRationale;   // Begründung der Schutzbedarfsfeststellung

  this(EntityId id, EntityId projectId, string name, TargetObjectKind kind, string description,
      ProtectionNeed protectionNeed, string protectionRationale, SysTime createdAt, SysTime modifiedAt) {
    super(id, createdAt, modifiedAt);
    _projectId = requireText(projectId, "Project id");
    _name = requireText(name, "Target object name");
    _kind = kind;
    _description = description;
    _protectionNeed = protectionNeed;
    _protectionRationale = protectionRationale;
  }

  EntityId projectId() const pure nothrow @nogc { return _projectId; }
  string name() const pure nothrow @nogc { return _name; }
  TargetObjectKind kind() const pure nothrow @nogc { return _kind; }
  string description() const pure nothrow @nogc { return _description; }
  ProtectionNeed protectionNeed() const pure nothrow @nogc { return _protectionNeed; }
  string protectionRationale() const pure nothrow @nogc { return _protectionRationale; }

  void rename(string name) { _name = requireText(name, "Target object name"); touch; }
  void describe(string description) { _description = description; touch; }
  void changeKind(TargetObjectKind kind) { _kind = kind; touch; }

  /// Schutzbedarfsfeststellung; a raised need must be justified.
  void assessProtectionNeed(ProtectionNeed need, string rationale) {
    import uim.myfiori.domain.exceptions : ValidationException;
    import std.string : strip;
    if (need.requiresRiskAnalysis && rationale.strip.length == 0)
      throw new ValidationException("A protection need above 'normal' requires a rationale");
    _protectionNeed = need;
    _protectionRationale = rationale;
    touch;
  }
}
