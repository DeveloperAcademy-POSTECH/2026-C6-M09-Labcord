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
}
