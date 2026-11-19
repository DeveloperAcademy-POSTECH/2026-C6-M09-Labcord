import Foundation
import LabcordShared
import UIKit

extension PhoneWatchExperimentCoordinator {
    public func refresh(republishingAfterRecovery: Bool = false) {
        republishAfterRecovery = republishAfterRecovery || republishingAfterRecovery
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            refreshTask = nil
            guard let session = connectivity.session,
                  WatchConnectivityState(session).canTransfer else { return }
            let force = republishAfterRecovery
            republishAfterRecovery = false
            let activeID = visibleExperimentID ?? currentScreen.experimentID ?? pendingStartID
            publishScreen(force: force)
            if let activeID {
                if let snapshot = try? snapshot(activeID, restoringRecords: false) {
                    publish(snapshot, force: force)
                }
                if force { try? restoreSavedRecords(activeID) }
            }
            publishAvailableExperiments(force: force)
            connectivity.records.resend(experimentID: activeID, session: session, force: force)
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
            let updated = candidate.withRevision(try nextRevision(), epoch: stateEpoch)
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

    func publishScreen(force: Bool = false) {
        guard currentScreen.revision > 0, let session = connectivity.session,
              WatchConnectivityState(session).canTransfer,
              let data = try? contextEncoder().encode(currentScreen) else { return }
        var context = session.applicationContext
        let previous = (context[WatchExperimentTransport.screenKey] as? Data).flatMap {
            try? JSONDecoder().decode(WatchScreenSnapshot.self, from: $0)
        }
        if let previous, previous.epoch != stateEpoch {
            Self.removePreviousEpoch(from: &context)
        }
        context[WatchExperimentTransport.screenKey] = data
        do {
            try WatchConnectivityDiagnostics.updateContext(
                session, context: context, id: WatchExperimentTransport.screenKey, force: force
            )
            lastScreenError = nil
        } catch {
            lastScreenError = .resultUnknown
        }
    }

    func versionedExperiments() throws -> (
        summaries: [WatchExperimentSummary], version: WatchStateVersion
    ) {
        let summaries = try client.watchSummaries()
        if let lastPublishedList, lastPublishedList.summaries == summaries {
            return lastPublishedList
        }
        let list = (summaries, WatchStateVersion(epoch: stateEpoch, revision: try nextRevision()))
        lastPublishedList = list
        return list
    }

    func publishAvailableExperiments(force: Bool) {
        guard let session = connectivity.session, WatchConnectivityState(session).canTransfer,
              let list = try? versionedExperiments() else { return }
        let encoder = contextEncoder()
        let key = WatchExperimentTransport.listSnapshotKey
        let versionKey = WatchExperimentTransport.listVersionKey
        guard let version = try? encoder.encode(list.version),
              let data = try? encoder.encode(list.summaries) else { return }
        var context = session.applicationContext
        context[key] = data
        context[versionKey] = version
        let updated = try? WatchConnectivityDiagnostics.updateContext(
            session, context: context, id: key, force: force
        )
        if updated != false, WatchConnectivityState(session).canTransfer, session.isReachable {
            session.sendMessage(
                [key: data, versionKey: version], replyHandler: { _ in },
                errorHandler: { error in
                    WatchConnectivityDiagnostics.failure("list.failed", id: key, error: error)
                }
            )
        }
    }

    func clearPublishedState() {
        guard let session = connectivity.session, session.activationState == .activated else {
            return
        }
        var context = session.applicationContext
        Self.removePreviousEpoch(from: &context)
        context.removeValue(forKey: WatchExperimentTransport.screenKey)
        context.removeValue(forKey: WatchSessionOpenResponse.messageKey)
        _ = try? WatchConnectivityDiagnostics.updateContext(
            session, context: context, id: WatchExperimentTransport.screenKey
        )
    }

    private static func removePreviousEpoch(from context: inout [String: Any]) {
        context.removeValue(forKey: WatchExperimentTransport.snapshotKey)
        context.removeValue(forKey: WatchExperimentTransport.listSnapshotKey)
        context.removeValue(forKey: WatchExperimentTransport.listVersionKey)
        context.removeValue(forKey: WatchExperimentTransport.backgroundResponseKey)
        context.removeValue(forKey: WatchRecordTransport.snapshotKey)
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
        guard candidate.matchesRevision(of: current) else {
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
                timerDraftSeconds: candidate.timerDraftSeconds, epoch: candidate.epoch
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

    func snapshot(_ id: UUID, restoringRecords: Bool = true) throws -> WatchExperimentSnapshot {
        guard let state = try client.watchState(id) else {
            throw WatchExperimentError.experimentNotFound
        }
        if restoringRecords { try restoreSavedRecords(id) }
        let active = visibleExperimentID == id
        if states[id] != state || sessionVisibility[id] != active {
            let next = try nextRevision()
            revisions[id] = next
            states[id] = state
            sessionVisibility[id] = active
        }
        return state.snapshot(
            revision: revisions[id] ?? 0, at: .now, phoneSessionActive: active, epoch: stateEpoch
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

    func publish(_ snapshot: WatchExperimentSnapshot, force: Bool = false) {
        guard let session = connectivity.session, WatchConnectivityState(session).canTransfer
        else { return }
        let key = WatchExperimentTransport.snapshotKey
        if !force, let previous = session.applicationContext[key] as? Data,
           let value = try? JSONDecoder().decode(WatchExperimentSnapshot.self, from: previous),
           value.experiment.id == snapshot.experiment.id, value.revision == snapshot.revision,
           value.epoch == snapshot.epoch {
            return
        }
        guard let data = try? contextEncoder().encode(snapshot) else { return }
        _ = try? WatchConnectivityDiagnostics.updateContext(
            session, key: key, data: data, force: force
        )
    }

    private func contextEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}
