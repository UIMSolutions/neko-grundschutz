/**
 * Entry point of the Grundschutz backend.
 *
 *   grundschutz serve          HTTP server (OData v4 + web GUI + Fiori app)
 *   grundschutz gui            server + desktop webview window
 *   grundschutz <command> ...  command line interface (see `grundschutz help`)
 */
module app;

import std.conv : to;
import std.process : environment;
import vibe.core.core : runApplication, runTask;
import vibe.core.log;

import uim.myfiori.bootstrap;
import uim.myfiori.infrastructure;
import uim.myfiori.presentation;

int main(string[] argv) {
  auto args = parseArgs(argv[1 .. $]);
  auto cfg = loadConfig(args.opt("config", environment.get("GS_CONFIG_DIR", "config")));
  if (args.flag("data")) cfg.dataFile = args.opt("data");
  if (args.flag("memory")) cfg.storage = "memory";
  if (args.flag("host")) cfg.host = args.opt("host");
  if (args.flag("port")) cfg.port = args.opt("port").to!ushort;

  auto serverMode = args.positional.length && (args.positional[0] == "serve" || args.positional[0] == "gui");
  // keep CLI output clean: only warnings/errors are logged outside of server mode
  configureLogging(serverMode ? cfg.logLevel : "warn");

  auto app = new DApplicationContainer(cfg);
  import std.functional : toDelegate;
  return new DCommandLine(app, toDelegate(&runServer)).run(args);
}

int runServer(DApplicationContainer app, bool openGui) @safe {
  app.seedAdminFromEnvironment();
  if (app.authGuard.loginEnabled && !app.users.hasUsers)
    logInfo("No user account yet: open /setup to create the first administrator");
  auto listener = startServer(app);
  auto backups = new DBackupWorker(app.backups, app.config.backupIntervalMinutes);
  backups.start();

  if (openGui) {
    auto host = app.config.host == "0.0.0.0" ? "127.0.0.1" : app.config.host;
    auto url = "http://" ~ host ~ ":" ~ app.config.port.to!string ~ "/web";
    runTask(() nothrow { try openWebView(url); catch (Exception e) logException(e, "Opening GUI failed"); });
  }

  string[] unrecognized;   // our own parser already handled the command line
  auto code = () @trusted { return runApplication(&unrecognized); }();
  backups.stop();
  listener.stopListening();
  app.storage.flush();
  app.userStorage.flush();
  return code;
}
