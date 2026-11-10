import ComposableArchitecture
import Foundation
import LabcordShared
import WatchConnectivity

public final class WatchConnectivitySession: NSObject, WatchConnectivitySessionManaging {
    nonisolated private let deliveryLock = NSLock()
    nonisolated(unsafe) private var handlingUserInfoCount = 0
    nonisolated(unsafe) private var lastHandledUserInfoAt: Date?
    nonisolated public let observerStore = WatchConnectivityObserverStore()
    public let experiments = WatchExperimentTransport()
    public let records = WatchRecordTransport()
    @MainActor public private(set) var activationFailed = false
    @MainActor public var remoteIntentHandler:
        (@MainActor (WatchRemoteIntentRequest) async -> WatchRemoteIntentResponse)?
    private var audioReceiptObservers: [UUID: AsyncStream<WatchAudioReceipt>.Continuation] = [:]
    private var latestAudioReceipts: [UUID: WatchAudioReceipt] = [:]

    nonisolated private func deliveryState(
        since start: Date
    ) -> (isHandling: Bool, handledRecently: Bool) {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        return (
            handlingUserInfoCount > 0,
            lastHandledUserInfoAt.map { $0 >= start.addingTimeInterval(-1) } ?? false
        )
    }

    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let failed = error != nil
        Task { @MainActor in
            self.activationFailed = failed
            if state == .activated { self.records.resend(session: session) }
        }
    }

    @MainActor public func retryActivation() {
        activationFailed = false
        activate()
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let data = message[WatchRemoteIntentRequest.messageKey] as? Data {
            Task { @MainActor in
                guard data.count <= 4_096,
                      let request = try? JSONDecoder().decode(
                        WatchRemoteIntentRequest.self, from: data
                      ),
                      let handler = self.remoteIntentHandler else {
                    replyHandler([:])
                    return
                }
                let result = await handler(request)
                let encoded = try? JSONEncoder().encode(result)
                replyHandler(encoded.map { [WatchRemoteIntentResponse.messageKey: $0] } ?? [:])
            }
            return
        }
        let data = message[WatchExperimentTransport.commandKey] as? Data
        Task { @MainActor in
            let response = data.flatMap { experiments.reply(to: $0) }
            replyHandler(response.map { [WatchExperimentTransport.responseKey: $0] } ?? [:])
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let snapshot = applicationContext[WatchExperimentTransport.snapshotKey] as? Data
        let screen = applicationContext[WatchExperimentTransport.screenKey] as? Data
        let record = applicationContext[WatchRecordTransport.snapshotKey] as? Data
        Task { @MainActor in
            if let snapshot { experiments.receiveSnapshot(snapshot) }
            if let screen { experiments.receiveScreen(screen) }
            if let record { records.receive(record) }
        }
    }

    public func audioReceipts() -> AsyncStream<WatchAudioReceipt> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            audioReceiptObservers[id] = continuation
            latestAudioReceipts.values.forEach { continuation.yield($0) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.audioReceiptObservers.removeValue(forKey: id) }
            }
        }
    }

    private func receiveAudioReceipt(_ data: Data) {
        guard data.count <= 200_000,
              let receipt = try? JSONDecoder().decode(WatchAudioReceipt.self, from: data),
              receipt.header.isValid else { return }
        if let previous = latestAudioReceipts[receipt.header.recordingID] {
            guard previous.header == receipt.header else { return }
            guard previous.savedRecordID == nil, !previous.isCancelled else { return }
            if let old = previous.transcript, let new = receipt.transcript,
               old.generationID == new.generationID, new.revision < old.revision { return }
        }
        if latestAudioReceipts[receipt.header.recordingID] != receipt {
            latestAudioReceipts[receipt.header.recordingID] = receipt
            audioReceiptObservers.values.forEach { $0.yield(receipt) }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        beginDelivery()
        observerStore.deliverUserInfo(userInfo) { self.finishDelivery() }
        let record = userInfo[WatchRecordTransport.snapshotKey] as? Data
        let receipt = userInfo["labcordAudioReceipt"] as? Data
        guard record != nil || receipt != nil else { return }
        beginDelivery()
        Task { @MainActor in
            defer { finishDelivery() }
            if let record { records.receive(record) }
            if let receipt { receiveAudioReceipt(receipt) }
        }
    }

    nonisolated private func beginDelivery() {
        deliveryLock.lock()
        handlingUserInfoCount += 1
        deliveryLock.unlock()
    }

    nonisolated private func finishDelivery() {
        deliveryLock.lock()
        handlingUserInfoCount -= 1
        lastHandledUserInfoAt = Date()
        deliveryLock.unlock()
    }

    public func waitForPendingUserInfo() async {
        activate()
        let start = Date()
        let deadline = start.addingTimeInterval(5)

        while !Task.isCancelled {
            guard let session else { return }

            let hasContentPending = session.hasContentPending
            let delivery = deliveryState(since: start)

            if session.activationState == .activated,
               !hasContentPending,
               !delivery.isHandling,
               delivery.handledRecently {
                return
            }

            guard Date() < deadline else { return }

            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}

extension WatchConnectivitySession: DependencyKey {
    public static let liveValue = WatchConnectivitySession()
}

extension DependencyValues {
    public var watchConnectivitySession: WatchConnectivitySession {
        get { self[WatchConnectivitySession.self] }
        set { self[WatchConnectivitySession.self] = newValue }
    }
}
