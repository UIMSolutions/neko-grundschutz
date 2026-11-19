/**
 * User account of the local login (used when no XSUAA is bound).
 * Roles are cumulative: an editor may also read, an admin may do everything.
 */
module uim.myfiori.domain.entities.user;

@safe:

import std.datetime.systime : SysTime, Clock;
import std.regex : ctRegex, matchFirst;
import std.string : strip, toLower;
import uim.myfiori.domain.entities.base;
import uim.myfiori.domain.exceptions;
import uim.myfiori.domain.types;

/// Role of a user; maps to the XSUAA scopes Viewer / Editor / Admin.
enum UserRole { viewer, editor, admin }

/// Scopes granted by a role (same names as the XSUAA role templates).
string[] scopesOf(UserRole role) pure nothrow {
  final switch (role) {
    case UserRole.viewer: return ["Viewer"];
    case UserRole.editor: return ["Viewer", "Editor"];
    case UserRole.admin: return ["Viewer", "Editor", "Admin"];
  }
}

/// Normalised login name: lower case, 3–64 of [a-z0-9._@-].
string normalizeUserName(string userName) {
  auto v = userName.strip.toLower;
  if (!matchFirst(v, ctRegex!(`^[a-z0-9][a-z0-9._@\-]{2,63}$`)))
    throw new ValidationException("Ungültiger Benutzername (3–64 Zeichen: a–z, 0–9, . _ - @)");
  return v;
}

class DUser : DEntity {
  private string _userName;
  private string _displayName;
  private string _email;
  private UserRole _role;
  private bool _active;
  private string _passwordHash;
  private SysTime _lastLoginAt;

  this(EntityId id, string userName, string displayName, string email, UserRole role, bool active,
      string passwordHash, SysTime lastLoginAt, SysTime createdAt, SysTime modifiedAt) {
    super(id, createdAt, modifiedAt);
    _userName = normalizeUserName(userName);
    _displayName = displayName.strip;
    _email = email.strip;
    _role = role;
    _active = active;
    _passwordHash = passwordHash;
    _lastLoginAt = lastLoginAt;
  }

  string userName() const pure nothrow @nogc { return _userName; }
  string displayName() const pure nothrow @nogc { return _displayName.length ? _displayName : _userName; }
  string rawDisplayName() const pure nothrow @nogc { return _displayName; }
  string email() const pure nothrow @nogc { return _email; }
  UserRole role() const pure nothrow @nogc { return _role; }
  bool active() const pure nothrow @nogc { return _active; }
  string passwordHash() const pure nothrow @nogc { return _passwordHash; }
  SysTime lastLoginAt() const pure nothrow { return _lastLoginAt; }
  bool isAdmin() const pure nothrow @nogc { return _active && _role == UserRole.admin; }

  void rename(string displayName) { if (displayName.strip == _displayName) return; _displayName = displayName.strip; touch; }
  void changeEmail(string email) {
    auto v = email.strip;
    if (v == _email) return;
    if (v.length > 255 || (v.length && !matchFirst(v, ctRegex!(`^[^@\s]+@[^@\s]+$`))))
      throw new ValidationException("Ungültige E-Mail-Adresse");
    _email = v; touch;
  }
  void assignRole(UserRole role) { if (role == _role) return; _role = role; touch; }
  void activate(bool active) { if (active == _active) return; _active = active; touch; }
  void changePasswordHash(string hash) {
    if (hash.length == 0) throw new ValidationException("Password hash must not be empty");
    _passwordHash = hash; touch;
  }
  /// Login bookkeeping, does not change modifiedAt.
  void recordLogin() { _lastLoginAt = Clock.currTime.toUTC; }
}

unittest {
  import std.exception : assertThrown;
  auto now = Clock.currTime.toUTC;
  auto u = new DUser("u1", " Admin ", "", "", UserRole.admin, true, "h", SysTime.init, now, now);
  assert(u.userName == "admin" && u.displayName == "admin" && u.isAdmin);
  assert(scopesOf(UserRole.editor) == ["Viewer", "Editor"]);
  assertThrown!ValidationException(normalizeUserName("a"));
  assertThrown!ValidationException(normalizeUserName("../etc"));
  assertThrown!ValidationException(u.changeEmail("no-mail"));
}
