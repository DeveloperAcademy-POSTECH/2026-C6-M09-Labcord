import Foundation

enum PhoneIntentReadiness: Equatable {
    case wait, ready, busy, failed

    struct Input {
        var active: Bool
        var detailReady: Bool
        var cameraNeeded: Bool
        var cameraReady: Bool
        var cameraFailed: Bool
        var busy: Bool
    }

    static func decide(_ input: Input) -> Self {
        guard input.active else { return .wait }
        guard !input.cameraFailed else { return .failed }
        guard !input.busy else { return .busy }
        guard input.detailReady, !input.cameraNeeded || input.cameraReady else { return .wait }
        return .ready
    }

    static func photoRequestAccepted(
        requestID: UUID,
        currentRequestID: UUID?,
        isScheduled: Bool,
        isCapturing: Bool,
        hasCapturedData: Bool
    ) -> Bool {
        currentRequestID == requestID && (isScheduled || isCapturing || hasCapturedData)
    }
}
