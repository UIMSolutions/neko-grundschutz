/**
 * Type-safe application configuration.
 * Precedence: backend/config/default.json → environment variables → VCAP_SERVICES.
 */
module uim.myfiori.infrastructure.configuration;

@safe:

import std.conv : to;
import std.file : exists, readText;
import std.path : buildPath;
import std.process : environment;
import std.string : toLower;
import vibe.data.json;

struct XsuaaConfig {
  string url;
  string clientId;
  string xsAppName = "grundschutz";
  string verificationKey;   // PEM public key used to verify RS256 JWTs
}

struct AppConfig {
  string host = "127.0.0.1";
  ushort port = 8080;
  string logLevel = "info";
  string storage = "json";                 // json | memory
  string dataFile = "data/grundschutz.json";
  string frontendDir = "../frontend";      // served under /ui/ for local development
  string publicDir = "public";
  bool authEnabled = false;
  int backupIntervalMinutes = 0;           // 0 = disabled
  string backupDir = "data/backups";
  int backupRetention = 30;                // number of backup files kept (0 = unlimited)
  size_t maxUploadMegabytes = 32;          // import / restore upload limit
  XsuaaConfig xsuaa;
}

/// Loads the configuration from `configDir`/default.json, the environment and VCAP_SERVICES.
AppConfig loadConfig(string configDir = "config") {
  AppConfig cfg;
  auto file = buildPath(configDir, "default.json");
  if (file.exists) applyJson(cfg, parseJsonString(readText(file), file));
  applyEnvironment(cfg, (string k) => environment.get(k, null));
  auto vcap = environment.get("VCAP_SERVICES", null);
  if (vcap.length) applyVcapServices(cfg, parseJsonString(vcap, "VCAP_SERVICES"));
  if (environment.get("VCAP_APPLICATION", null).length) cfg.host = "0.0.0.0";
  return cfg;
}

void applyJson(ref AppConfig cfg, Json j) {
  string s(string k, string d) { return j[k].type == Json.Type.string ? j[k].get!string : d; }
  cfg.host = s("host", cfg.host);
  if (j["port"].type == Json.Type.int_) cfg.port = j["port"].get!long.to!ushort;
  cfg.logLevel = s("logLevel", cfg.logLevel);
  cfg.storage = s("storage", cfg.storage);
  cfg.dataFile = s("dataFile", cfg.dataFile);
  cfg.frontendDir = s("frontendDir", cfg.frontendDir);
  cfg.publicDir = s("publicDir", cfg.publicDir);
  cfg.backupDir = s("backupDir", cfg.backupDir);
  if (j["backupRetention"].type == Json.Type.int_) cfg.backupRetention = j["backupRetention"].get!long.to!int;
  if (j["maxUploadMegabytes"].type == Json.Type.int_) cfg.maxUploadMegabytes = j["maxUploadMegabytes"].get!long.to!size_t;
  if (j["authEnabled"].type == Json.Type.bool_) cfg.authEnabled = j["authEnabled"].get!bool;
  if (j["backupIntervalMinutes"].type == Json.Type.int_) cfg.backupIntervalMinutes = j["backupIntervalMinutes"].get!long.to!int;
  if (j["xsuaa"].type == Json.Type.object) {
    auto x = j["xsuaa"];
    if (x["xsappname"].type == Json.Type.string) cfg.xsuaa.xsAppName = x["xsappname"].get!string;
  }
}

void applyEnvironment(ref AppConfig cfg, string delegate(string) @safe env) {
  if (auto v = env("GS_HOST")) cfg.host = v;
  if (auto v = env("GS_PORT")) cfg.port = v.to!ushort;
  if (auto v = env("PORT")) cfg.port = v.to!ushort;          // Cloud Foundry
  if (auto v = env("GS_LOG_LEVEL")) cfg.logLevel = v;
  if (auto v = env("GS_STORAGE")) cfg.storage = v;
  if (auto v = env("GS_DATA_FILE")) cfg.dataFile = v;
  if (auto v = env("GS_FRONTEND_DIR")) cfg.frontendDir = v;
  if (auto v = env("GS_PUBLIC_DIR")) cfg.publicDir = v;
  if (auto v = env("GS_AUTH")) cfg.authEnabled = v.toLower == "true" || v == "1";
  if (auto v = env("GS_BACKUP_INTERVAL")) cfg.backupIntervalMinutes = v.to!int;
  if (auto v = env("GS_BACKUP_DIR")) cfg.backupDir = v;
  if (auto v = env("GS_BACKUP_RETENTION")) cfg.backupRetention = v.to!int;
  if (auto v = env("GS_MAX_UPLOAD_MB")) cfg.maxUploadMegabytes = v.to!size_t;
}

/// Binds an XSUAA service instance; a bound XSUAA always enables authentication.
void applyVcapServices(ref AppConfig cfg, Json vcap) {
  if (vcap["xsuaa"].type != Json.Type.array || vcap["xsuaa"].length == 0) return;
  auto c = vcap["xsuaa"][0]["credentials"];
  string s(string k) { return c[k].type == Json.Type.string ? c[k].get!string : ""; }
  cfg.xsuaa.url = s("url");
  cfg.xsuaa.clientId = s("clientid");
  if (s("xsappname").length) cfg.xsuaa.xsAppName = s("xsappname");
  cfg.xsuaa.verificationKey = s("verificationkey");
  cfg.authEnabled = true;
}

unittest {
  AppConfig cfg;
  applyEnvironment(cfg, (string k) => k == "PORT" ? "9000" : k == "GS_AUTH" ? "true" : null);
  assert(cfg.port == 9000 && cfg.authEnabled);

  AppConfig c2;
  applyVcapServices(c2, parseJsonString(`{"xsuaa":[{"credentials":{"xsappname":"gs!t1","clientid":"sb-gs","verificationkey":"KEY","url":"https://uaa"}}]}`));
  assert(c2.authEnabled && c2.xsuaa.xsAppName == "gs!t1" && c2.xsuaa.verificationKey == "KEY");
}
