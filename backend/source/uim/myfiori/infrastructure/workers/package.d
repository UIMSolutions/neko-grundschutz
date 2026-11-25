/// Background tasks.
module uim.myfiori.infrastructure.workers;

@safe:

import core.time : minutes;
import vibe.core.core : setTimer, Timer;
import vibe.core.log;
import uim.myfiori.ports.services : IBackupService;

/// Periodically writes a complete backup into the backup directory (Datensicherung, CON.3).
class DBackupWorker {
  private IBackupService _backups;
  private int _intervalMinutes;
  private Timer _timer;

  this(IBackupService backups, int intervalMinutes) {
    _backups = backups;
    _intervalMinutes = intervalMinutes;
  }

  void start() {
    if (_intervalMinutes <= 0) return;
    logInfo("Backup worker: complete backup every %d min", _intervalMinutes);
    _timer = setTimer(_intervalMinutes.minutes, () nothrow {
      try logInfo("Backup written: %s", _backups.backupToFile("auto").name);
      catch (Exception e) logException(e, "Backup failed");
    }, true);
  }

  void stop() { if (_timer) _timer.stop(); }
}
