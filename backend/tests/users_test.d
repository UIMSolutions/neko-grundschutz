/// User management and login use cases.
module users_test;

version (GrundschutzUnittest):

import std.exception : assertThrown;
import uim.myfiori.application.dtos;
import uim.myfiori.bootstrap;
import uim.myfiori.domain.exceptions;

private CreateUserInput user(string name, string role, string password = "sehr-geheim-1") {
  CreateUserInput i;
  i.userName = name;
  i.role = role;
  i.password = password;
  return i;
}

unittest {
  auto app = DApplicationContainer.inMemory;
  assert(!app.users.hasUsers);

  auto admin = app.users.create(user("Admin", "admin"));
  assert(admin.userName == "admin" && admin.scopes == ["Viewer", "Editor", "Admin"]);
  assert(app.users.hasUsers);
  assertThrown!ConflictException(app.users.create(user("admin", "viewer")));    // unique (case-insensitive)
  assertThrown!ValidationException(app.users.create(user("kurz", "viewer", "123")));  // password length
  assertThrown!ValidationException(app.users.create(user("x", "viewer")));     // user name rules
  assertThrown!ValidationException(app.users.create(user("anna", "superuser")));

  // login
  auto logged = app.users.authenticate("ADMIN", "sehr-geheim-1");
  assert(logged.ID == admin.ID && logged.lastLoginAt.length);
  assertThrown!AuthenticationFailedException(app.users.authenticate("admin", "falsch-falsch"));
  assertThrown!AuthenticationFailedException(app.users.authenticate("niemand", "sehr-geheim-1"));
  assertThrown!AuthenticationFailedException(app.users.authenticate("../x", "sehr-geheim-1"));

  // the last active administrator cannot be removed, demoted or deactivated
  UpdateUserInput demote;
  demote.role = "editor";
  assertThrown!ConflictException(app.users.update(admin.ID, demote));
  UpdateUserInput lock;
  lock.active = false;
  assertThrown!ConflictException(app.users.update(admin.ID, lock));
  assertThrown!ConflictException(app.users.remove(admin.ID));

  // deactivated users cannot log in
  auto anna = app.users.create(user("anna", "editor"));
  assert(anna.scopes == ["Viewer", "Editor"]);
  app.users.update(anna.ID, lock);
  assertThrown!AuthenticationFailedException(app.users.authenticate("anna", "sehr-geheim-1"));

  // password reset / own change
  app.users.setPassword(anna.ID, "ganz-neues-pw");
  UpdateUserInput unlock;
  unlock.active = true;
  app.users.update(anna.ID, unlock);
  app.users.authenticate("anna", "ganz-neues-pw");
  assertThrown!ValidationException(app.users.changeOwnPassword(anna.ID, "falsch-falsch", "noch-ein-pw-1"));
  app.users.changeOwnPassword(anna.ID, "ganz-neues-pw", "noch-ein-pw-1");
  app.users.authenticate("anna", "noch-ein-pw-1");

  // a second admin makes the first one removable
  UpdateUserInput promote;
  promote.role = "admin";
  app.users.update(anna.ID, promote);
  app.users.remove(admin.ID);
  assert(app.users.list.length == 1);

  // accounts are not part of the business data backup
  assert(app.storage.snapshot.get("users", null) is null);
}
