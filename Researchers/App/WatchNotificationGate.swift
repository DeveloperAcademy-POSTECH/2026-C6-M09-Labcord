import Foundation

/// Coordinates notification loads while a Watch command owns the visible session.
struct WatchNotificationGate: Equatable {
    enum Decision: Equatable {
        case ignore
        case deferUntilWatchFinishes
        case open
    }

    private(set) var experimentID: UUID?
    private(set) var token: UUID?
    private(set) var isDeferred = false

    mutating func begin(experimentID: UUID, token: UUID) {
        self.experimentID = experimentID
        self.token = token
        isDeferred = false
    }

    mutating func receive(experimentID: UUID, token: UUID, watchRequestPending: Bool) -> Decision {
        guard self.experimentID == experimentID, self.token == token else { return .ignore }
        guard !watchRequestPending else {
            isDeferred = true
            return .deferUntilWatchFinishes
        }
        self.experimentID = nil
        self.token = nil
        isDeferred = false
        return .open
    }

    mutating func takeDeferredExperiment() -> UUID? {
        guard isDeferred, let experimentID else { return nil }
        isDeferred = false
        return experimentID
    }
}
