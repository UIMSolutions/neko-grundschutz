/// Use cases for local user accounts (login, user management).
module uim.myfiori.application.usecases.users;

@safe:

import std.algorithm : count, map;
import std.array : array;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.uuid : randomUUID;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

enum minPasswordLength = 10;

class DUserUseCases : IUserUseCases {
  private IUserRepository _users;
  private IPasswordHasher _hasher;
  private IDomainEventPublisher _events;
  private string _dummyHash;   // equalises timing for unknown user names

  this(IUserRepository users, IPasswordHasher hasher, IDomainEventPublisher events) {
    _users = users;
    _hasher = hasher;
    _events = events;
  }

  bool hasUsers() { return _users.findAll.length > 0; }

  UserDto[] list() { return _users.findAll.map!(u => toDto(u)).array; }

  UserDto get(string id) { return toDto(load(id)); }

  UserDto findByUserName(string userName) {
    auto u = _users.findByUserName(normalizeUserName(userName));
    if (u is null) throw new EntityNotFoundException("User", userName);
    return toDto(u);
  }

  UserDto create(CreateUserInput input) {
    auto name = normalizeUserName(input.userName);
    if (_users.findByUserName(name) !is null)
      throw new ConflictException("Benutzer '" ~ name ~ "' existiert bereits");
    checkPassword(input.password);
    auto now = Clock.currTime.toUTC;
    auto u = new DUser(randomUUID.toString, name, input.displayName, "", parseEnum!UserRole(input.role),
        input.active, _hasher.hash(input.password), SysTime.init, now, now);
    u.changeEmail(input.email);
    _users.save(u);
    _events.raise("UserCreated", u.id, "", name ~ " (" ~ u.role.to!string ~ ")");
    return toDto(u);
  }

  UserDto update(string id, UpdateUserInput input) {
    auto u = load(id);
    auto wasAdmin = u.isAdmin;
    if (!input.displayName.isNull) u.rename(input.displayName.get);
    if (!input.email.isNull) u.changeEmail(input.email.get);
    if (!input.role.isNull) u.assignRole(parseEnum!UserRole(input.role.get));
    if (!input.active.isNull) u.activate(input.active.get);
    if (wasAdmin && !u.isAdmin) ensureAnotherAdmin(u.id);
    _users.save(u);
    _events.raise("UserChanged", u.id, "", u.userName);
    return toDto(u);
  }

  void setPassword(string id, string newPassword) {
    auto u = load(id);
    checkPassword(newPassword);
    u.changePasswordHash(_hasher.hash(newPassword));
    _users.save(u);
    _events.raise("UserPasswordReset", u.id, "", u.userName);
  }

  void changeOwnPassword(string id, string currentPassword, string newPassword) {
    auto u = load(id);
    if (!_hasher.verify(currentPassword, u.passwordHash))
      throw new ValidationException("Aktuelles Passwort ist falsch");
    if (currentPassword == newPassword)
      throw new ValidationException("Das neue Passwort muss sich vom bisherigen unterscheiden");
    checkPassword(newPassword);
    u.changePasswordHash(_hasher.hash(newPassword));
    _users.save(u);
    _events.raise("UserPasswordChanged", u.id, "", u.userName);
  }

  void remove(string id) {
    auto u = load(id);
    if (u.isAdmin) ensureAnotherAdmin(u.id);
    _users.remove(u.id);
    _events.raise("UserDeleted", u.id, "", u.userName);
  }

  UserDto authenticate(string userName, string password) {
    enum failure = "Benutzername oder Passwort ist falsch";
    DUser u;
    try u = _users.findByUserName(normalizeUserName(userName));
    catch (ValidationException) u = null;
    if (u is null) {
      // same work as for an existing user, so response time does not reveal valid names
      if (_dummyHash.length == 0) _dummyHash = _hasher.hash("dummy-password");
      _hasher.verify(password, _dummyHash);
      throw new AuthenticationFailedException(failure);
    }
    if (!_hasher.verify(password, u.passwordHash) || !u.active) {
      _events.raise("UserLoginFailed", u.id, "", u.userName);
      throw new AuthenticationFailedException(failure);
    }
    u.recordLogin();
    _users.save(u);
    return toDto(u);
  }

  // ------------------------------------------------------------------ helpers

  private DUser load(string id) {
    auto u = _users.findById(id);
    if (u is null) throw new EntityNotFoundException("User", id);
    return u;
  }

  /// The system must keep at least one active administrator.
  private void ensureAnotherAdmin(string exceptId) {
    if (_users.findAll.count!(o => o.id != exceptId && o.isAdmin) == 0)
      throw new ConflictException("Mindestens ein aktiver Administrator muss erhalten bleiben");
  }

  private static void checkPassword(string password) {
    if (password.length < minPasswordLength)
      throw new ValidationException("Das Passwort muss mindestens " ~ minPasswordLength.to!string ~ " Zeichen lang sein");
    if (password.length > 1024) throw new ValidationException("Das Passwort ist zu lang");
  }

  private static UserDto toDto(DUser u) {
    static string ts(SysTime t) { return t == SysTime.init ? "" : t.toUTC.toISOExtString; }
    return UserDto(u.id, u.userName, u.displayName, u.email, u.role.to!string, u.active, scopesOf(u.role),
        ts(u.lastLoginAt), ts(u.createdAt));
  }
}
