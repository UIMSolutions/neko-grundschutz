/**
 * Grundschutz project = Sicherheitskonzeption for one Informationsverbund.
 * Aggregate root: target objects, requirements and risks reference it by id.
 */
module uim.myfiori.domain.entities.project;

@safe:

import std.datetime.systime : SysTime;
import uim.myfiori.domain.entities.base;
import uim.myfiori.domain.enumerations;
import uim.myfiori.domain.exceptions;
import uim.myfiori.domain.types;

class DProject : DEntity {
  private string _name;
  private string _description;
  private string _scope;          // Geltungsbereich / Informationsverbund
  private string _owner;          // verantwortliche Person (ISB)
  private SecurityApproach _approach;
  private ProjectStatus _status;

  this(EntityId id, string name, string description, string scope_, string owner,
      SecurityApproach approach, ProjectStatus status, SysTime createdAt, SysTime modifiedAt) {
    super(id, createdAt, modifiedAt);
    _name = requireText(name, "Project name");
    _description = description;
    _scope = scope_;
    _owner = owner;
    _approach = approach;
    _status = status;
  }

  string name() const pure nothrow @nogc { return _name; }
  string description() const pure nothrow @nogc { return _description; }
  string scope_() const pure nothrow @nogc { return _scope; }
  string owner() const pure nothrow @nogc { return _owner; }
  SecurityApproach approach() const pure nothrow @nogc { return _approach; }
  ProjectStatus status() const pure nothrow @nogc { return _status; }

  bool isReadOnly() const pure nothrow @nogc { return _status == ProjectStatus.archived; }

  /// Throws if the project can no longer be changed.
  void ensureWritable() const {
    if (isReadOnly)
      throw new ConflictException("Project '" ~ _name ~ "' is archived and read-only");
  }

  // Setters are no-ops for unchanged values, so re-saving an archived project is harmless.
  void rename(string name) {
    auto v = requireText(name, "Project name");
    if (v == _name) return;
    ensureWritable; _name = v; touch;
  }
  void describe(string description) { if (description == _description) return; ensureWritable; _description = description; touch; }
  void changeScope(string scope_) { if (scope_ == _scope) return; ensureWritable; _scope = scope_; touch; }
  void assignOwner(string owner) { if (owner == _owner) return; ensureWritable; _owner = owner; touch; }
  void chooseApproach(SecurityApproach approach) { if (approach == _approach) return; ensureWritable; _approach = approach; touch; }

  /// Status transitions: planned → inProgress → completed → archived (completed may be reopened).
  void changeStatus(ProjectStatus next) {
    if (next == _status) return;
    immutable allowed = () {
      final switch (_status) {
        case ProjectStatus.planned: return next == ProjectStatus.inProgress || next == ProjectStatus.archived;
        case ProjectStatus.inProgress: return next == ProjectStatus.completed || next == ProjectStatus.archived;
        case ProjectStatus.completed: return next == ProjectStatus.inProgress || next == ProjectStatus.archived;
        case ProjectStatus.archived: return false;
      }
    }();
    if (!allowed)
      throw new ConflictException("Status change " ~ statusName(_status) ~ " -> " ~ statusName(next) ~ " is not allowed");
    _status = next;
    touch;
  }

  private static string statusName(ProjectStatus s) {
    import std.conv : to;
    return s.to!string;
  }
}
