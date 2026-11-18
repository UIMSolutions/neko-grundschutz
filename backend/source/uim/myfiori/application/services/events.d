/// Helper for raising domain events from use cases.
module uim.myfiori.application.services.events;

@safe:

import std.datetime.systime : Clock;
import uim.myfiori.ports.messaging;

void raise(IDomainEventPublisher publisher, string type, string aggregateId, string projectId, string details = "") {
  if (publisher is null) return;
  publisher.publish(DomainEvent(type, aggregateId, projectId, details, Clock.currTime.toUTC.toISOExtString));
}
