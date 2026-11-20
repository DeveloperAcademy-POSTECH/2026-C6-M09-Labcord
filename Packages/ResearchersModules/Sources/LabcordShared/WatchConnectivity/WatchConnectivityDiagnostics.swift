import Foundation
import OSLog
import WatchConnectivity

public struct WatchConnectivityState: Equatable, Sendable {
    public let activation: WCSessionActivationState
    public let installed: Bool?
    private let paired: Bool
    public let reachable: Bool

    public init(_ session: WCSession) {
        activation = session.activationState
        if activation == .activated {
            #if os(iOS)
            paired = session.isPaired
            installed = session.isWatchAppInstalled
            #else
            paired = true
            let independent = Bundle.main
                .object(forInfoDictionaryKey: "WKRunsIndependentlyOfCompanionApp") as? Bool
            installed = independent == true ? session.isCompanionAppInstalled : nil
            #endif
            reachable = session.isReachable
        } else {
            paired = false
            installed = nil
            reachable = false
        }
    }

    public var canTransfer: Bool { activation == .activated && paired && installed != false }

    public func recovered(from previous: Self?) -> Bool {
        canTransfer
            && (previous?.canTransfer != true || (reachable && previous?.reachable != true))
    }
}

public enum WatchConnectivityDiagnostics {
    private static let log = Logger(
        subsystem: "com.researchers.Researchers", category: "WatchConnectivity"
    )
    private static let traceKey = "labcord.transport.trace"

    public static func state(_ session: WCSession, event: String, error: Error? = nil) {
        let state = WatchConnectivityState(session)
        let installed = state.installed.map { String($0) } ?? "unknown"
        let active = state.activation == .activated
        let userInfo = active ? session.outstandingUserInfoTransfers.count : 0
        let files = active ? session.outstandingFileTransfers.count : 0
        log.notice("""
            session event=\(event, privacy: .public) activation=\(state.activation.rawValue) \
            installed=\(installed, privacy: .public) reachable=\(state.reachable) \
            userInfo=\(userInfo) files=\(files)
            """)
        if let error { failure("activation", id: "-", error: error) }
    }

    public static func event(_ event: String, id: String, bytes: Int = 0, depth: Int = 0) {
        log.info("""
            \(event, privacy: .public) id=\(id, privacy: .public) bytes=\(bytes) depth=\(depth)
            """)
    }

    public static func reply(id: String, since start: ContinuousClock.Instant, bytes: Int) {
        let duration = start.duration(to: .now).components
        let milliseconds = duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000
        log.info("command.reply id=\(id, privacy: .public) bytes=\(bytes) rttMs=\(milliseconds)")
    }

    public static func failure(_ event: String, id: String, error: Error) {
        let failure = error as NSError
        log.error("""
            \(event, privacy: .public) id=\(id, privacy: .public) \
            domain=\(failure.domain, privacy: .public) code=\(failure.code)
            """)
    }

    public static func received(_ payload: [String: Any]) {
        guard let id = traceID(payload) else { return }
        event("userInfo.received", id: id, bytes: payloadBytes(payload))
    }

    public static func receivedFile(_ metadata: [String: Any]?) {
        guard let id = traceID(metadata) else { return }
        event("file.received", id: id)
    }

    @MainActor @discardableResult
    public static func updateContext(
        _ session: WCSession, key: String, data: Data, force: Bool = false
    ) throws -> Bool {
        var context = session.applicationContext
        context[key] = data
        return try updateContext(session, context: context, id: key, force: force)
    }

    @discardableResult
    public static func updateContext(
        _ session: WCSession, context: [String: Any], id: String, force: Bool = false
    ) throws -> Bool {
        guard WatchConnectivityState(session).canTransfer else {
            throw WatchExperimentError.notReachable
        }
        guard force || !NSDictionary(dictionary: session.applicationContext).isEqual(to: context)
        else { return false }
        do {
            try session.updateApplicationContext(context)
            event("context.updated", id: id, bytes: payloadBytes(context))
            return true
        } catch {
            failure("context.failed", id: id, error: error)
            throw error
        }
    }

    @MainActor @discardableResult
    public static func queueUserInfo(_ payload: [String: Any], on session: WCSession?) -> Bool {
        guard let session, WatchConnectivityState(session).canTransfer else { return false }
        #if targetEnvironment(simulator)
        return false
        #else
        let outstanding = session.outstandingUserInfoTransfers
        if outstanding.contains(where: { transfer in
            var queued = transfer.userInfo
            queued.removeValue(forKey: traceKey)
            return NSDictionary(dictionary: queued).isEqual(to: payload)
        }) { return true }
        let id = UUID().uuidString
        var tagged = payload
        tagged[traceKey] = id
        let depth = outstanding.count + 1
        event("userInfo.queued", id: id, bytes: payloadBytes(payload), depth: depth)
        session.transferUserInfo(tagged)
        return true
        #endif
    }

    @MainActor
    public static func queueFile(_ url: URL, metadata: [String: Any], on session: WCSession) {
        guard WatchConnectivityState(session).canTransfer else { return }
        #if !targetEnvironment(simulator)
        let id = UUID().uuidString
        var tagged = metadata
        tagged[traceKey] = id
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let depth = session.outstandingFileTransfers.count + 1
        event("file.queued", id: id, bytes: bytes, depth: depth)
        session.transferFile(url, metadata: tagged)
        #endif
    }

    public static func finished(_ transfer: WCSessionUserInfoTransfer, error: Error?) {
        finish("userInfo", id: traceID(transfer.userInfo), error: error)
    }

    public static func finished(_ transfer: WCSessionFileTransfer, error: Error?) {
        finish("file", id: traceID(transfer.file.metadata), error: error)
    }

    private static func finish(_ kind: String, id: String?, error: Error?) {
        if let error {
            failure("\(kind).failed", id: id ?? "legacy", error: error)
        } else {
            event("\(kind).completed", id: id ?? "legacy")
        }
    }

    private static func traceID(_ payload: [String: Any]?) -> String? {
        guard let value = payload?[traceKey] as? String else { return nil }
        return UUID(uuidString: value)?.uuidString
    }

    private static func payloadBytes(_ payload: [String: Any]) -> Int {
        payload.values.reduce(0) { $0 + (($1 as? Data)?.count ?? 0) }
    }
}
