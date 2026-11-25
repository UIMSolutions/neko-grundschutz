/// Technical logging and the audit trail for domain events.
module uim.myfiori.infrastructure.logging;

@safe:

import std.format : format;
import vibe.core.log;
import uim.myfiori.ports.messaging;

/// Applies the configured log level ("debug", "info", "warn", "error").
void configureLogging(string level) @trusted {
  switch (level) {
    case "trace": setLogLevel(LogLevel.trace); break;
    case "debug": setLogLevel(LogLevel.debug_); break;
    case "warn": setLogLevel(LogLevel.warn); break;
    case "error": setLogLevel(LogLevel.error); break;
    default: setLogLevel(LogLevel.info); break;
  }
}

/**
 * Event publisher writing every domain event to the log (audit trail) and
 * keeping the most recent events in memory for the web GUI activity feed.
 */
class DAuditLogPublisher : IDomainEventPublisher {
  private DomainEvent[] _recent;
  private size_t _capacity;

  this(size_t capacity = 100) { _capacity = capacity; }

  void publish(DomainEvent e) {
    logInfo("[audit] %s %s project=%s %s", e.type, e.aggregateId, e.projectId, e.details);
    _recent = e ~ _recent;
    if (_recent.length > _capacity) _recent = _recent[0 .. _capacity];
  }

  /// Most recent first.
  const(DomainEvent)[] recent(size_t max = 20) const {
    return _recent.length > max ? _recent[0 .. max] : _recent;
  }
}
