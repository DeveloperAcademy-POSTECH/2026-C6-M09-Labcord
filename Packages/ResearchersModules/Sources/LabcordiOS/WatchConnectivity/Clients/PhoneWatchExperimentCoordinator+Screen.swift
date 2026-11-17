import Foundation
import LabcordShared
import UIKit

extension PhoneWatchExperimentCoordinator {
    public func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            var ids = Set(states.keys)
            if let visibleExperimentID { ids.insert(visibleExperimentID) }
            if let id = currentScreen.experimentID { ids.insert(id) }
            for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
                if let snapshot = try? snapshot(id) { publish(snapshot) }
            }
            publishScreen()
            publishAvailableExperiments()
        }
    }

    public func updateScreen(_ candidate: WatchScreenSnapshot) {
        guard candidate.isValid else {
            lastScreenError = .invalidPayload
            return
        }
        guard currentScreen.revision == 0 || !candidate.hasSameContent(as: currentScreen) else {
            return
        }
        do {
            let updated = candidate.withRevision(try nextRevision())
            if currentScreen.destination != updated.destination
                || currentScreen.experimentID != updated.experimentID
                || currentScreen.stage != updated.stage {
                tokens.removeAll()
            }
            if pendingStartID != updated.experimentID { pendingStartID = nil }
            currentScreen = updated
            lastScreenError = nil
            publishScreen()
        } catch {
            lastScreenError = .storageFailed
        }
    }

    public func validPendingStartID() throws -> UUID? {
        guard let id = pendingStartID else { return nil }
        guard try client.watchState(id)?.experiment.status == .running,
              visibleExperimentID == nil || visibleExperimentID == id else {
            pendingStartID = nil
            return nil
        }
        return id
    }

    public func recordDidChange(_ record: WatchRecordSnapshot) {
        guard let experimentID = record.experimentID else { return }
        commandSubscriber?.yield(.recordChanged(experimentID))
    }

    func refreshedScreen() -> WatchScreenSnapshot {
        if currentScreen.revision == 0 { updateScreen(currentScreen) }
        return currentScreen.withRevision(currentScreen.revision)
    }

    func publishScreen() {
        guard currentScreen.revision > 0,
              let session = connectivity.session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(refreshedScreen()) else { return }
        var context = session.applicationContext
        context[WatchExperimentTransport.screenKey] = data
        do {
            try session.updateApplicationContext(context)
            lastScreenError = nil
        } catch {
            lastScreenError = .resultUnknown
        }
    }

    func availableExperiments() throws -> [WatchExperimentSummary] {
        try client.load().compactMap { entry in
            try client.watchState(entry.id)?.experiment
        }.filter { $0.status != .completed }
    }

    func publishAvailableExperiments() {
        guard let session = connectivity.session, session.activationState == .activated,
              let summaries = try? availableExperiments(),
              let data = try? JSONEncoder().encode(summaries) else { return }
        let key = WatchExperimentTransport.listSnapshotKey
        guard session.applicationContext[key] as? Data != data else { return }
        var context = session.applicationContext
        context[key] = data
        try? session.updateApplicationContext(context)
        if session.isReachable {
            session.sendMessage([key: data], replyHandler: { _ in }, errorHandler: { _ in })
        }
    }

    func navigate(_ command: WatchExperimentCommand) async throws -> WatchExperimentResponse {
        guard UIApplication.shared.isProtectedDataAvailable else {
            throw WatchExperimentError.phoneUnlockRequired
        }
        guard let candidate = command.screen, candidate.isValid,
              candidate.destination != .registration,
              command.experimentID == candidate.experimentID else {
            throw WatchExperimentError.invalidPayload
        }
        let current = refreshedScreen()
        guard current.revision > 0, lastScreenError != .storageFailed,
              lastScreenError != .invalidPayload else {
            throw WatchExperimentError.storageFailed
        }
        guard candidate.revision == current.revision else {
            throw WatchExperimentError.staleRevision
        }
        if command.discardTimerDraft == true {
            guard current.destination == .experiment, current.stage == .timerEditor,
                  candidate.destination == .experiment,
                  candidate.experimentID == current.experimentID,
                  candidate.stage == .timers || candidate.stage == .active else {
                throw WatchExperimentError.invalidPayload
            }
        }
        if let id = candidate.experimentID, try client.watchState(id) == nil {
            throw WatchExperimentError.experimentNotFound
        }
        guard let commandSubscriber else { throw WatchExperimentError.phoneBusy }
        let navigation = WatchExperimentCommand(
            requestID: command.requestID, operation: .navigate,
            experimentID: candidate.experimentID,
            screen: WatchScreenSnapshot(
                destination: candidate.destination, experimentID: candidate.experimentID,
                stage: candidate.stage, countdownEndsAt: candidate.countdownEndsAt,
                revision: candidate.revision, recordedAt: candidate.recordedAt,
                timerDraftSeconds: candidate.timerDraftSeconds
            ),
            discardTimerDraft: command.discardTimerDraft
        )
        try await withCheckedThrowingContinuation { continuation in
            completions[command.requestID] = continuation
            commandSubscriber.yield(.navigation(navigation))
        }
        return WatchExperimentResponse(
            requestID: command.requestID, phase: .completed, screen: refreshedScreen()
        )
    }

    func snapshot(_ id: UUID) throws -> WatchExperimentSnapshot {
        guard let state = try client.watchState(id) else {
            throw WatchExperimentError.experimentNotFound
        }
        try restoreSavedRecords(id)
        let active = visibleExperimentID == id
        if states[id] != state || sessionVisibility[id] != active {
            let next = try nextRevision()
            revisions[id] = next
            states[id] = state
            sessionVisibility[id] = active
        }
        return state.snapshot(
            revision: revisions[id] ?? 0, at: .now, phoneSessionActive: active
        )
    }

    func nextRevision() throws -> UInt64 {
        var previous: UInt64 = 0
        if FileManager.default.fileExists(atPath: revisionURL.path) {
            let data = try Data(contentsOf: revisionURL)
            guard let value = String(data: data, encoding: .utf8).flatMap(UInt64.init) else {
                throw WatchExperimentError.storageFailed
            }
            previous = value
        }
        guard previous < UInt64.max else { throw WatchExperimentError.storageFailed }
        let next = previous + 1
        try FileManager.default.createDirectory(
            at: revisionURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(String(next).utf8).write(
            to: revisionURL, options: [.atomic, .completeFileProtection]
        )
        return next
    }

    func publish(_ snapshot: WatchExperimentSnapshot) {
        guard let session = connectivity.session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        var context = session.applicationContext
        context[WatchExperimentTransport.snapshotKey] = data
        try? session.updateApplicationContext(context)
    }

}
