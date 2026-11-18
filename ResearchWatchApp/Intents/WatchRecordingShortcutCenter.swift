import Foundation
import LabcordShared
import OSLog
import WatchKit

private let logger = Logger(
    subsystem: "com.researchers.Researchers.watchkitapp", category: "WatchShortcut"
)

enum WatchRecordingShortcut: Sendable {
    case voice, photo, video

    init(_ kind: WatchRemoteIntentRequest.Kind) {
        switch kind {
        case .voice: self = .voice
        case .photo: self = .photo
        case .video: self = .video
        }
    }
}

/// Watch 단축어와 iPhone 단축어 요청을 현재 화면에 전달합니다.
/// 처리할 화면이 없으면 요청을 보관하지 않고 버려, 나중에 실험 화면에 들어갔을 때
/// 지난 요청이 뒤늦게 실행되지 않도록 합니다.
@MainActor
final class WatchRecordingShortcutCenter {
    /// 요청을 처리했으면 `true`를 반환합니다. `experimentID`가 `nil`이면 실험을 가리지 않습니다.
    typealias Handler = @MainActor (WatchRecordingShortcut, UUID?) -> Bool

    static let shared = WatchRecordingShortcutCenter()

    private var handlers: [UUID: Handler] = [:]

    private init() {}

    /// 화면의 `@State`에 보관하는 등록 정보입니다.
    /// 단축어 화면이 Watch 앱을 잠시 가려 `onDisappear`가 불려도 등록이 풀리지 않도록,
    /// 화면이 실제로 사라져 이 객체가 해제될 때 등록을 해제합니다.
    final class Registration {
        fileprivate let id: UUID

        fileprivate init(id: UUID) {
            self.id = id
        }

        isolated deinit {
            WatchRecordingShortcutCenter.shared.handlers[id] = nil
        }
    }

    func register(_ handler: @escaping Handler) -> Registration {
        let id = UUID()
        handlers[id] = handler
        return Registration(id: id)
    }

    @discardableResult
    func send(_ shortcut: WatchRecordingShortcut, experimentID: UUID? = nil) -> Bool {
        var isHandled = false
        for handler in handlers.values where handler(shortcut, experimentID) {
            isHandled = true
        }
        logger.info("""
            Shortcut \(String(describing: shortcut), privacy: .public): \
            app=\(Self.applicationState, privacy: .public) \
            handlers=\(self.handlers.count) handled=\(isHandled)
            """)
        return isHandled
    }

    func receive(_ request: WatchRemoteIntentRequest) -> WatchRemoteIntentResponse {
        let isHandled = request.expiresAt > .now
            && send(WatchRecordingShortcut(request.kind), experimentID: request.experimentID)
        return WatchRemoteIntentResponse(
            requestID: request.requestID,
            accepted: isHandled,
            message: isHandled
                ? "Watch에서 기록을 실행했어요."
                : "Watch 실험 화면에서 기록을 실행할 수 없어요."
        )
    }

    private static var applicationState: String {
        switch WKApplication.shared().applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}
