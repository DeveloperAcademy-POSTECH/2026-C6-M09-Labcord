import ComposableArchitecture
import Foundation
import LabcordShared
import WatchConnectivity

public final class WatchConnectivitySession: NSObject, WatchConnectivitySessionManaging {
    private let lock = NSLock()
    private var stateObservers: [UUID: () -> Void] = [:]
    nonisolated public let observerStore = WatchConnectivityObserverStore()
    public let experiments = WatchExperimentTransport()
    public let records = WatchRecordTransport()
    public private(set) var lastAudioTransferError: WatchAudioError?
    private var didRetryActivation = false

    func addStateObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()

        lock.lock()
        stateObservers[id] = observer
        lock.unlock()

        activate()

        DispatchQueue.main.async {
            observer()
        }

        return id
    }

    func removeStateObserver(_ id: UUID) {
        lock.lock()
        stateObservers.removeValue(forKey: id)
        lock.unlock()
    }

    private func notifyStateObservers() {
        lock.lock()
        let observers = Array(stateObservers.values)
        lock.unlock()

        DispatchQueue.main.async {
            observers.forEach { $0() }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let succeeded = error == nil
        let shouldRetry = error != nil && session.activationState != .activated
        Task { @MainActor in
            if succeeded {
                self.didRetryActivation = false
            } else if shouldRetry, !self.didRetryActivation {
                self.didRetryActivation = true
                session.activate()
            }
            self.notifyStateObservers()
            self.records.resend(session: session)
        }
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.notifyStateObservers() }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.notifyStateObservers()
            self.records.resend(session: session)
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let data = message[WatchExperimentTransport.commandKey] as? Data
        let voiceStatus = message[WatchVoiceLiveStatus.messageKey] as? Data
        Task { @MainActor in
            if let voiceStatus { PhoneWatchAudioService.shared.receiveLiveStatus(voiceStatus) }
            let response = data.flatMap { experiments.reply(to: $0) }
            replyHandler(response.map { [WatchExperimentTransport.responseKey: $0] } ?? [:])
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let snapshot = applicationContext[WatchExperimentTransport.snapshotKey] as? Data
        let record = applicationContext[WatchRecordTransport.snapshotKey] as? Data
        Task { @MainActor in
            if let snapshot { experiments.receiveSnapshot(snapshot) }
            if let record { records.receive(record) }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        Task { @MainActor in
            replyHandler(await PhoneWatchAudioService.shared.reply(to: messageData))
        }
    }

    nonisolated public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["labcordAudioChunk"] as? Bool == true else { return }
        do {
            let retained = try WatchAudioReceiver.retainIncomingFile(file.fileURL)
            Task { @MainActor in
                do {
                    try await PhoneWatchAudioService.shared.receiveRetainedFile(retained)
                    lastAudioTransferError = nil
                } catch {
                    lastAudioTransferError = (error as? WatchAudioError) ?? .storageFailed
                }
            }
        } catch {
            let failure = (error as? WatchAudioError) ?? .storageFailed
            Task { @MainActor in self.lastAudioTransferError = failure }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        observerStore.deliverUserInfo(userInfo)
        let record = userInfo[WatchRecordTransport.snapshotKey] as? Data
        let audio = userInfo[PhoneWatchAudioService.messageKey] as? Data
        Task { @MainActor in
            if let record { records.receive(record) }
            if let audio {
                let receipt = await PhoneWatchAudioService.shared.reply(to: audio)
                if !receipt.isEmpty {
                    transferUserInfo([PhoneWatchAudioService.receiptKey: receipt])
                } else {
                    lastAudioTransferError = .invalidAudio
                }
            }
        }
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.notifyStateObservers() }
    }

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        Task { @MainActor in self.notifyStateObservers() }
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
