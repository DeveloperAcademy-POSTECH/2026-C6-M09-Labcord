import Foundation

enum PhoneIntentReadiness: Equatable {
    case wait, ready, contextChanged, busy, failed

    struct Input {
        var contextMatches: Bool
        var active: Bool
        var detailReady: Bool
        var cameraNeeded: Bool
        var cameraReady: Bool
        var cameraFailed: Bool
        var busy: Bool
    }

    static func decide(_ input: Input) -> Self {
        guard input.contextMatches else { return .contextChanged }
        guard input.active else { return .wait }
        guard !input.cameraFailed else { return .failed }
        guard !input.busy else { return .busy }
        guard input.detailReady, !input.cameraNeeded || input.cameraReady else { return .wait }
        return .ready
    }
}
