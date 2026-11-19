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
    private var connectionState: WatchConnectivityState?

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
        WatchConnectivityDiagnostics.state(session, event: "activation", error: error)
        let succeeded = error == nil && state == .activated
        let shouldRetry = error != nil && session.activationState != .activated
        Task { @MainActor in
            if succeeded {
                self.didRetryActivation = false
            } else if shouldRetry, !self.didRetryActivation {
                self.didRetryActivation = true
                session.activate()
            }
            self.connectionDidChange(session)
        }
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        WatchConnectivityDiagnostics.state(session, event: "watchState")
        Task { @MainActor in self.connectionDidChange(session) }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        WatchConnectivityDiagnostics.state(session, event: "reachability")
        Task { @MainActor in self.connectionDidChange(session) }
    }

    private func connectionDidChange(_ session: WCSession) {
        let state = WatchConnectivityState(session)
        guard state != connectionState else { return }
        let recovered = state.recovered(from: connectionState)
        connectionState = state
        notifyStateObservers()
        guard recovered else { return }
        self.session(session, didReceiveApplicationContext: session.receivedApplicationContext)
        PhoneWatchExperimentCoordinator.shared.refresh(republishingAfterRecovery: true)
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let confirmed = message[WatchSessionOpenRequest.confirmedMessageKey] as? Data
        if let request = confirmed ?? message[WatchSessionOpenRequest.messageKey] as? Data {
            Task { @MainActor in
                PhoneWatchExperimentCoordinator.shared.receiveOpenSessionRequest(
                    request, confirmed: confirmed != nil
                )
                replyHandler([:])
            }
            return
        }
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
        let backgroundCommand = applicationContext[
            WatchExperimentTransport.backgroundCommandKey
        ] as? Data
        let openRequest = applicationContext[WatchSessionOpenRequest.messageKey] as? Data
        let confirmedOpen = applicationContext[
            WatchSessionOpenRequest.confirmedMessageKey
        ] as? Data
        let snapshot = applicationContext[WatchExperimentTransport.snapshotKey] as? Data
        let screen = applicationContext[WatchExperimentTransport.screenKey] as? Data
        let record = applicationContext[WatchRecordTransport.snapshotKey] as? Data
        Task { @MainActor in
            PhoneWatchExperimentCoordinator.shared.receiveOpenSessionRequest(openRequest)
            PhoneWatchExperimentCoordinator.shared.receiveOpenSessionRequest(
                confirmedOpen, confirmed: true
            )
            receiveBackgroundListCommand(backgroundCommand)
            if let snapshot { experiments.receiveSnapshot(snapshot) }
            if let screen { experiments.receiveScreen(screen) }
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
        WatchConnectivityDiagnostics.receivedFile(file.metadata)
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
        WatchConnectivityDiagnostics.received(userInfo)
        let backgroundCommand = userInfo[
            WatchExperimentTransport.backgroundCommandKey
        ] as? Data
        let openRequest = userInfo[WatchSessionOpenRequest.messageKey] as? Data
        let confirmedOpen = userInfo[WatchSessionOpenRequest.confirmedMessageKey] as? Data
        observerStore.deliverUserInfo(userInfo)
        let record = userInfo[WatchRecordTransport.snapshotKey] as? Data
        let audio = userInfo[PhoneWatchAudioService.messageKey] as? Data
        let voiceStatus = userInfo[WatchVoiceLiveStatus.messageKey] as? Data
        Task { @MainActor in
            PhoneWatchExperimentCoordinator.shared.receiveOpenSessionRequest(openRequest)
            PhoneWatchExperimentCoordinator.shared.receiveOpenSessionRequest(
                confirmedOpen, confirmed: true
            )
            receiveBackgroundListCommand(backgroundCommand)
            if let record { records.receive(record) }
            if let voiceStatus { PhoneWatchAudioService.shared.receiveLiveStatus(voiceStatus) }
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

    @MainActor
    private func receiveBackgroundListCommand(_ data: Data?) {
        guard let data, data.count <= 4_096,
              let command = try? JSONDecoder().decode(
                  WatchExperimentCommand.self, from: data
              ), command.operation == .list,
              let session, WatchConnectivityState(session).canTransfer else { return }
        if let previous = session.applicationContext[
            WatchExperimentTransport.backgroundResponseKey
        ] as? Data, let response = try? JSONDecoder().decode(
            WatchExperimentResponse.self, from: previous
        ), response.requestID == command.requestID { return }
        guard let response = experiments.reply(to: data) else { return }

        _ = try? WatchConnectivityDiagnostics.updateContext(
            session, key: WatchExperimentTransport.backgroundResponseKey, data: response
        )
        #if !targetEnvironment(simulator)
        transferUserInfo([WatchExperimentTransport.backgroundResponseKey: response])
        #endif
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        WatchConnectivityDiagnostics.state(session, event: "inactive")
        Task { @MainActor in self.sessionDidDisconnect() }
    }

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        WatchConnectivityDiagnostics.state(session, event: "deactivated")
        Task { @MainActor in
            self.sessionDidDisconnect()
            session.activate()
        }
    }

    private func sessionDidDisconnect() {
        connectionState = nil
        notifyStateObservers()
    }

    nonisolated public func session(
        _ session: WCSession, didFinish transfer: WCSessionUserInfoTransfer, error: Error?
    ) {
        WatchConnectivityDiagnostics.finished(transfer, error: error)
        if error != nil, let data = transfer.userInfo[WatchRecordTransport.snapshotKey] as? Data {
            Task { @MainActor in self.records.retryOnRecovery(data) }
        }
    }

    nonisolated public func session(
        _ session: WCSession, didFinish transfer: WCSessionFileTransfer, error: Error?
    ) {
        WatchConnectivityDiagnostics.finished(transfer, error: error)
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
